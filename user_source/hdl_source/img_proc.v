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
//      3 = Sobel 边缘 |Gx|+|Gy|，3x3 邻域，**晚 1 行 + 2 像素**（唯一有延迟的模式）
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
    input  wire [ 2:0] I_mode,      // 0=原图 1=灰度 2=二值化 3=Sobel
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
    //  Sobel 边缘检测（I_mode == 3）
    //
    //  ★ 这是本工程第一个"有延迟"的算法：3x3 邻域必须缓存前两行，
    //    输出比输入晚 **1 行 + 2 像素**。因为没有改动 hdmi_mixer 的时序，
    //    画面会整体下移 1 行（720 行里的 1 行，肉眼不可见），
    //    原因与三种补偿方案见 docs/算法添加方法.md §1。
    //
    //  行缓存：3 个轮转 RAM（每个 2048x8，让工具推断为 ERAM）
    //      行 y   写入 buf[y%3]，行 y-1 从 buf[(y-1)%3] 读，行 y-2 从 buf[(y-2)%3] 读
    //      三者互不冲突，每个 RAM 都是 1 读 1 写。
    //  卷积核（列：左=x-2, 中=x-1, 右=x）
    //      Gx = (B0-B2) + 2*(A0-A2) + (D0-D2)
    //      Gy = (D2+2D1+D0) - (B2+2B1+B0)
    //      |G| = |Gx| + |Gy|（省一次开方，工程常用）
    //==================================================================
    reg [10:0] S_lx;            // 行内像素序号 0..1279
    reg        S_de_d;
    reg [9:0]  S_ln;            // 本帧已收到的有效行数

    wire S_line_end = S_de_d & ~I_de;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_de_d <= 1'b0;
            S_lx   <= 11'd0;
            S_ln   <= 10'd0;
        end
        else begin
            S_de_d <= I_de;

            if (I_de)  S_lx <= S_lx + 1'b1;
            else       S_lx <= 11'd0;

            if (I_vs) begin
                S_ln  <= 10'd0;
            end
            else if (S_line_end) begin
                S_ln  <= S_ln + 1'b1;
            end
        end
    end

    // ---- 2 块 ping-pong 行缓存（2026-10-24 改写，目标：让 TD 推断成 ERAM）----
    //   行 y   写入 buf[y&1]
    //   行 y-1 从 buf[~y&1] 读   -> 不同块，无读写冲突
    //   行 y-2 从 buf[y&1]  读   -> 同块同地址，靠"读优先"语义拿到旧数据
    //   每块 RAM 只有 1 写 1 读，是 TD 推断 ERAM 的标准模板。
    //   （原来用 3 数组 + 3 路 case，被推断成 768 个 dram lut，贵得多。）
    // (* ramstyle = "block" *) 强制映射到 ERAM：2048x8 = 16,384 bit，一块 eram20k 装得下。
    // 不加属性时 TD 会选 LUTRAM（512 个 dram lut），加属性后应降到 0。
    (* ramstyle = "block" *) reg [7:0] S_lb0 [0:2047];
    (* ramstyle = "block" *) reg [7:0] S_lb1 [0:2047];

    reg [7:0] S_q1;             // 行 y-1 在 x 处的灰度
    reg [7:0] S_q2;             // 行 y-2 在 x 处的灰度
    wire      S_row_odd = S_ln[0];

    always @(posedge I_clk) begin
        if (I_de) begin
            if (!S_row_odd) begin
                S_q1 <= S_lb1[S_lx];          // y-1：另一块
                S_q2 <= S_lb0[S_lx];          // y-2：同块，读到旧数据
                S_lb0[S_lx] <= S_gray;        // 写当前行
            end
            else begin
                S_q1 <= S_lb0[S_lx];
                S_q2 <= S_lb1[S_lx];
                S_lb1[S_lx] <= S_gray;
            end
        end
    end

    // ---- 三行各一条 3 级像素延迟线，对齐到同一个 x 窗口 ----
    reg [7:0] S_g1;             // 当前行灰度，补 1 拍与 RAM 读出对齐
    always @(posedge I_clk) S_g1 <= S_gray;

    reg [7:0] A0, A1, A2;       // 行 y-1
    reg [7:0] B0, B1, B2;       // 行 y-2
    reg [7:0] D0, D1, D2;       // 行 y

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            A0 <= 8'd0; A1 <= 8'd0; A2 <= 8'd0;
            B0 <= 8'd0; B1 <= 8'd0; B2 <= 8'd0;
            D0 <= 8'd0; D1 <= 8'd0; D2 <= 8'd0;
        end
        else begin
            A2 <= A1; A1 <= A0; A0 <= S_q1;
            B2 <= B1; B1 <= B0; B0 <= S_q2;
            D2 <= D1; D1 <= D0; D0 <= S_g1;
        end
    end

    // ---- 卷积（全用无符号宽度，避免有符号运算的坑）----
    wire [12:0] S_gxp = {5'd0, B0} + {4'd0, A0, 1'b0} + {5'd0, D0};   // 正侧
    wire [12:0] S_gxn = {5'd0, B2} + {4'd0, A2, 1'b0} + {5'd0, D2};   // 负侧
    wire [12:0] S_gx  = (S_gxp >= S_gxn) ? (S_gxp - S_gxn) : (S_gxn - S_gxp);

    wire [12:0] S_gyp = {5'd0, D2} + {4'd0, D1, 1'b0} + {5'd0, D0};
    wire [12:0] S_gyn = {5'd0, B2} + {4'd0, B1, 1'b0} + {5'd0, B0};
    wire [12:0] S_gy  = (S_gyp >= S_gyn) ? (S_gyp - S_gyn) : (S_gyn - S_gyp);

    wire [12:0] S_gmag  = S_gx + S_gy;                                 // 最大 4*255 = 1020
    wire [7:0]  S_sobel = (S_gmag > 13'd255) ? 8'd255 : S_gmag[7:0];

    // 前两行行缓存还没填满，输出黑，避免上电首帧花屏
    //   行首 12 个像素也置黑：3x3 窗口左侧会取到上一行末尾的像素（行缓存地址绕回），
    //   产生巨大梯度饱和成 255 —— 实测左侧 x=0..5 六列全白，就是这个原因。
    wire S_sob_ok = (S_ln >= 10'd2) && (S_lx >= 11'd12);

    //==================================================================
    //  输出选择：纯组合 4 选 1
    //    mode 0/1/2 与输入严格同拍；mode 3 晚 1 行 + 2 像素（见上）
    //==================================================================
    assign O_data = (I_mode == 3'd0) ? I_data :
                    (I_mode == 3'd2) ? (S_bin ? 24'hFF_FF_FF : 24'h00_00_00) :
                    (I_mode == 3'd3) ? (S_sob_ok ? {S_sobel, S_sobel, S_sobel}
                                                 : 24'h00_00_00) :
                                       {S_gray, S_gray, S_gray};

endmodule
