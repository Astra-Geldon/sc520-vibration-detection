//=============================================================================
//  vib_gz_multi.v  ——  48 块共享 Goertzel 引擎（含逐块高通）
//
//  架构：
//    vib_lk_grid 每 60 行（一个块行）给出 8 个横向块的 bx 快照
//    本引擎收到后逐块处理：先做一阶高通，再对 17 个频点递推
//
//  两个存储阵列（都在 ERAM 里，不占 slice）：
//    A. 频点状态  816 x 64 = {s1, s2}      地址 = 块号*17 + 频点
//    B. 块状态     48 x 64 = {hp, x_prev}  地址 = 块号
//       高通和 Goertzel 一样是每块独立的状态，不是每频点 —— 所以只要 48 份
//
//  时域预算（实测）：
//    每块行：8 块 x (1 次高通 + 17 次递推) = 8 x 18 = 144 次
//    每次约 4 拍 -> 576 拍；块行间隔 19,200 拍 -> 3%
//    一帧 6 个块行 = 3,456 拍 / 1,240,000 -> 0.28%
//
//  乘法器复用：整个引擎只有一个 c*s1（16x32，2 个 DSP）
//              高通里的 63*hp 用移位减（hp<<6 - hp），不占 DSP
//
//  ★ 不要登记进 .al，由顶层用 `include 拉入
//=============================================================================
`ifndef VIB_GZ_MULTI_V
`define VIB_GZ_MULTI_V

