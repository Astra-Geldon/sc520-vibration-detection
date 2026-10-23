//=====================================================================
//  img_proc.v  ——  基础图像处理（基础要求 2.3(2)）
//
//  插入位置
//      video_out.O_vdieo_data ──► [img_proc] ──► hdmi_mixer.I_video_rd_data
//      时钟域：S_hdmi_pixel_clk（74.25 MHz），与 VTC / hdmi_mixer 同域，无需 CDC。
//
//  为什么必须"组合、零延迟"
//      显示链路的时序对齐完全由 hdmi_mixer 内部的 2 级延迟决定：
//          S_video_data_1d/2d    ← I_video_rd_data
//          S_window_active_1d/2d ← I_video_de
//      mixer 假定「I_video_rd_data 与本拍的 de 对齐」。本模块只要保证
//      输入到输出 **零拍延迟**，这条假定就天然成立，mixer / vtc / hdmi_tx
//      一行都不用改。一旦在这里插寄存器，画面就会整体错位（且行首错行），
//      所以输出选择一律用纯组合 mux 实现。
//
//  像素格式：24-bit RGB888，R=[23:16]，G=[15:8]，B=[7:0]（与 video_out 一致）
//      灰度公式 (R + 2G + B) >> 2 与 vib_video_tap.v:200-204 完全相同，
//      这样"屏幕上看到的灰度"和振动链路里算的灰度是同一个定义。
//
//  模式（运行期 I_mode，由 img_mode_sel.v 从板载按键产生）
//      0 = 原图     直通 I_data（不做任何改动，等价于不插本模块）
//      1 = 灰度     g=(R+2G+B)>>2，输出 {g,g,g}
//      2 = 二值化   g>=TH ? 白 : 黑，TH = ADAPT_EN ? (上一帧 Σg>>ADAPT_SHIFT) : THRESH
//
//  ★ 运行期切换的代价
//      三种模式的逻辑**同时存在**（不再靠编译期常量裁剪）。实测约
//      34 logic lut + 28 位 ripple + 36 FF，仍在"免费"量级。
//      若某次构建要极限省资源，把顶层的 `IMG_KEY_SW 注释掉、用 IMG_MODE
//      固定模式，即可回到"只综合一种模式"的旧行为。
//
//  关于阈值（重要，来自实测）
//      室内光照下传感器只输出约 34~43/255（README §6），实际调试中还遇到过
//      整幅 154/255 的亮场景。固定阈值 128 会全黑，所以用**上一帧均值**自适应：
//      1280x720 = 921600 像素，2^20 = 1048576，差 13.8%，均值误差 <1 LSB。
//      ★ 累加器**始终运行**（与当前模式无关），这样刚切到二值化时阈值就已经
//        是上一帧的真实均值，不会出现"切换后第一帧按复位值 48 判"的突变。
//        2026-10-21 实测确认：若阈值卡在 48，亮场景会输出 99.8% 白；
//        实测只有 43.5% 白 ⇒ 自适应链路确实在工作。
//=====================================================================
module img_proc #(
    parameter integer THRESH      = 48,     // 固定阈值（画面暗，取低）
    parameter integer ADAPT_EN    = 1,      // 二值化：用上一帧均值做自适应阈值
    parameter integer ADAPT_SHIFT = 20      // Σg >> 20 ≈ 帧均值
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_vs,        // 场同步（自适应阈值用它切帧）
    input  wire        I_de,        // 像素有效
    input  wire [ 1:0] I_mode,      // 0=原图 1=灰度 2=二值化
    input  wire [23:0] I_data,      // 来自 video_out
    output wire [23:0] O_data       // 送 hdmi_mixer
);

    localparam [7:0] TH8 = THRESH;          // 显式截断，避免 32 位 integer 直接赋 8 位

    //==================================================================
    //  灰度：三路共用，组合输出
    //      (R + 2G + B) >> 2，最大 1020 -> 10 bit
    //==================================================================
    wire [9:0] S_gsum = {2'b0, I_data[23:16]}
                      + {1'b0, I_data[15:8], 1'b0}      // 2G
                      + {2'b0, I_data[7:0]};
    wire [7:0] S_gray = S_gsum[9:2];

    //==================================================================
    //  二值化阈值：始终累加，切模式时无需等待
    //      I_vs 上升沿 = 一帧有效像素已收完（VTC 的 vs 在 active 之后 5 行才拉高）
    //==================================================================
    reg  [7:0]  S_th;           // 当前使用的阈值
    reg  [27:0] S_acc;          // 帧累加：1280*720*255 = 235,008,000 < 2^28
    reg         S_vs_d;

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
                // ADAPT_EN=0 时整段被折叠，阈值恒为 TH8
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

    wire S_bin = (S_gray >= S_th);

    //==================================================================
    //  输出选择：纯组合 3 选 1，零拍延迟
    //==================================================================
    assign O_data = (I_mode == 2'd0) ? I_data :
                    (I_mode == 2'd2) ? (S_bin ? 24'hFF_FF_FF : 24'h00_00_00) :
                                       {S_gray, S_gray, S_gray};

endmodule
