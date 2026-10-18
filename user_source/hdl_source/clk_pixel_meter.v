//=====================================================================
//  clk_pixel_meter.v  ——  实测 MIPI/ISP 域时钟频率与像素速率
//
//  为什么要它：
//    S_csi_rx_clk（MIPI RX byte 域，也是 ISP 与算法通路的时钟）的真实
//    频率决定了算法数据通路要做多宽。camera_to_dsi_display.sdc 写的是
//    MIPI 时钟通道 2.415ns（->828Mbps/lane），而 Python 工程 config.py 里
//    写的是 480Mbps/lane，两者矛盾。与其猜，不如在板上实测。
//
//  ★ 实测结论（2026-10-11，本板）：
//      S_csi_rx_clk = 74.43 MHz
//      像素率       = 54.93 Mpx/s   （1280x720x60 名义值 55.30 Mpx/s）
//      每像素时钟   = 1.355 个 csi 时钟（含消隐）
//                   = 1.009 个 csi 时钟（有效像素期间，消隐占 25.5%）
//    => 有效视频期间 ISP 基本就是"1 个 csi 时钟 1 个像素"，
//       所以 1 像素/时钟的数据通路可用，但**余量几乎为零，绝对不能停拍**。
//       （ISP 输出本来就没有反压，停拍就丢数据，所以抽头必须纯流式。）
//
//  ★ 128bit 拍里装的是什么（这个坑踩过一次，记下来）：
//      ISP 的 O_tdata[127:0] 是一条**连续的 24bit/像素**流，不是 4 个
//      RGB888 槽位。128/24 = 5.33 像素/拍，3 拍正好 16 个像素——带比特进位。
//      权威依据是 video_out.v:177-194 的解包逻辑（16 个像素跨 3 个字）。
//      实测校验：172800 拍/帧 x 16 字节 = 2_764_800 字节 = 1280x720x3 ✓
//      而 172800 = 720 行 x 240 拍/行（1280x3/16 = 240 拍/行，正好一行，
//      也正好是 video_in.v 用的 240 拍突发长度）
//
//  原理（全部是计数，不需要除法器）：
//    用稳定的板级 50MHz（I_sys_clk）做 1 秒基准窗口，在那个窗口里数：
//      csi_cnt  —— S_csi_rx_clk 的周期数        -> 就是它的频率(Hz)
//      px_cnt   —— 有效像素数（用比特相位累加得到精确值）
//      fs_cnt   —— 帧首脉冲数                   -> 每秒帧数
//      pxf_cnt  —— 上一完整帧内的像素数         -> 每帧像素数
//
//  跨时钟域：1 秒基准用 toggle 请求 / toggle 应答握手。
//
//  输出判读（在串口日志里，见 uart_log_debug.v）：
//      PXFR 必须恒等于 1280*720 = 921600 = 0x000E1000
//         —— 这是最强的一条自检：不对说明视频流规格不是 1280x720。
//      CSIH / PIXS 的比值 = 平均每像素有多少个 csi 时钟
//=====================================================================
module clk_pixel_meter #(
    parameter integer REF_HZ = 50_000_000,   // I_sys_clk 频率(Hz)，基准窗口 1 秒
    parameter integer IMG_W  = 1280,
    parameter integer IMG_H  = 720
)(
    input  wire        ref_clk,        // I_sys_clk = 50MHz（稳定基准）
    input  wire        ref_rst_n,      // I_rst_n
    input  wire        csi_clk,        // S_csi_rx_clk（被测时钟）
    input  wire        csi_rst_n,      // S_rst_n（= S_pll_lock）
    input  wire        beat_valid,     // S_ISP_O_tvalid（一个 128bit 拍）
    input  wire        frame_start,    // S_ISP_O_tuser

    output reg  [31:0] csi_hz,         // S_csi_rx_clk 实测频率(Hz)
    output reg  [31:0] px_per_sec,     // 每秒有效像素数
    output reg  [31:0] fps,            // 每秒帧数
    output reg  [31:0] px_per_frame    // 每帧有效像素数（应 = 0x000E1000）
);

    //------------------------------------------------------------------
    // ref 域：1 秒基准 + 采样请求（toggle 跨时钟域）
    //------------------------------------------------------------------
    reg  [31:0] ref_cnt;
    reg         req_tgl;
    wire        ref_tick = (ref_cnt == (REF_HZ - 1));

    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            ref_cnt <= 32'd0;
            req_tgl <= 1'b0;
        end
        else if (ref_tick) begin
            ref_cnt <= 32'd0;
            req_tgl <= ~req_tgl;
        end
        else begin
            ref_cnt <= ref_cnt + 32'd1;
        end
    end

    //------------------------------------------------------------------
    // csi 域：24bit 像素流的比特相位（每拍 128 bit）
    //   相位 < 16  -> 本拍出 5 个像素
    //   相位 >= 16 -> 本拍出 6 个像素
    //   验证：0->8(5个) ->16(5个) ->0(6个)，3 拍共 16 个像素 ✓
    //   一行 240 拍 x 128 bit = 30720 bit = 3840 字节 = 1280 像素，
    //   相位在一行结束时自然回到 0，不需要额外复位。
    //------------------------------------------------------------------
    reg  [8:0] bit_phase;                       // 0..23
    wire [2:0] px_of_beat  = (bit_phase < 9'd16) ? 3'd5 : 3'd6;
    // 24*px = px*16 + px*8
    wire [8:0] phase_next  = bit_phase + 9'd128
                             - {px_of_beat, 4'b0} - {px_of_beat, 3'b0};

    //------------------------------------------------------------------
    // csi 域：被测量计数
    //------------------------------------------------------------------
    reg  [31:0] csi_cnt;
    reg  [31:0] px_cnt;        // 1 秒窗口内像素数
    reg  [31:0] fs_cnt;
    reg  [31:0] pxf_cnt;       // 当前帧内像素数
    reg         prev_fs;
    wire        fs_rise = frame_start & ~prev_fs;

    // 采样请求同步进 csi 域，取上升沿做 1 拍采样脉冲
    reg  [1:0]  req_sync;
    reg         req_d;
    always @(posedge csi_clk or negedge csi_rst_n) begin
        if (!csi_rst_n) begin
            req_sync <= 2'b00;
            req_d    <= 1'b0;
        end
        else begin
            req_sync <= {req_sync[0], req_tgl};
            req_d    <= req_sync[1];
        end
    end
    wire snap = req_sync[1] ^ req_d;

    // 锁存保持寄存器：两次采样之间稳定 1 秒
    reg  [31:0] h_csi, h_px, h_fs, h_pxf;
    reg         ack_tgl;

    always @(posedge csi_clk or negedge csi_rst_n) begin
        if (!csi_rst_n) begin
            csi_cnt   <= 32'd0;
            px_cnt    <= 32'd0;
            fs_cnt    <= 32'd0;
            pxf_cnt   <= 32'd0;
            bit_phase <= 9'd0;
            prev_fs   <= 1'b0;
            h_csi     <= 32'd0;
            h_px      <= 32'd0;
            h_fs      <= 32'd0;
            h_pxf     <= 32'd0;
            ack_tgl   <= 1'b0;
        end
        else begin
            prev_fs <= frame_start;
            csi_cnt <= csi_cnt + 32'd1;              // 每个 csi 时钟 +1

            if (fs_rise) begin                       // 上一帧结束，锁存帧内像素数
                h_pxf   <= pxf_cnt;
                pxf_cnt <= 32'd0;
                fs_cnt  <= fs_cnt + 32'd1;
            end

            if (beat_valid) begin                    // 一个 128bit 拍
                bit_phase <= phase_next;
                px_cnt    <= px_cnt  + {29'd0, px_of_beat};
                pxf_cnt   <= pxf_cnt + {29'd0, px_of_beat};
            end

            if (snap) begin                          // 1 秒到：锁存并清零
                h_csi    <= csi_cnt;
                h_px     <= px_cnt;
                h_fs     <= fs_cnt;
                csi_cnt  <= 32'd0;
                px_cnt   <= 32'd0;
                fs_cnt   <= 32'd0;
                ack_tgl  <= ~ack_tgl;
            end
        end
    end

    //------------------------------------------------------------------
    // ref 域：等 csi 域应答后取回结果
    //------------------------------------------------------------------
    reg  [1:0]  ack_sync;
    reg         ack_d;
    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            ack_sync <= 2'b00;
            ack_d    <= 1'b0;
        end
        else begin
            ack_sync <= {ack_sync[0], ack_tgl};
            ack_d    <= ack_sync[1];
        end
    end
    wire ack_pulse = ack_sync[1] ^ ack_d;

    always @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            csi_hz       <= 32'd0;
            px_per_sec   <= 32'd0;
            fps          <= 32'd0;
            px_per_frame <= 32'd0;
        end
        else if (ack_pulse) begin
            csi_hz       <= h_csi;
            px_per_sec   <= h_px;      // 已是精确像素数，不需要再换算
            fps          <= h_fs;
            px_per_frame <= h_pxf;     // 应 = 921600 = 0x000E1000
        end
    end

endmodule