module vib_gz_multi #(
    parameter NFRM = 64,           // 窗口帧数
    parameter NBIN = 17,           // 2.0..10.0Hz，步进0.5Hz
    parameter NROW = 6,            // 块行数
    parameter NCOL = 8             // 每行块数
)(
    input  wire          clk,
    input  wire          rst_n,

    // ---- 来自 vib_lk_grid 的 8 块快照 ----
    input  wire [255:0]  i_bx8,        // 8 块 x 32 位，块 0 在最低位
    input  wire [4:0]    i_agc_exp,   // 8 块纹理能量对数最大值（块行 tick 时有效）
    input  wire [2:0]    i_row,        // 块行 0..5
    input  wire          i_tick,       // 1 拍脉冲：快照有效

    // ---- 帧 / 窗口 ----
    output reg  [7:0]    o_frm,        // 窗口内已累计帧数 0..NFRM
    output reg           o_frm_tgl,    // 窗口完成翻转
    output reg           o_busy,

    // ---- 状态阵列 B 口读出（给 vib_gz_peak 峰值扫描器用）----
    //   引擎自己只用 A 口（读写），B 口专门让扫描器只读，两边不打架。
    input  wire [9:0]    pk_b_addr,
    output wire [63:0]   pk_b_data,

    // ---- 诊断 ----
    output reg  [5:0]    o_dbg_blk,    // 当前处理的绝对块号 0..47
    output reg  [4:0]    o_dbg_bin,    // 当前频点
    output reg  [31:0]   o_dbg_rate,   // 上一帧递推次数（应 = 816）
    output reg  [5:0]    o_dbg_rowcnt,  // 本帧已处理块行数 0..5,
    output reg  [31:0]   o_tick_cnt,    // 自由运行的块行结束计数（应约 357/秒）,
    input  wire          i_pk_done,     // 峰值扫描完成：收到后清空状态阵列,
    output reg  [31:0] o_clr_cnt,    // 上次清空写了多少次（应 = 816）
    output wire [4:0]  o_dbg_agc_ref // 当前 AGC 参考对数
);

    localparam integer NB = NROW * NCOL;      // 48
    localparam integer NADDR = NROW * NCOL * NBIN;   // 48*17 = 816（状态阵列有效深度）
    localparam [7:0]   LAST_FRM = (NFRM - 1);
    localparam [13:0]  COEF_FRAC = 14'd14;

    //==================================================================
    //  系数表：c = 2cos(2*pi*f/fs)，Q1.14，f = 2+0.5*k，fs = 59.5
    //==================================================================
    function signed [15:0] coef_of;
        input [4:0] k;
        begin
            case (k)
            5'd0:  coef_of = 16'sd32040;   //  2.0 Hz
            5'd1:  coef_of = 16'sd31633;   //  2.5
            5'd2:  coef_of = 16'sd31137;   //  3.0
            5'd3:  coef_of = 16'sd30555;   //  3.5
            5'd4:  coef_of = 16'sd29888;   //  4.0
            5'd5:  coef_of = 16'sd29137;   //  4.5
            5'd6:  coef_of = 16'sd28306;   //  5.0
            5'd7:  coef_of = 16'sd27395;   //  5.5
            5'd8:  coef_of = 16'sd26408;   //  6.0
            5'd9:  coef_of = 16'sd25347;   //  6.5
            5'd10: coef_of = 16'sd24216;   //  7.0
            5'd11: coef_of = 16'sd23017;   //  7.5
            5'd12: coef_of = 16'sd21754;   //  8.0
            5'd13: coef_of = 16'sd20431;   //  8.5
            5'd14: coef_of = 16'sd19050;   //  9.0
            5'd15: coef_of = 16'sd17616;   //  9.5
            default: coef_of = 16'sd16134; // 10.0
            endcase
        end
    endfunction

    //==================================================================
    //  A. 频点状态 816 x 64 = {s1, s2}
    //==================================================================
    reg  [63:0] st_din;
    reg  [9:0]  st_addr;
    reg         st_we;
    wire [63:0] st_dout;

    vib_eram_dp #(
        .W_A(64), .AW_A(10), .D_A(1024),
        .W_B(64), .AW_B(10), .D_B(1024)
    ) u_state (
        .clk(clk), .rst_n(rst_n),
        .dia(st_din), .addra(st_addr), .wea(st_we), .doa(st_dout),
        .dib(64'd0), .addrb(pk_b_addr), .web(1'b0), .dob(pk_b_data)
    );

    //==================================================================
    //  B. 块状态 48 x 64 = {hp, x_prev}
    //==================================================================
    reg  [63:0] bs_din;
    reg  [5:0]  bs_addr;
    reg         bs_we;
    wire [63:0] bs_dout;

    vib_eram_dp #(
        .W_A(64), .AW_A(6), .D_A(64),
        .W_B(64), .AW_B(6), .D_B(64)
    ) u_bstat (
        .clk(clk), .rst_n(rst_n),
        .dia(bs_din), .addra(bs_addr), .wea(bs_we), .doa(bs_dout),
        .dib(64'd0), .addrb(6'd0), .web(1'b0), .dob()
    );

    //==================================================================
    //  快照缓存
    //==================================================================
    reg  [255:0] bx_snap;
    reg  [2:0]   row_snap;
    reg          snap_vld;

    //==================================================================
    //  引擎状态机
    //==================================================================
    localparam [3:0] S_IDLE  = 4'd0,
                     S_HP_RD = 4'd1,
                     S_HP_C  = 4'd2,
                     S_ST_RD = 4'd3,
                     S_ST_C  = 4'd4,
                     S_NEXT  = 4'd5,
                     S_END   = 4'd6,
                     S_CLR   = 4'd7,   // 清空 816 个 Goertzel 状态
                     S_CLR2  = 4'd8;   // 多待一拍，让最后一个地址真正写进去

    reg  [3:0]  gst;
    reg         clr_req;      // 需要清空状态阵列
    reg  [9:0]  clr_idx;      // 清空指针 0..815
    reg  [31:0] clr_cnt;      // 本次清空实际写了多少次
    reg  [2:0]  col;
    reg  [4:0]  bin;
    reg  [7:0]  fcnt;
    reg  [5:0]  rowcnt;
    reg  [31:0] rec_cnt;

    reg  [9:0]  blk_base;
    reg  signed [31:0] vcur;
    reg  signed [31:0] xcur;
    reg  signed [15:0] ccur;

    wire [5:0]  blk_abs = {row_snap, col};

    //==================================================================
    //  输入 AGC：参考上一完整帧6行的最大纹理指数，下限仍为18。
    //  2026-10-28：历史最大值只升不降，会在移动/纹理变化后永久抬高
    //  暗块增益。改为逐帧重新统计，参考只在第6行处理结束后提交，
    //  避免一帧内6行使用不同的参考。原有gain上限6和四档移位不变。
    //==================================================================
    reg [4:0] agc_frame_max; // 本帧6行最大值，每帧重置到18
    reg  [4:0] agc_ref;      // 上一完整帧的最大值，允许随当前场景下降
    assign o_dbg_agc_ref = agc_ref;
    wire [4:0] agc_diff = (agc_ref > i_agc_exp) ? (agc_ref - i_agc_exp) : 5'd0;
    wire [4:0] agc_gain = (agc_diff > 5'd6) ? 5'd6 : agc_diff;

    // ---- 逐块高通：hp' = (63*hp + x - x_prev) >>> 6 ----
    //   63*hp = (hp<<6) - hp，用移位减实现，不占 DSP
    wire signed [31:0] hp_q   = bs_dout[63:32];
    wire signed [31:0] xp_q   = bs_dout[31:0];
    wire signed [63:0] hp_qe  = {{32{hp_q[31]}}, hp_q};
    wire signed [63:0] xp_qe  = {{32{xp_q[31]}}, xp_q};
    wire signed [63:0] xcure  = {{32{xcur[31]}},  xcur};
    // ★ 2026-10-23：一阶高通系数 63 -> 52。
    //   hp[n] = (K*hp[n-1] + x[n] - x[n-1])/64，alpha = K/64
    //   K=63 -> alpha=0.9844 -> fc=0.149Hz（几乎不滤漂移，bin0 恒最大）
    //   K=52 -> alpha=0.8125 -> fc=1.99Hz（匹配 Python 的 highpass_cutoff_hz=2.0）
    //   52 = 64 - 8 - 4，用移位减法实现，不占 DSP。
    wire signed [63:0] hp63   = (hp_qe <<< 6) - (hp_qe <<< 3) - (hp_qe <<< 2);
    wire signed [63:0] hp_sum = hp63 + xcure - xp_qe;
    wire signed [31:0] hp_nxt = hp_sum >>> 6;
    // AGC 四档移位（6 / 4 / 2 / 0），用 4 选 1 的 mux，不是桶形移位器
    wire signed [31:0] v_agc = (agc_gain[2:1] == 2'd0) ? (hp_nxt >>> 6) :
                               (agc_gain[2:1] == 2'd1) ? (hp_nxt >>> 4) :
                               (agc_gain[2:1] == 2'd2) ? (hp_nxt >>> 2) :
                                                          (hp_nxt);

    // ---- Goertzel 递推（整个引擎唯一的一个乘法器）----
    wire signed [31:0] s1      = st_dout[63:32];
    wire signed [31:0] s2      = st_dout[31:0];
    wire signed [47:0] mul_cs1 = ccur * s1;
    wire signed [31:0] cs1_v   = mul_cs1 >>> COEF_FRAC;
    // ★ 饱和保护：去掉第二次 >>6 后输入大 64 倍，
    //   极端大幅度运动时 32 位状态可能回绕（符号翻转）。
    //   先用 33 位算，再夹到 ±2^30，保证不回绕。
    wire signed [32:0] s0_w  = {vcur[31], vcur} + {cs1_v[31], cs1_v}
                             - {s2[31], s2};
    wire signed [31:0] s0_v  = (s0_w > 33'sd1073741824)  ?  32'sd1073741823 :
                               (s0_w < -33'sd1073741824) ? -32'sd1073741824 :
                               (s0_w >>> 0);   // part-select 无符号，先移位再截断

    // ---- 行号 -> 基地址（行*136），用 case 避免乘法器 ----
    function [9:0] row_base;
        input [2:0] r;
        begin
            case (r)
            3'd0:    row_base = 10'd0;
            3'd1:    row_base = 10'd136;
            3'd2:    row_base = 10'd272;
            3'd3:    row_base = 10'd408;
            3'd4:    row_base = 10'd544;
            default: row_base = 10'd680;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            agc_ref <= 5'd18;
            agc_frame_max <= 5'd18;
            bx_snap   <= 256'd0;
            row_snap  <= 3'd0;
            snap_vld  <= 1'b0;
            gst       <= S_IDLE;
            col       <= 3'd0;
            bin       <= 5'd0;
            fcnt      <= 8'd0;
            rowcnt    <= 6'd0;
            rec_cnt   <= 32'd0;
            blk_base  <= 10'd0;
            vcur      <= 32'sd0;
            xcur      <= 32'sd0;
            ccur      <= 16'sd0;
            st_addr   <= 10'd0;
            st_din    <= 64'd0;
            st_we     <= 1'b0;
            bs_addr   <= 6'd0;
            bs_din    <= 64'd0;
            bs_we     <= 1'b0;
            o_frm     <= 8'd0;
            o_frm_tgl <= 1'b0;
            o_busy    <= 1'b0;
            o_dbg_blk <= 6'd0;
            o_dbg_bin <= 5'd0;
            o_dbg_rate<= 32'd0;
            o_dbg_rowcnt <= 6'd0;
            o_tick_cnt   <= 32'd0;
            clr_req      <= 1'b0;
            clr_idx      <= 10'd0;
            clr_cnt      <= 32'd0;
            o_clr_cnt    <= 32'd0;
        end else begin
            st_we <= 1'b0;
            bs_we <= 1'b0;

            // ---- 收快照 ----
            // 峰值扫描读完本窗口状态后清空状态阵列（Goertzel 每窗口必须重启）
            if (i_pk_done) clr_req <= 1'b1;

            if (i_tick) begin
                o_tick_cnt <= o_tick_cnt + 32'd1;
                bx_snap  <= i_bx8;
                // 本帧统计，包含最后一行；由S_END统一提交并重新开始。
                if (i_agc_exp > agc_frame_max) agc_frame_max <= i_agc_exp;
                row_snap <= i_row;
                snap_vld <= 1'b1;
            end

            case (gst)
            S_IDLE: begin
                o_busy <= 1'b0;
                if (clr_req) begin
                    clr_idx <= 10'd0;
                    st_addr <= 10'd0;
                    st_din  <= 64'd0;
                    gst     <= S_CLR;
                end else if (snap_vld) begin
                    snap_vld <= 1'b0;
                    o_busy   <= 1'b1;
                    col      <= 3'd0;
                    bin      <= 5'd0;
                    xcur     <= $signed(bx_snap[31:0]);
                    blk_base <= row_base(row_snap);
                    bs_addr  <= {row_snap, 3'd0};
                    gst      <= S_HP_RD;
            end
            end
            // --- 逐块高通 ---
            S_HP_RD: begin
                gst <= S_HP_C;
            end
            S_HP_C: begin
                bs_din  <= {hp_nxt, xcur};
                bs_we   <= 1'b1;
                // ★ 2026-10-23：原来这里还有一次 >>>6，等效除以 4096，
                //   输入过小时全部 bin 都会落在噪声量级。
                //   去掉第二次移位，增益 x64，mag² 落到可判区间。
                vcur    <= v_agc;
                //   之前我改成 vcur <= hp_nxt（增益 x64），导致 s1 累积到约 1e9，
                //   正好撞上 s0_v 的 ±2^30 饱和门限，递推被夹失真，
                //   表现为 B4=0（mag2 为负）、MBHZ 随机。
                //   旧版就是 >>>6，这个标度是对的。
                ccur    <= coef_of(5'd0);
                st_addr <= blk_base;
                gst     <= S_ST_RD;
            end
            // --- 17 个频点递推 ---
            // ★ 2026-10-23 修（ERAM 读延迟 = 1 拍）：
            //   "本拍给出的地址，下一拍数据才有效" —— vib_eram_probe.v 里已经实测过。
            //   原来在 S_ST_RD 这一拍才赋值 st_addr，而 RAM 在时钟沿采的是沿前的值，
            //   于是这一拍采到的仍是上一个 bin 的地址，S_ST_C 拿到的是 A(bin-1) 的状态：
            //   每个 bin 都读取自己的状态，不能把频点串成级联链。
            //   现在地址在 S_NEXT 里预取（bin 0 由 S_HP_C 预置），本状态只做等待拍，
                //   当前 2.0..10.0Hz 共 17 个频点，MBRT 应为 816。
            S_ST_RD: begin
                gst     <= S_ST_C;
            end
            S_ST_C: begin
                st_din    <= {s0_v, s1};
                st_we     <= 1'b1;
                rec_cnt   <= rec_cnt + 32'd1;
                o_dbg_blk <= blk_abs;
                o_dbg_bin <= bin;
                gst       <= S_NEXT;
            end
            S_NEXT: begin
                if (bin != (NBIN - 1)) begin
                    bin     <= bin + 5'd1;
                    ccur    <= coef_of(bin + 5'd1);
                    // ★ 预取下一个 bin 的地址：这一拍 st_addr 仍是当前 bin，所以 S_ST_C 期间
                    //   提交的写入落在当前 bin；行尾才切到 bin+1，正好在 S_ST_RD 呈现给 RAM。
                    st_addr <= blk_base + {5'd0, bin} + 10'd1;
                    gst     <= S_ST_RD;
                end else if (col != (NCOL - 1)) begin
                    col      <= col + 3'd1;
                    bin      <= 5'd0;
                    blk_base <= blk_base + NBIN;
                    xcur     <= $signed(bx_snap[32*(col + 3'd1) +: 32]);
                    bs_addr  <= {row_snap, (col + 3'd1)};
                    gst      <= S_HP_RD;
                end else begin
                    gst <= S_END;
                end
            end
            S_CLR: begin
                // 逐地址写 0；addr/din/we 都是寄存器，一起推进，不会错位
                st_addr <= clr_idx;
                clr_cnt <= clr_cnt + 32'd1;   // 每拍都计数
                st_din  <= 64'd0;
                st_we   <= 1'b1;
                if (clr_idx == (NADDR - 1)) begin
                    clr_req <= 1'b0;
                    // ★ 不能在这里清 st_we：这一拍 RAM 才刚采到 addr=815，
                    //   同一拍把 we 清 0 会让最后一个地址永远写不进去。
                    gst     <= S_CLR2;
                end else begin
                    clr_idx <= clr_idx + 10'd1;
                end
            end
            S_CLR2: begin
                // 本拍 addr 已经是 815、we 还是 1，写真正落盘；下一拍才撤 we
                st_we     <= 1'b0;
                o_clr_cnt <= clr_cnt;
                clr_cnt   <= 32'd0;
                gst       <= S_IDLE;
            end
            S_END: begin
                if (rowcnt == (NROW - 1)) begin
                    agc_ref       <= agc_frame_max;
                    agc_frame_max <= 5'd18;
                    rowcnt       <= 6'd0;
                    o_dbg_rate   <= rec_cnt;      // 不再额外 +136
                    rec_cnt      <= 32'd0;
                    o_dbg_rowcnt <= 6'd0;
                    if (fcnt == LAST_FRM) begin
                        fcnt      <= 8'd0;
                        o_frm     <= 8'd0;
                        o_frm_tgl <= ~o_frm_tgl;
                    end else begin
                        fcnt  <= fcnt + 8'd1;
                        o_frm <= fcnt + 8'd1;
                    end
                end else begin
                    rowcnt       <= rowcnt + 6'd1;
                    o_dbg_rowcnt <= rowcnt + 6'd1;
                end
                gst <= S_IDLE;
            end
            default: gst <= S_IDLE;
            endcase
        end
    end

endmodule

`endif // VIB_GZ_MULTI_V
