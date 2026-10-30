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
//      KEY1 (D5 / I_key[0]) → 视觉增强彩色画面
//      KEY2 (A9 / I_key[1]) → 算法循环： 灰度 → 二值化 → 边缘 → 灰度 …
//      KEY3 (B9 / I_key[2]) → 曝光候选档循环（0/1/2/3）
//      KEY4 (C7 / I_key[3]) → 释放，无功能
//
//  模式编码（3 bit，最多 8 种）
//      0 = 原图
//      1 = 灰度
//      2 = 二值化
//      3 = Sobel 边缘
//      灰度和 Sobel 固定使用原图；二值化固定使用增强图像
//
//  ★ 新增算法怎么接进来（详见 docs/算法添加方法.md）
//      1) img_proc.v 里加一个 I_mode 分支（新编码接着往下排）
//      2) osd_overlay.v 的字模 case 里登记 (起始字形, 字数)
//      3) tools/gen_osd_assets.py 的 CHARS 里追加汉字，重跑脚本
//      4) 回到本文件：扩展 KEY2 的循环；KEY3 现在用于曝光候选档
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
    parameter integer EXP_RST  = 1,         // 上电曝光候选：1=1600

    // 兼容旧例化的保留参数，不再控制 KEY3；扩展算法需修改 KEY2 循环。
    parameter integer EXT_BASE = 4,         // 第一个扩展算法的模式码
    parameter integer EXT_N    = 0          // 扩展算法个数
)(
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire [3:0] I_key_n,      // {KEY4,KEY3,KEY2,KEY1}，按下=0
    output reg  [2:0] O_mode,       // 见上面"模式编码"
    output reg        O_src_raw,    // 二值化来源：1=原图，0=视觉增强视频
    output reg  [1:0] O_exp_sel,   // 曝光候选：0=1991, 1=1600, 2=1200, 3=900
    output reg        O_th_lock,    // 二值阈值锁定请求，img_proc在下一VS提交
    output wire       O_k_step      // 非二值化模式的KEY4单次脉冲，供顶层调校正强度
);

    localparam integer CNT_MAX = (CLK_HZ / 1000) * DB_MS;   // 10ms → 742,500
    localparam integer CNT_W   = 20;                        // 2^20 = 1,048,576

    // 显式截断成 3 bit，避免对 integer 参数做 part-select
    localparam [2:0] RST3  = MODE_RST;
    localparam [1:0] EXP_RST2 = EXP_RST;

    wire [3:0] S_press;             // 每个按键的一次"有效按下"脉冲

    genvar gi;
    generate
        // KEY4 释放，只对 KEY1~KEY3 做同步与去抖。
        for (gi = 0; gi < 3; gi = gi + 1) begin : g_key

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

    assign S_press[3] = 1'b0;

    // KEY4 已释放：不调整颜色校正，也不切换阈值锁定。
    assign O_k_step = 1'b0;

    //==================================================================
    //  模式锁存：按一下就定住，不需要一直按住
    //==================================================================
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_mode <= RST3;
            O_src_raw <= 1'b0;
            O_exp_sel <= EXP_RST2;
            O_th_lock <= 1'b0;
        end

        // KEY1：视觉增强彩色画面；保留二值化来源选择
        else if (S_press[0]) begin
            O_mode <= 3'd0;
        end

        // KEY2：基础算法组循环 1 -> 2 -> 3 -> 1
        else if (S_press[1]) begin
            if (O_mode == 3'd1)      O_mode <= 3'd2;
            else if (O_mode == 3'd2) O_mode <= 3'd3;
            else                     O_mode <= 3'd1;
        end

        // KEY3：循环曝光候选；最终二值化始终使用增强源，O_src_raw 保留兼容接口
        else if (S_press[2]) begin
            O_exp_sel <= O_exp_sel + 1'b1;
        end

        // KEY4 释放：O_th_lock 保持复位值 0。
    end

endmodule
