//=====================================================================
//  img_mode_sel.v  ——  用板载 4 个按键选择图像处理模式
//
//  为什么单独一个模块
//      本功能是**附加**在显示通路上的，和摄像头采集（ISP/AWB/曝光）、振动链路、
//      HDMI 发射完全解耦：只读 4 个按键引脚，只输出 3 bit 模式码。
//      顶层用 `ifdef IMG_MODE_KEY 包住；注释掉那一个 `define 就退回
//      "编译期固定模式"，队友完全不受影响。
//
//  硬件（依据《新HX1P35A开发板手册》⑱、4 组按键）
//      KEY1..KEY4 = D5 / A9 / B9 / C7，**按下为低电平**，松开为高电平。
//      （本工程 pin.adc 里原有的 I_button[0]=N2 / I_button[1]=J14 经手册核对
//        不是板载按键，属历史遗留；为不影响 ae_set 等既有逻辑，这里不复用，
//        另开独立端口 I_key[3:0]。）
//
//  按键分配（2026-10-23 按需求调整）
//      KEY1 (D5 / I_key[0]) → 原图（直通）
//      KEY2 (A9 / I_key[1]) → 基础算法组循环： 灰度 → 二值化 → 边缘 → 灰度 …
//                             当前是原图时，按下先进入灰度
//      KEY3 (B9 / I_key[2]) → 扩展算法组循环： 后续新加的算法
//                             ★ 目前 EXT_N = 0（还没加），按下无任何效果
//      KEY4 (C7 / I_key[3]) → 保留，暂不使用
//
//  模式编码（3 bit，最多 8 种）
//      0 = 原图
//      1 = 灰度
//      2 = 二值化
//      3 = Sobel 边缘
//      4..7 = 预留给"以后加进来的算法"，由 KEY3 循环
//
//  ★ 新增算法怎么接进来（详见 docs/算法添加方法.md）
//      1) img_proc.v 里加一个 I_mode 分支（新编码接着往下排）
//      2) osd_overlay.v 的字模 case 里登记 (起始字形, 字数)
//      3) tools/gen_osd_assets.py 的 CHARS 里追加汉字，重跑脚本
//      4) 回到本文件：把 EXT_N 加 1（必要时改 EXT_BASE）—— KEY3 立刻就能循环到它
//
//  时序
//      每个按键：两级同步（防亚稳态）→ 10ms 稳定计数去抖 → 去抖电平的下降沿
//      = 一次有效按下。长按只算一次。
//
//  板上验证（2026-10-23）
//      4 个按键全部实测正常，原图/灰度/二值化/边缘 均切换成功
//=====================================================================
module img_mode_sel #(
    parameter integer MODE_RST = 0,         // 上电默认模式
    parameter integer CLK_HZ   = 74250000,  // = S_hdmi_pixel_clk
    parameter integer DB_MS    = 10,        // 去抖时间(ms)

    // ---- 扩展算法组（KEY3 循环）----
    //   EXT_N = 0 表示"还没有扩展算法"，此时 KEY3 按下无效（整段被综合折叠掉）
    //   加了第 N 个扩展算法后，把 EXT_N 改成 N 即可
    parameter integer EXT_BASE = 4,         // 第一个扩展算法的模式码
    parameter integer EXT_N    = 0          // 扩展算法个数
)(
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire [3:0] I_key_n,      // {KEY4,KEY3,KEY2,KEY1}，按下=0
    output reg  [2:0] O_mode        // 见上面"模式编码"
);

    localparam integer CNT_MAX = (CLK_HZ / 1000) * DB_MS;   // 10ms → 742,500
    localparam integer CNT_W   = 20;                        // 2^20 = 1,048,576

    // 显式截断成 3 bit，避免对 integer 参数做 part-select
    localparam [2:0] RST3  = MODE_RST;
    localparam [2:0] EXT0  = EXT_BASE;
    localparam [2:0] EXTL  = EXT_BASE + EXT_N - 1;          // 最后一个扩展算法的编码

    wire [3:0] S_press;             // 每个按键的一次"有效按下"脉冲

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_key

            // ---- 两级同步 ----
            reg [1:0] S_sync;
            always @(posedge I_clk or negedge I_rst_n) begin
                if (!I_rst_n) S_sync <= 2'b11;              // 松开态
                else          S_sync <= {S_sync[0], I_key_n[gi]};
            end
            wire S_key_n = S_sync[1];

            // ---- 稳定计数去抖 ----
            reg [CNT_W-1:0] S_cnt;
            reg             S_level;        // 去抖后电平，1=松开 0=按下
            reg             S_level_d;

            always @(posedge I_clk or negedge I_rst_n) begin
                if (!I_rst_n) begin
                    S_cnt     <= {CNT_W{1'b0}};
                    S_level   <= 1'b1;
                    S_level_d <= 1'b1;
                end
                else begin
                    S_level_d <= S_level;

                    if (S_key_n != S_level) begin
                        if (S_cnt == CNT_MAX) begin
                            S_level <= S_key_n;             // 稳定够久，接受
                            S_cnt   <= {CNT_W{1'b0}};
                        end
                        else begin
                            S_cnt <= S_cnt + 1'b1;
                        end
                    end
                    else begin
                        S_cnt <= {CNT_W{1'b0}};
                    end
                end
            end

            assign S_press[gi] = S_level_d & ~S_level;       // 去抖后的下降沿

        end
    endgenerate

    //==================================================================
    //  模式锁存：按一下就定住，不需要一直按住
    //==================================================================
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_mode <= RST3;
        end

        // KEY1：原图
        else if (S_press[0]) begin
            O_mode <= 3'd0;
        end

        // KEY2：基础算法组循环 1 -> 2 -> 3 -> 1（在原图或扩展算法上按下则进入 1）
        else if (S_press[1]) begin
            if (O_mode == 3'd1)      O_mode <= 3'd2;
            else if (O_mode == 3'd2) O_mode <= 3'd3;
            else                     O_mode <= 3'd1;
        end

        // KEY3：扩展算法组循环；EXT_N = 0 时整段被折叠 -> 按键无效
        else if ((EXT_N > 0) && S_press[2]) begin
            if ((O_mode < EXT0) || (O_mode > EXTL))
                O_mode <= EXT0;                              // 不在扩展组里 -> 进入第一个
            else if (O_mode == EXTL)
                O_mode <= EXT0;                              // 转一圈
            else
                O_mode <= O_mode + 3'd1;
        end

        // KEY4：保留，暂不使用
    end

endmodule
