//=====================================================================
//  img_proc.v  ——  基础图像处理（基础要求 2.3(2)）
//
//  插入位置
//      video_out.O_vdieo_data ──► [img_proc] ──► hdmi_mixer.I_video_rd_data
//      时钟域：S_hdmi_pixel_clk（74.25 MHz），与 VTC / hdmi_mixer 同域，无需 CDC。
//
//  显示接口与邻域延迟
//      显示链路的时序对齐完全由 hdmi_mixer 内部的 2 级延迟决定：
//          S_video_data_1d/2d    ← I_video_rd_data
//          S_window_active_1d/2d ← I_video_de
//      mixer 假定「I_video_rd_data 与本拍的 de 对齐」。本模块只要保证
//      彩色/灰度保持零拍延迟；输出选择仍用组合 mux，不增加整条数据/DE流水级。
//      邻域模式有空间延迟：多数滤波窗口中心位于输入前1行、前1列，
//      Sobel保留原有延迟。这里不改 mixer / vtc / hdmi_tx。
//
//  像素格式：24-bit RGB888，R=[23:16]，G=[15:8]，B=[7:0]（与 video_out 一致）
//      灰度公式 (R + 2G + B) >> 2 与 vib_video_tap.v:200-204 完全相同，
//      这样"屏幕上看到的灰度"和振动链路里算的灰度是同一个定义。
//
//  模式（运行期 I_mode，由 img_mode_sel.v 从板载按键产生）
//      0 = 彩色     直通视觉增强输入
//      1 = 灰度     固定原图，g=(R+2G+B)>>2，输出 {g,g,g}
//      2 = 二值化   当前选择源的全局阈值 + 3x3黑白多数滤波（至少5票）
//      3 = Sobel 边缘 固定原图，|Gx|+|Gy|，3x3 邻域，**晚 1 行 + 2 像素**
//
//  运行期切换时各模式硬件同时存在；资源数以当前布局布线报告为准。
//  BIN_MAJORITY_EN=0可在编译期旁路多数滤波，保留旧的逐像素阈值行为。
//
//  关于阈值（重要，来自实测）
//      室内光照下传感器只输出约 34~43/255（README §6），实际调试中还遇到过
//      整幅 154/255 的亮场景。固定阈值 128 会全黑，所以用**上一帧均值**自适应：
//      1280x720 = 921600 = 4096*225；不能用 Σg>>20 代替均值（会低算约12.1%）。
//      在场消隐中计算 floor((Σg>>12)/225)，与 floor(Σg/921600) 完全等价。
//      16拍串行除法复用帧累加器，不增加像素通路延迟，也不使用DSP。
//      均值结果再做 1/4 帧间平滑：T_next = T + (T_raw-T)/4。
//      第一帧直接采用真实均值，后续小变化逐步跟随，减少构图变化造成的整幅跳变。
//      ★ 累加器**始终运行**（与当前模式无关），这样刚切到二值化时阈值就已经
//        是上一帧的真实均值，不会出现"切换后第一帧按复位值 48 判"的突变。
//        2026-10-21 实测确认：若阈值卡在 48，亮场景会输出 99.8% 白；
//        实测只有 43.5% 白 ⇒ 自适应链路确实在工作。
//=====================================================================
module img_proc #(
    parameter integer THRESH      = 48,     // 固定阈值（画面暗，取低）
    parameter integer ADAPT_EN    = 1,      // 二值化：用上一帧720p均值做自适应阈值
    parameter integer BIN_MAJORITY_EN = 1,  // 1=3x3多数滤波；0=旧逐像素二值化
    parameter integer TH_LOCK_EN = 0,      // 调试：允许运行时锁定当前实际阈值
    parameter integer GAUSSIAN_PRE_EN = 0, // 二值化前3x3轻高斯，复用Sobel邻域
    parameter integer BINARY_FIXED_EN = 0  // 1=固定增强源，释放运行时选源
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_vs,        // 场同步（自适应阈值用它切帧）
    input  wire        I_de,        // 像素有效
    input  wire [ 2:0] I_mode,      // 0=原图 1=灰度 2=二值化 3=Sobel
    input  wire [23:0] I_data,      // 显示端视觉增强后视频
    input  wire [23:0] I_raw_data,  // video_out 原图（已有 ISP AWB/Gamma）
    input  wire        I_src_raw,   // 仅二值化选源：1=原图，0=视觉增强后
    input  wire        I_th_lock,   // 请求锁定，下一VS上升沿生效（TH_LOCK_EN=1）
    output wire [23:0] O_data,      // 送 hdmi_mixer
    output wire [ 7:0] O_threshold, // 实际比较阈值：自动S_th或锁定值
    output wire        O_th_locked  // 已在帧间提交的锁定状态
);

    localparam [7:0] TH8 = THRESH;          // 显式截断，避免 32 位 integer 直接赋 8 位

    //==================================================================
    //  灰度：原图供显示/Sobel，二值化另选原图/增强灰度；全部为组合逻辑
    //      (R + 2G + B) >> 2，最大 1020 -> 10 bit
    //==================================================================
    // 灰度显示和Sobel取原图；最终二值化固定取增强数据。
    wire [9:0] S_gsum = {2'b0, I_raw_data[23:16]}
                      + {1'b0, I_raw_data[15:8], 1'b0}      // 2G
                      + {2'b0, I_raw_data[7:0]};
    wire [7:0] S_gray = S_gsum[9:2];
    wire [9:0] S_enh_gsum = {2'b0, I_data[23:16]}
                          + {1'b0, I_data[15:8], 1'b0}
                          + {2'b0, I_data[7:0]};
    wire [7:0] S_enh_gray = S_enh_gsum[9:2];
    wire [7:0] S_bin_gray = (BINARY_FIXED_EN != 0) ? S_enh_gray :
                             (I_src_raw ? S_gray : S_enh_gray);

    //==================================================================
    //  二值化阈值：始终累加，切模式时无需等待
    //      I_vs 上升沿 = 一帧有效像素已收完（VTC 的 vs 在 active 之后 5 行才拉高）
    //==================================================================
    reg  [7:0]  S_th;           // 当前二值模式所选输入的阈值
    // 有效期：28位帧灰度和。场消隐除法期：{余数[7:0], 被除数/商[15:0], 步数[3:0]}。
    // floor(sum/4096)<=57375；除以225的商<=255，余数<225。
    reg  [27:0] S_acc;
    reg         S_vs_d;
    reg         S_mean_busy;
    reg         S_th_valid;      // 首个有效均值到来后才启用帧间平滑

    wire [8:0] S_mean_trial = {S_acc[27:20], S_acc[19]};
    wire [8:0] S_mean_sub   = S_mean_trial - 9'd225;
    wire       S_mean_ge    = (S_mean_trial >= 9'd225);
    wire [7:0] S_mean_rem   = S_mean_ge ? S_mean_sub[7:0] : S_mean_trial[7:0];
    wire [7:0] S_mean_raw   = {S_acc[10:4], S_mean_ge};
    wire signed [8:0] S_th_delta = $signed({1'b0, S_mean_raw}) -
                                    $signed({1'b0, S_th});
    wire signed [8:0] S_th_step  = S_th_delta >>> 2;
    wire signed [9:0] S_th_smooth = $signed({1'b0, S_th}) + S_th_step;

    // 后台S_th持续更新。锁定只冻结比较器用值，解锁恢复最新自适应值。
    // 在VS上升沿提交请求；锁定捕获刚结束帧实际使用的S_th，整个有效帧同T。
    wire [7:0] S_global_threshold;
    generate
        if (TH_LOCK_EN != 0) begin : g_th_lock
            reg S_locked;
            reg [7:0] S_locked_threshold;
            always @(posedge I_clk or negedge I_rst_n) begin
                if (!I_rst_n) begin
                    S_locked <= 1'b0;
                    S_locked_threshold <= TH8;
                end
                else if (I_vs && !S_vs_d) begin
                    S_locked <= I_th_lock;
                    if (I_th_lock && !S_locked)
                        S_locked_threshold <= S_th;
                end
            end
            assign O_th_locked = S_locked;
            assign S_global_threshold = S_locked ? S_locked_threshold : S_th;
        end
        else begin : g_th_auto
            assign O_th_locked = 1'b0;
            assign S_global_threshold = S_th;
        end
    endgenerate

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_vs_d <= 1'b0;
            S_th   <= TH8;
            S_acc  <= 28'd0;
            S_mean_busy <= 1'b0;
            S_th_valid  <= 1'b0;
        end
        else begin
            S_vs_d <= I_vs;

            if (I_vs && !S_vs_d) begin
                if (ADAPT_EN != 0) begin
                    S_acc <= {8'd0, S_acc[27:12], 4'd0};
                    S_mean_busy <= 1'b1;
                end
                else begin
                    S_acc <= 28'd0;
                    S_mean_busy <= 1'b0;
                end
            end
            else if (S_mean_busy && (ADAPT_EN != 0)) begin
                // VTC在第725行进入VS，下一有效帧尚有25行，足够完成16拍除法。
                // 非阻塞赋值：末拍的商低8位={旧商低7位, 本拍商位}。
                if (S_acc[3:0] == 4'd15) begin
                    // 首帧不等待收敛；之后只跟随本帧均值的1/4，抑制全图跳变。
                    if (!S_th_valid)
                        S_th <= S_mean_raw;
                    else if (S_th_smooth[9])
                        S_th <= 8'd0;
                    else if (S_th_smooth > 10'd255)
                        S_th <= 8'd255;
                    else
                        S_th <= S_th_smooth[7:0];
                    S_th_valid <= 1'b1;
                    S_acc <= 28'd0;
                    S_mean_busy <= 1'b0;
                end
                else begin
                    S_acc <= {S_mean_rem, S_acc[18:4], S_mean_ge, (S_acc[3:0] + 4'd1)};
                end
            end
            else if (I_de && (ADAPT_EN != 0)) begin
                S_acc <= S_acc + {20'd0, S_bin_gray};
            end
        end
    end

    // 默认逐像素灰度；高斯分支在下方复用已存在的3x3邻域。
    wire [7:0] S_bin_gray_pre;
    wire S_bin = (S_bin_gray_pre >= O_threshold);

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

        assign O_threshold = S_global_threshold;

// ---- 2 块 ping-pong 行缓存（2026-10-24 改写，目标：让 TD 推断成 ERAM）----
    //   行 y   写入 buf[y&1]
    //   行 y-1 从 buf[~y&1] 读   -> 不同块，无读写冲突
    //   行 y-2 从 buf[y&1]  读   -> 同块同地址，靠"读优先"语义拿到旧数据
    //   每块 RAM 只有 1 写 1 读，是 TD 推断 ERAM 的标准模板。
    //   （原来用 3 数组 + 3 路 case，被推断成 768 个 dram lut，贵得多。）
    // TD模板使用 ram_style="bram"；原 ramstyle="block" 不被识别。
    // 仅改变物理存储映射，保留同步读取旧数据的行为与现有像素延迟。
    (* ram_style = "bram" *) reg [7:0] S_lb0 [0:2047];
    (* ram_style = "bram" *) reg [7:0] S_lb1 [0:2047];

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
    wire [14:0] S_gauss_sum = {2'd0, S_gxp} + {2'd0, S_gxn} +
                                {12'd0, B1, 1'b0} +
                                {12'd0, D1, 1'b0} +
                                {11'd0, A1, 2'b00};
    wire [7:0] S_gauss_gray = S_gauss_sum[11:4];
    wire S_gauss_valid = (S_ln >= 10'd2) && (S_lx >= 11'd2);
    // 邻域缓存和二值化均固定服务原图。
    assign S_bin_gray_pre = (GAUSSIAN_PRE_EN != 0) && S_gauss_valid ?
                            S_gauss_gray : S_bin_gray;

    // 前两行行缓存还没填满，输出黑，避免上电首帧花屏
    //   行首 12 个像素也置黑：3x3 窗口左侧会取到上一行末尾的像素（行缓存地址绕回），
    //   产生巨大梯度饱和成 255 —— 实测左侧 x=0..5 六列全白，就是这个原因。
    wire S_sob_ok = (S_ln >= 10'd2) && (S_lx >= 11'd12);

    // 黑白窗口独立于原图Sobel缓存，原图/增强二值化均使用同一套滤波硬件。
    // 活动帧内阈值恒定：多数滤波等价于灰度3x3中值后用同一T阈值化。
    wire S_bin_display;
    generate
        if (BIN_MAJORITY_EN != 0) begin : g_bin_majority
            binary_majority3x3 u_filter (
                .I_clk     ( I_clk     ),
                .I_rst_n   ( I_rst_n   ),
                .I_vs      ( I_vs      ),
                .I_de      ( I_de      ),
                .I_line_end( S_line_end),
                .I_x       ( S_lx      ),
                .I_y       ( S_ln      ),
                .I_src_raw ( I_src_raw ),
                .I_bit     ( S_bin     ),
                .O_bit     ( S_bin_display )
            );
        end
        else begin : g_bin_point
            assign S_bin_display = S_bin;
        end
    endgenerate

    //==================================================================
    //  输出选择：纯组合 4 选 1
    //    mode 0/1 同拍；mode 2有效窗中心晚1行+1像素；mode 3保持原有延迟。
    //==================================================================
    assign O_data = (I_mode == 3'd0) ? I_data :
                    (I_mode == 3'd2) ? (S_bin_display ? 24'hFF_FF_FF : 24'h00_00_00) :
                    (I_mode == 3'd3) ? (S_sob_ok ? {S_sobel, S_sobel, S_sobel}
                                                 : 24'h00_00_00) :
                                       {S_gray, S_gray, S_gray};

endmodule

// Coarse local adaptive threshold. Each 128x128 cell samples its central
// 32x32 patch; a 10x6 map covers all of 1280x720, including the bottom row.
// Double buffering prevents partial-frame maps from reaching the comparator.
// Bilinear interpolation removes tile steps; the half-global floor keeps
// uniformly dark objects from becoming white merely due to local adaptation.
module binary_majority3x3 (
    input wire I_clk,
    input wire I_rst_n,
    input wire I_vs,
    input wire I_de,
    input wire I_line_end,
    input wire [10:0] I_x,
    input wire [9:0] I_y,
    input wire I_src_raw,
    input wire I_bit,
    output wire O_bit
);
    // TD pads narrow 1-bit memories to byte width. Pack eight adjacent
    // pixels per word so the same 4096 bits use 256x8 rather than 2048x1.
    // Commit at column 7 of each byte; row-end also commits a partial byte.
    // Reads of row y-2 finish before its byte is overwritten at column 7.
    reg [7:0] S_lb0 [0:255];
    reg [7:0] S_lb1 [0:255];
    reg [7:0] S_pack;
    wire [7:0] S_read0 = S_lb0[I_x[10:3]];
    wire [7:0] S_read1 = S_lb1[I_x[10:3]];
    wire S_previous_row = I_y[0] ? S_read0[I_x[2:0]] : S_read1[I_x[2:0]];
    wire S_two_rows_ago = I_y[0] ? S_read1[I_x[2:0]] : S_read0[I_x[2:0]];
    wire [10:0] S_last_x = I_x - 11'd1;
    wire [7:0] S_write_address = I_de ? I_x[10:3] : S_last_x[10:3];
    wire [7:0] S_write_byte = I_de ? {I_bit, S_pack[6:0]} : S_pack;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) S_pack <= 8'd0;
        else if (!I_de || I_vs) S_pack <= 8'd0;
        else S_pack[I_x[2:0]] <= I_bit;
    end

    always @(posedge I_clk) begin
        if (!I_vs && ((I_de && (&I_x[2:0])) || I_line_end)) begin
            if (I_y[0]) S_lb1[S_write_address] <= S_write_byte;
            else        S_lb0[S_write_address] <= S_write_byte;
        end
    end

    reg [1:0] S_top_history, S_mid_history, S_bottom_history;
    reg S_src_d, S_frame_clean;
    wire S_source_changed = (I_src_raw != S_src_d);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_src_d <= 1'b0;
            S_frame_clean <= 1'b1;
            S_top_history <= 2'b00;
            S_mid_history <= 2'b00;
            S_bottom_history <= 2'b00;
        end
        else begin
            S_src_d <= I_src_raw;
            if (S_source_changed) S_frame_clean <= 1'b0;
            else if (I_vs)        S_frame_clean <= 1'b1;

            if (!I_de || I_vs || S_source_changed) begin
                S_top_history <= 2'b00;
                S_mid_history <= 2'b00;
                S_bottom_history <= 2'b00;
            end
            else begin
                S_top_history <= {S_top_history[0], S_two_rows_ago};
                S_mid_history <= {S_mid_history[0], S_previous_row};
                S_bottom_history <= {S_bottom_history[0], I_bit};
            end
        end
    end

    wire [1:0] S_top_count = {1'b0, S_two_rows_ago} +
                            {1'b0, S_top_history[0]} + {1'b0, S_top_history[1]};
    wire [1:0] S_mid_count = {1'b0, S_previous_row} +
                            {1'b0, S_mid_history[0]} + {1'b0, S_mid_history[1]};
    wire [1:0] S_bottom_count = {1'b0, I_bit} +
                               {1'b0, S_bottom_history[0]} + {1'b0, S_bottom_history[1]};
    wire [3:0] S_white_count = {2'b00, S_top_count} + {2'b00, S_mid_count} +
                              {2'b00, S_bottom_count};
    wire S_window_valid = I_de && !I_vs && S_frame_clean && !S_source_changed &&
                          (I_y >= 10'd2) && (I_x >= 11'd2);
    assign O_bit = S_window_valid ? (S_white_count >= 4'd5) : I_bit;
endmodule
