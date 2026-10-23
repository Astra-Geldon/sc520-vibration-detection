//=====================================================================
//  img_mode_sel.v  ——  用板载 4 个按键选择图像处理模式
//
//  为什么单独一个模块
//      本功能是**附加**在显示通路上的，和摄像头采集（ISP/AWB/曝光）、振动链路、
//      HDMI 发射完全解耦：只读 4 个按键引脚，只输出 2 bit 模式码。
//      顶层用 `ifdef IMG_MODE_KEY 包住；注释掉那一个 `define 就退回
//      "编译期固定模式"，队友完全不受影响。
//
//  硬件（依据《新HX1P35A开发板手册》⑱、4 组按键）
//      KEY1..KEY4 = D5 / A9 / B9 / C7，**按下为低电平**，松开为高电平。
//      （本工程 pin.adc 里原有的 I_button[0]=N2 / I_button[1]=J14 经手册核对
//        不是板载按键，属历史遗留；为不影响 ae_set 等既有逻辑，这里不复用，
//        另开独立端口 I_key[3:0]。）
//
//  行为（按一下就锁定，不用一直按住）
//      KEY1 → 原图（直通）
//      KEY2 → 灰度
//      KEY3 → 二值化
//      KEY4 → 循环：原图 → 灰度 → 二值化 → 原图 …
//      上电默认取 MODE_RST。
//
//  时序
//      每个按键：两级同步（防亚稳态）→ 10ms 稳定计数去抖 → 去抖电平的下降沿
//      = 一次有效按下。长按只算一次。
//
//  板上验证（2026-10-23）
//      4 个按键全部实测正常，三种模式均可切换：
//        原图   mean≈107 / uniq≈27000（像素未被改动）
//        灰度   mean|R-G| = mean|G-B| = 0.000，三通道最大差 0，202 级灰阶
//        二值化 中间灰(32~224) = 0.01%，两级占比 99.28%
//=====================================================================
module img_mode_sel #(
    parameter integer MODE_RST = 0,         // 上电默认模式 0=原图 1=灰度 2=二值化
    parameter integer CLK_HZ   = 74250000,  // = S_hdmi_pixel_clk
    parameter integer DB_MS    = 10         // 去抖时间(ms)
)(
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire [3:0] I_key_n,      // {KEY4,KEY3,KEY2,KEY1}，按下=0
    output reg  [1:0] O_mode        // 0=原图 1=灰度 2=二值化
);

    localparam integer CNT_MAX = (CLK_HZ / 1000) * DB_MS;   // 10ms → 742,500
    localparam integer CNT_W   = 20;                        // 2^20 = 1,048,576

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
            O_mode <= MODE_RST;                             // 隐含截断到 2 bit
        end
        else if (S_press[0]) begin
            O_mode <= 2'd0;                                 // KEY1 原图
        end
        else if (S_press[1]) begin
            O_mode <= 2'd1;                                 // KEY2 灰度
        end
        else if (S_press[2]) begin
            O_mode <= 2'd2;                                 // KEY3 二值化
        end
        else if (S_press[3]) begin
            O_mode <= (O_mode >= 2'd2) ? 2'd0 : (O_mode + 2'd1);   // KEY4 循环
        end
    end

endmodule
