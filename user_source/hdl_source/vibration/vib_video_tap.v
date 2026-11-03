//=====================================================================
//  vib_video_tap.v  ——  从 ISP 输出抽头，灰度化 + 2x2 盒式降采样
//
//  位置：只读监听 S_ISP_O_tvalid / tdata / tuser / tlast（S_csi_rx_clk 域）
//        **不产生任何 ready / 反压**——ISP 输出本来就没有反压（顶层
//        S_ISP_O_tready 悬空未驱动），所以抽头绝不可能拖慢显示通路。
//
//  输入规格（这一点踩过坑，务必看清）：
//      S_ISP_O_tdata[127:0] 是一条**连续的 24bit/像素**流，不是 4 个 32bit
//      槽位。128/24 = 5.33 像素/拍，3 拍正好 16 个像素，**带比特进位**。
//      权威依据：video_out.v:177-194 用 16 个周期跨 3 个字解出 16 个像素。
//      板上实测已确认：PXFR/每帧像素数 = 0x000E1000 = 921600 ✓
//                172800 拍/帧 = 720 行 x 240 拍/行（1280x3/16 = 240）
//      ⚠ 老工程的 isp128_to_rgb_stream.v 按 4 个 32bit 槽位取，既丢 25% 像素
//        又错位，不能用。
//
//  输出：640x360 灰度（8bit），**覆盖整幅画面**（全屏识别，不做固定 ROI）
//
//  ★★ 最重要的一条：拍缓存必须够深（曾经只用 4 深，导致只收到 26% 数据）★★
//      ISP 不是均匀吐拍的，而是**按"一整行 240 拍"成串吐出来**的
//      （旁证：video_in.v 给同一路信号配的就是 512 深 FIFO，且要攒够 240 拍
//        才启动一次 DDR 写——那个深度和触发值本来就是为这个突发模式准备的）。
//      抽头每个 128bit 拍要 5.33 个时钟才能消化完，所以突发期间根本追不上：
//          用 4 深 FIFO：每行只能截获 45(突发期消化) + 4(FIFO) = 49/240 = 20.4%
//          板上实测总截获率                                   = 19.6%  ← 吻合
//      改用工程里现成的 w128_d512_fifo（512 深）后，一整行的 240 拍
//      可以完整缓存下来，突发结束后再慢慢消化。
//
//  读时序：w128_d512_fifo 的 dout 在 re 之后 1 拍有效（video_in.v 就是这么用的：
//          re 在 N 拍、O_ddr_user_wr_data 在 N+1 拍被 mc_to_user_interface 取走）。
//          所以这里做一级预取：pre_go -> fifo_re -> 下一拍锁存 d_pre。
//          相位长 5~6 拍，预取只需 2~3 拍，余量充足。
//
//  相位/进位自同步：
//      一行 240 拍 x 128bit = 30720bit = 1280 像素，240 mod 3 = 0，
//      所以每行开始时相位和进位都自然回到 0；行消隐期间 FIFO 也会排空，
//      这里就利用"FIFO 空且空闲"把相位/进位复位成 0，简单且自校正。
//
//  自检（走串口日志，见 uart_log_debug.v）：
//      VOFP 每帧输出像素数，必须恒等于 640*360 = 230400 = 0x00038400
//      VOFL 每帧输出行数，  必须恒等于 360 = 0x00000168
//      VSUM 每帧灰度累加和（松耦合校验，应非 0）
//      VTAP 异常计数，必须 = 0
//=====================================================================
module vib_video_tap (
    input  wire         clk,              // S_csi_rx_clk
    input  wire         rst_n,            // S_rst_n

    input  wire         in_valid,         // S_ISP_O_tvalid（一个 128bit 拍）
    input  wire [127:0] in_data,          // S_ISP_O_tdata
    input  wire         in_frame_start,   // S_ISP_O_tuser
    input  wire         in_line_end,      // S_ISP_O_tlast

    output reg          px_valid,         // 640x360 灰度输出有效
    output reg  [7:0]   px_data,
    output reg          px_frame_start,
    output reg          px_line_end,

    output reg  [31:0]  st_frame_px,      // 上一帧输出像素数（应 0x00038400）
    output reg  [15:0]  st_frame_ln,      // 上一帧输出行数（应 360）
    output reg  [31:0]  st_px_sum,        // 上一帧输出灰度累加和（校验用，应非 0）
    output reg  [31:0]  st_ovf,           // 异常计数（应 0）
    output reg          st_tgl            // 统计量已更新（供跨域原子快照）
);

    localparam [10:0] IMG_W  = 11'd1280;   // 输入行像素数
    localparam [10:0] LAST_X = 11'd1279;   // IMG_W-1
    localparam [9:0]  DW     = 10'd640;    // 降采样后行像素数

    //==================================================================
    // 拍缓存：512 深 x 128bit（工程里现成的 IP，不要自己缩深度）
    //==================================================================
    wire [127:0] fifo_dout;
    wire         fifo_empty;
    wire         fifo_full;
    wire [8:0]   fifo_cnt;
    reg          fifo_re;

    w128_d512_fifo u_beat_fifo (
        .rst        ( ~rst_n      ),      // 该 IP 的 rst 是高有效
        .clkw       ( clk         ),
        .clkr       ( clk         ),
        .we         ( in_valid    ),
        .di         ( in_data     ),
        .re         ( fifo_re     ),
        .dout       ( fifo_dout   ),
        .valid      (             ),
        .full_flag  ( fifo_full   ),
        .empty_flag ( fifo_empty  ),
        .afull      (             ),
        .aempty     (             ),
        .wrusedw    (             ),
        .rdusedw    ( fifo_cnt    )
    );

    wire fifo_ovf = in_valid & fifo_full;

    //==================================================================
    // 一级预取：把 FIFO 的下一拍搬到 d_pre
    //   pre_go   -> FIFO 看到 re
    //   下一拍   -> dout 有效，锁进 d_pre
    //==================================================================
    reg  [127:0] d_pre;
    reg          d_pre_v;
    reg          pre_busy;

    wire pre_go = ~d_pre_v & ~fifo_empty & ~pre_busy;

    //==================================================================
    // 发射控制
    //==================================================================
    reg  [1:0]   phase;
    reg  [127:0] d;
    reg  [15:0]  carry;
    reg  [2:0]   emit_cnt;
    reg  [2:0]   emit_num;
    reg          emit_act;

    wire at_last = emit_act & (emit_cnt == (emit_num - 1'b1));
    wire do_end  = at_last &  d_pre_v;      // 本相发完且下一拍已在手
    wire do_idle = at_last & ~d_pre_v;      // 本相发完但下一拍还没来 -> 停
    wire start   = ~emit_act & d_pre_v;     // 空转后数据到达 -> 启动
    wire take    = do_end | start;          // 从 d_pre 取走一拍

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_re  <= 1'b0;
            pre_busy <= 1'b0;
            d_pre    <= 128'd0;
            d_pre_v  <= 1'b0;
        end
        else if (in_frame_start) begin
            // ★ 帧首把预取状态一起收敛：in_frame_start 是异步于 FIFO 状态的，
            //   如果它落在"已发起预取但数据还没到"的窗口里，d_pre_v 会在
            //   帧首之后才被置 1，配上一个被清零的 phase，帧首几个像素错位。
            fifo_re  <= 1'b0;
            pre_busy <= 1'b0;
            d_pre_v  <= 1'b0;
        end
        else begin
            fifo_re  <= pre_go;                     // 1 拍脉冲
            pre_busy <= pre_go;
            if (pre_busy) begin                     // re 之后 1 拍 dout 有效
                d_pre   <= fifo_dout;
                d_pre_v <= 1'b1;
            end
            if (take)                               // 放最后：优先级最高
                d_pre_v <= 1'b0;
        end
    end

    //==================================================================
    // 相位 -> 像素位切片（与 video_out.v:177-194 完全一致）
    //   phase0: carry 无效      -> 发 5 个像素，carry = d[7:0]   (8bit)
    //   phase1: carry 低 8 位   -> 发 5 个像素，carry = d[15:0]  (16bit)
    //   phase2: carry 低 16 位  -> 发 6 个像素，carry = 0
    //   校验：5+5+6 = 16 像素；3 拍 x 128bit = 384bit = 16 x 24bit
    //==================================================================
    reg  [23:0] raw_px;
    always @(*) begin
        case ({phase, emit_cnt})
        // ---- phase 0（carry 无效）----
        5'b00000: raw_px = d[127:104];
        5'b00001: raw_px = d[103:80];
        5'b00010: raw_px = d[79:56];
        5'b00011: raw_px = d[55:32];
        5'b00100: raw_px = d[31:8];
        // ---- phase 1（carry 低 8 位有效）----
        5'b01000: raw_px = {carry[7:0],  d[127:112]};
        5'b01001: raw_px = d[111:88];
        5'b01010: raw_px = d[87:64];
        5'b01011: raw_px = d[63:40];
        5'b01100: raw_px = d[39:16];
        // ---- phase 2（carry 低 16 位有效）----
        5'b10000: raw_px = {carry[15:0], d[127:120]};
        5'b10001: raw_px = d[119:96];
        5'b10010: raw_px = d[95:72];
        5'b10011: raw_px = d[71:48];
        5'b10100: raw_px = d[47:24];
        5'b10101: raw_px = d[23:0];
        default:  raw_px = 24'd0;
        endcase
    end

    reg  [15:0] carry_nxt;
    always @(*) begin
        case (phase)
        2'd0:    carry_nxt = {8'd0, d[7:0]};
        2'd1:    carry_nxt = d[15:0];
        default: carry_nxt = 16'd0;
        endcase
    end

    wire [1:0] phase_nxt = (phase == 2'd2) ? 2'd0 : (phase + 1'b1);
    wire [2:0] num_nxt   = (phase_nxt == 2'd2) ? 3'd6 : 3'd5;

    //==================================================================
    // 灰度 + 2x2 盒式平均
    //==================================================================
    // (R + 2G + B) >> 2：最大 255+510+255 = 1020 -> 10bit
    wire [9:0] gsum = {2'b0, raw_px[23:16]}
                    + {1'b0, raw_px[15:8], 1'b0}
                    + {2'b0, raw_px[7:0]};
    wire [7:0] gray = gsum[9:2];

    reg  [10:0] x;          // 行内输入像素计数 0..1279
    reg         row_odd;    // 0 = 偶数行（写行 RAM），1 = 奇数行（输出）
    reg  [8:0]  hsum;       // 偶数列的灰度
    wire [9:0]  osum = {1'b0, hsum} + {1'b0, gray};   // 水平相邻两像素之和

    // 行 RAM：640 x 9bit，存偶数行的水平对和。
    //   这块缓存只在偶数行写、奇数行读，使用一个显式ERAM双口包装，
    //   把原先约256个分布式RAM LUT移到一个20K ERAM中；读口保持NOREG，
    //   不增加像素流水延迟。
    wire [9:0]  col = x[10:1];

    wire [8:0] lram_rd;
    wire       lram_we = emit_act & ~row_odd & x[0];
    vib_eram_dp #(
        .W_A(9), .AW_A(10), .D_A(640),
        .W_B(9), .AW_B(10), .D_B(640),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG")
    ) u_lram (
        .clk   (clk),
        .rst_n (rst_n),
        .dia   (osum[8:0]),
        .addra (col),
        .wea   (lram_we),
        .doa   (),
        .dib   (9'd0),
        .addrb (col),
        .web   (1'b0),
        .dob   (lram_rd)
    );

    wire outpix   = emit_act & row_odd & x[0];
    wire last_col = emit_act & (x == LAST_X);
    wire [7:0] opx = (osum + lram_rd) >> 2;            // 本拍要输出的降采样灰度

    // 异常来源（合并计数，见主状态里的一次加法）：
    //   ① 拍缓存溢出
    //   ② 一行拍数不对（在**拍域**校验）
    //   ③ 一行中途缓存排空
    //
    //   ★★ 为什么不能拿 tlast 和像素计数 x 比 ★★
    //     抽头因为 512 深拍缓存而**滞后于 ISP 的输入时序**：tlast 到达时，
    //     像素计数器往往还停在这一行的中间（缓存里还有几十上百拍没消化完）。
    //     所以 "tlast 与 x 对不上" 是必然的，这样校验是根本性错误——
    //     前两版都在这里误报，每行一次、约 42900/秒，而且数值改不动。
    //     正确做法是在拍域数：一行 = 1280 像素 x 3 字节 / 16 字节 = 240 拍。
    reg  [8:0] bpl;                       // 本行已累计的拍数
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)             bpl <= 9'd0;
        else if (in_line_end)   bpl <= 9'd0;
        else if (in_valid)      bpl <= bpl + 9'd1;
    end
    // 容差 ±10 拍，避开 tlast 与最后一个拍同拍时的 1 拍边界歧义
    wire bpl_bad = in_line_end & ((bpl < 9'd230) | (bpl > 9'd250));

    // ★ 断流条件每拍都成立，必须做边沿检测，否则 st_ovf 每拍 +1，
    //   从一个"事件计数"变成"持续时钟数"，数值失去意义。
    wire stall_now = fifo_empty & ~emit_act & (x != 11'd0);
    reg  stall_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) stall_d <= 1'b0;
        else        stall_d <= stall_now;
    end
    wire [1:0] ovf_inc = {1'b0, fifo_ovf}
                       + {1'b0, bpl_bad}
                       + {1'b0, (stall_now & ~stall_d)};

    //==================================================================
    // 主状态
    //==================================================================
    reg  [31:0] px_acc;
    reg  [15:0] ln_acc;
    reg  [31:0] px_sum;
    reg         fs_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase          <= 2'd0;
            d              <= 128'd0;
            carry          <= 16'd0;
            emit_cnt       <= 3'd0;
            emit_num       <= 3'd5;
            emit_act       <= 1'b0;
            x              <= 11'd0;
            row_odd        <= 1'b0;
            hsum           <= 9'd0;
            px_valid       <= 1'b0;
            px_data        <= 8'd0;
            px_frame_start <= 1'b0;
            px_line_end    <= 1'b0;
            st_frame_px    <= 32'd0;
            st_frame_ln    <= 16'd0;
            st_px_sum      <= 32'd0;
            st_ovf         <= 32'd0;
            st_tgl         <= 1'b0;
            px_acc         <= 32'd0;
            ln_acc         <= 16'd0;
            px_sum         <= 32'd0;
            fs_pending     <= 1'b0;
        end
        else begin
            px_valid       <= 1'b0;
            px_frame_start <= 1'b0;
            px_line_end    <= 1'b0;

            //----------------------------------------------------------
            // 异常统计（三个来源合并成一次加法，避免同一 reg 被多次赋值覆盖）
            //----------------------------------------------------------
            if (ovf_inc != 2'd0)
                st_ovf <= st_ovf + {30'd0, ovf_inc};

            //----------------------------------------------------------
            // 帧首
            //----------------------------------------------------------
            if (in_frame_start) begin
                st_frame_px <= px_acc;
                st_frame_ln <= ln_acc;
                st_px_sum   <= px_sum;
                st_tgl      <= ~st_tgl;    // 统计量已更新（供跨域原子快照）
                px_acc      <= 32'd0;
                ln_acc      <= 16'd0;
                px_sum      <= 32'd0;
                x           <= 11'd0;
                row_odd     <= 1'b0;
                phase       <= 2'd0;
                carry       <= 16'd0;
                emit_cnt    <= 3'd0;
                emit_num    <= 3'd5;
                fs_pending  <= 1'b1;
                // ★ 必须同时清发射状态：如果 in_frame_start 正好落在
                //   emit_act=1 的时候，下面会清 phase/carry/emit_cnt，
                //   但 emit_act 仍为 1、d 还是旧值 —— 下一拍就会用**旧 d**
                //   配 **phase=0** 去解像素，帧首几个像素错，而且 d_pre_v
                //   若仍为 1，start 不会触发，emit_act 一直不清，状态乱一段时间。
                //   正常时序帧首在消隐期，emit_act 已是 0，但这是逻辑隐患。
                emit_act    <= 1'b0;
                d           <= 128'd0;
                // d_pre_v / pre_busy / fifo_re 在下面的预取块里清，
                // 不能在这里再驱动一次（否则同一信号两个 always 驱动）
            end

            //----------------------------------------------------------
            // 发射
            //----------------------------------------------------------
            if (emit_act) begin
                // ★ px_valid 必须**只**在真正的降采样输出像素上拉高！
                //   曾经写成"每个发射的像素都拉高"，结果对外每帧发 921600 个像素
                //   （其中 3/4 是重复的旧 px_data），下游 B2b 便按 4 倍数据量
                //   去凑行，ITLN 变成 ~1376 行/帧而不是 360，FIFO 也一直被灌满。
                //   注意 VOFP/VOFL/VSUM 是在下面的输出分支里统计的，
                //   所以它们当时是"正确"的，掩盖了这个接口错误。

                // 水平：偶列暂存灰度，奇列求和
                if (x[0] == 1'b0)
                    hsum <= gray;

                // 偶行写行 RAM由u_lram的显式ERAM写口完成。

                // 奇数行、奇数列 -> 输出一个降采样像素
                if (row_odd & x[0]) begin
                    px_valid <= 1'b1;
                    px_data <= opx;
                    px_acc  <= px_acc + 32'd1;
                    px_sum  <= px_sum + {24'd0, opx};
                    if (fs_pending & (x == 11'd1)) begin
                        px_frame_start <= 1'b1;
                        fs_pending     <= 1'b0;
                    end
                    if (x == LAST_X) begin
                        px_line_end <= 1'b1;
                        ln_acc      <= ln_acc + 16'd1;
                    end
                end

                // 行内推进 / 行结束
                if (x == LAST_X) begin
                    x       <= 11'd0;
                    row_odd <= ~row_odd;
                end
                else begin
                    x <= x + 11'd1;
                end

                // 相位推进
                if (do_end) begin
                    phase    <= phase_nxt;
                    carry    <= carry_nxt;
                    emit_cnt <= 3'd0;
                    emit_num <= num_nxt;
                    d        <= d_pre;
                end
                else if (do_idle) begin
                    // ★ 必须同时推进相位/进位：
                    //   本相像素已发完但下一拍还没来。若只清 emit_act 而不推进
                    //   phase，重启时会用**旧 phase** 去解**新的 d_pre**
                    //   （d_pre 已是下一相的数据）-> 位切片错位。
                    //   平时靠"FIFO 空 -> phase 复位 0"兜住，行中间欠载才暴露，
                    //   而且 VOFP/VOFL 完全不变，极难查。
                    phase    <= phase_nxt;
                    carry    <= carry_nxt;
                    emit_num <= num_nxt;
                    emit_act <= 1'b0;
                    emit_cnt <= 3'd0;
                end
                else begin
                    emit_cnt <= emit_cnt + 1'b1;
                end
            end
            //----------------------------------------------------------
            // 空转：数据到达就启动；缓存排空则把相位/进位复位为 0
            //       （每行开始时本来就该是 0）
            //----------------------------------------------------------
            else if (start) begin
                emit_act <= 1'b1;
                emit_cnt <= 3'd0;
                emit_num <= (phase == 2'd2) ? 3'd6 : 3'd5;
                d        <= d_pre;
            end
            else if (fifo_empty) begin
                phase <= 2'd0;
                carry <= 16'd0;
            end
        end
    end

endmodule
