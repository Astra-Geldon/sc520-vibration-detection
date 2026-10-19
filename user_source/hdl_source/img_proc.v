//=====================================================================
//  img_proc.v  ——  基础图像处理（基础要求 2.3(2)）
//
//  插入位置
//      video_out.O_vdieo_data ──► [img_proc] ──► hdmi_mixer.I_video_rd_data
//      时钟域：S_hdmi_pixel_clk（75 MHz），与 VTC / hdmi_mixer 同域，无需 CDC。
//
//  为什么必须"组合、零延迟"（MODE=0/1/2）
//      显示链路的时序对齐完全由 hdmi_mixer 内部的 2 级延迟决定：
//          S_video_data_1d/2d    ← I_video_rd_data
//          S_window_active_1d/2d ← I_video_de
//      mixer 假定「I_video_rd_data 与本拍的 de 对齐」。本模块只要保证
//      输入到输出 **零拍延迟**，这条假定就天然成立，mixer / vtc / hdmi_tx
//      一行都不用改。一旦在这里插寄存器，画面就会整体错位（且行首错行），
//      所以 MODE=0/1/2 一律用纯组合 assign 实现。
//
//      注：Sobel（MODE=3）需要行缓存，必然带 1 行 + 若干像素的延迟，
//          留到边缘检测那一轮再加，届时用 generate 分支隔离，不影响前三种。
//
//  像素格式：24-bit RGB888，R=[23:16]，G=[15:8]，B=[7:0]（与 video_out 一致）
//      灰度公式 (R + 2G + B) >> 2 与 vib_video_tap.v:200-204 完全相同，
//      这样"屏幕上看到的灰度"和振动链路里算的灰度是同一个定义。
//
//  MODE
//      0 = 直通（调试用，等价于不插本模块）
//      1 = 灰度变换        g=(R+2G+B)>>2，输出 {g,g,g}
//      2 = 二值化          g=(R+2G+B)>>2，g>=TH ? 白 : 黑
//                          TH = ADAPT_EN ? (上一帧 Σg >> ADAPT_SHIFT) : THRESH
//      其它值（含暂未实现的 3）一律退化成灰度，避免"看起来像直通"而误判
//
//  关于阈值（重要，来自实测）
//      室内光照下传感器只输出约 43/255（README §6），固定阈值 128 会全黑。
//      所以默认 THRESH=48；而自适应用上一帧均值，能自动跟住亮度变化。
//      ADAPT_SHIFT 取 20 —— 一帧 1280x720 = 921600 像素，2^20 = 1048576，
//      两者差 13.8%，均值误差 <1 LSB，够用且省一个除法器。
//
//  资源（预估；实测值见 docs/plan/01 的「本轮记录」）
//      MODE=0/1  纯组合，约 25 LUT，0 FF，0 ERAM，0 DSP
//      MODE=2    约 70 LUT + 28 FF（仅 ADAPT_EN=1 时才有累加器）
//=====================================================================
module img_proc #(
    parameter integer MODE        = 1,      // 0=直通 1=灰度 2=二值化
    parameter integer THRESH      = 48,     // 固定阈值（画面暗，取低）
    parameter integer ADAPT_EN    = 1,      // 二值化：用上一帧均值做自适应阈值
    parameter integer ADAPT_SHIFT = 20      // Σg >> 20 ≈ 帧均值
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_vs,        // 场同步（仅自适应阈值用来切帧）
    input  wire        I_de,        // 像素有效
    input  wire [23:0] I_data,      // 来自 video_out
    output wire [23:0] O_data       // 送 hdmi_mixer
);

    //==================================================================
    //  灰度：三路共用，组合输出
    //      (R + 2G + B) >> 2，最大 1020 -> 10 bit
    //==================================================================
    wire [9:0] S_gsum = {2'b0, I_data[23:16]}
                      + {1'b0, I_data[15:8], 1'b0}      // 2G
                      + {2'b0, I_data[7:0]};
    wire [7:0] S_gray = S_gsum[9:2];

    //==================================================================
    //  MODE 分支：未选中的分支被常量折叠剪掉，不占资源
    //    O_data 只在被选中的分支里驱动，保证单驱动
    //==================================================================
    generate
        //--------------------------------------------------------------
        //  0：直通
        //--------------------------------------------------------------
        if (MODE == 0) begin : g_bypass
            assign O_data = I_data;

        //--------------------------------------------------------------
        //  2：二值化
        //--------------------------------------------------------------
        end
        else if (MODE == 2) begin : g_binary
            localparam [7:0] TH8 = THRESH;   // 显式截断，避免 32 位 integer 直接赋给 8 位寄存器

            reg  [7:0]  S_th;           // 当前使用的阈值
            reg  [27:0] S_acc;          // 帧累加：1280*720*255 = 235,008,000 < 2^28
            reg         S_vs_d;

            // I_vs 上升沿 = 一帧有效像素已收完（VTC 的 vs 在 active 之后 5 行才拉高）：
            // 用刚结束那一帧的均值更新下一帧的阈值
            always @(posedge I_clk or negedge I_rst_n) begin
                if (!I_rst_n) begin
                    S_vs_d <= 1'b0;
                    S_th   <= TH8;
                    S_acc  <= 28'd0;
                end
                else begin
                    S_vs_d <= I_vs;

                    if (I_vs && !S_vs_d) begin
                        S_acc <= 28'd0;
                        // ADAPT_EN=0 时整段被折叠，不产生累加器
                        if (ADAPT_EN != 0) begin
                            if ((S_acc >> ADAPT_SHIFT) > 28'd255)
                                S_th <= 8'd255;
                            else
                                S_th <= S_acc[ADAPT_SHIFT +: 8];
                        end
                    end
                    else if (I_de && (ADAPT_EN != 0)) begin
                        S_acc <= S_acc + {20'd0, S_gray};
                    end
                end
            end

            assign O_data = (S_gray >= S_th) ? 24'hFF_FF_FF : 24'h00_00_00;

        //--------------------------------------------------------------
        //  1 及其它：灰度（默认分支，故意让未实现的 MODE 显示成灰度）
        //--------------------------------------------------------------
        end
        else begin : g_gray
            assign O_data = {S_gray, S_gray, S_gray};
        end
    endgenerate

endmodule
