//=============================================================================
//  vib_goertzel.v  ——  振动频率识别（17 频点 Goertzel，128 帧窗口）
//
//  输入：固定纹理块的 bx[n] = Σ(ix·It)，每帧一个采样点（同时钟域，无 CDC）
//
//  处理链：
//    1. 一阶高通   hp = (63*hp + x - x_prev) >>> 6
//    2. 降位宽     v  = hp >>> 6
//    3. 每频点     s0 = v + c*s1 - s2 ;  s2 = s1 ;  s1 = s0     c = 2cos(2πf/fs)，Q1.14
//    4. 窗口末尾   mag² = s1² - c*s1*s2 + s2²  → 17 个里取最大
//
//  参数：fs ≈ 59.5 Hz，NFRM = 128 帧 → Δf = 0.465 Hz
//        频点 2.0 .. 10.0 Hz，步长 0.5 Hz，共 17 个
//
//  ★★ signed 三条铁律（每条都真的踩过）★★
//    (1) IEEE 1364-2001：**矢量 part-select（a[i:j]）是无符号的**，即使 a
//        声明成 signed。绝不能写 `signed_vec[47:0] >>> 14` —— 那会变成
//        逻辑右移，负数符号位被当数据位。正确做法：把中间量声明成**恰好
//        需要的那一位宽**，然后全名引用。
//        （第一版就栽在这里：GZS1≈-10 但 GZMG≈0xFC000000）
//    (2) `a * b` 结果宽度 = 操作数最大宽度，但**左侧更宽的上下文会把操作数
//        一起拓宽**，所以 `wire [63:0] p = a*b;`（a,b 32 位）是完整 64 位
//        乘积，不用手工扩展；手工扩成 64×64 反而吃掉 DSP（实测 DSP 从 15
//        涨到 35）。
//    (3) `a >>> k` 的左操作数**自决定**、不向上下文传播 → 后面跟 >>> 的
//        乘法必须先手工拓宽操作数。
//
//  ★ 状态数组故意不做异步复位：对 RAM 加复位循环会让综合放弃 RAM、拆成
//    1000+ 触发器。改用独立 CLR 状态机逐条写 0。上电后第一个窗口可能是
//    垃圾（约 2 秒后正常）。
//=============================================================================
`ifndef VIB_GOERTZEL_V
`define VIB_GOERTZEL_V

module vib_goertzel #(
    parameter NFRM = 128,
    parameter NBIN = 17
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               tick,
    input  wire signed [31:0] bx,
    output reg  [4:0]         peak_bin,
    output reg  [7:0]         peak_hz10,
    output reg  [63:0]        peak_mag,
    output reg                valid,
    // ---- 音调判决（2026-10-20 新增）----
    //   没有振动时 17 个 bin 的能量相近，峰值只是噪声的偶然最大；
    //   有真实振动时某个 bin 会显著高于其余。
    //   tonal = (峰值 > MIN_MAG) && (峰值*4 > 全部 bin 之和)
    //   即"峰值占全部能量的 25% 以上"，才认为存在单一主导频率。
    output reg                tonal,
    output wire [43:0]        total_mag,
    output wire [31:0]        psum_hi,   // psum 的高 32 位（调阈值用）
    output reg  [7:0]         frm_cnt,
    output reg                frm_tgl,
    // ---- 诊断：上一个完整窗口内的绝对峰值 ----
    //   5 Hz 信号用 1 秒一次的串口采瞬时值等于乱猜（混叠成随机数），
    //   所以保持 |hp|、|v|、|s1(bin6)| 在整个窗口内的最大值。
    output reg  [31:0]        dbg_hp,
    output reg  [31:0]        dbg_in,
    output reg  [31:0]        dbg_s1
);

    localparam [13:0] COEF_FRAC = 14'd14;
    localparam [7:0]  LAST_FRM  = NFRM - 1;

    // 音调判决的两个门限
    //   MIN_MAG：峰值绝对下限。
    //     实机数据（2026-10-20，手机屏播 8 Hz 视频）：
    //       静止噪声     GZMG = 45,254
    //       8 Hz 屏振动  GZMG = 8,289 ~ 33,953   ← 比手抖那次小得多
    //       手抖 / 大幅  GZMG = 530,012
    //     取 4,000（低于最小真实振动值的一半），主要靠比例判据区分。
    //   PEAK_RATIO：峰值 / 平均 bin，用 pmax*2 > psum
    //     静止时 17 个 bin 相近 → 峰值 ≈ 平均，比值 ≈ 1，判 0
    //     真实单频时峰值突出   → 比值 >> 2，判 1
    //     原来用 pmax*4（峰值占 25%），实测 8 Hz 用例过不了 ——
    //     泄漏把能量分散到了相邻 bin，25% 太严。
    localparam signed [63:0] MIN_MAG = 64'sd4000;

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

    // ---- 状态（期望综合成 RAM；无异步复位）------------------------------
    reg signed [31:0] s1 [0:NBIN-1];
    reg signed [31:0] s2 [0:NBIN-1];

    reg signed [31:0] hp;
    reg signed [31:0] xprev;

    localparam [2:0] G_IDLE = 3'd0, G_READ = 3'd1, G_CALC = 3'd2,
                     P_READ = 3'd3, P_CALC = 3'd4, P_DONE = 3'd5,
                     CLR    = 3'd6;

    reg [2:0]  gst;
    reg [4:0]  bidx, clr_i;
    reg [7:0]  fcnt;
    reg signed [31:0] rd1, rd2;
    reg signed [15:0] ccur;
    reg signed [31:0] vcur;
    reg signed [63:0] pmax;
    reg [4:0]  pidx;

    // 窗口内 17 个 bin 的能量累计（负数按 0 处理），用于音调判决
    // 2026-10-20：psum 从 72 位降到 44 位。
    //   累计的是 mag2>>24，mag2 最大约 2^48 → 17 个之和 < 2^44 ✓
    //   只用于"峰值 / 全部能量"的比值判决，精度完全够。
    reg  [43:0] psum;
    assign total_mag = psum;
    assign psum_hi   = psum[43:12];

    reg [31:0] pk_sh;                   // 只保留 bin6 的 |s1| 峰值

    // ---- 组合：位宽全部"恰好够"，然后全名引用（绝不 part-select signed 量）
    //   实测量级：s1,s2 <= 1.5e5 = 2^17.2；c <= 2^14
    //     mul_cs1 = c*s1     <= 2^31.2 → 48 位
    //     cs1     = mul_cs1>>14 <= 2^17.2 → 32 位
    //     p_cs12  = c*s1*s2  <= 2^48.4 → 64 位
    //     sq1,sq2 = s1²      <= 2^34.4 → 64 位
    //  ★ 2026-10-20 修正：原来把 c 手工扩到 48 位、s2 扩到 64 位，
    //    导致 c(48)*s1(48) 吃 9 个 DSP、mul_cs1(48)*s2(64) 吃 12 个。
    //    c 本身就是 16 位有符号（Q1.14，实测范围 16134..32040），
    //    s1/s2 是 32 位 —— 按真实宽度声明即可，乘法器 18+ → 10 个。
    wire signed [15:0] c_ext   = ccur;
    wire signed [31:0] rd1_ext = rd1;
    wire signed [31:0] rd2_ext = rd2;

    wire signed [47:0] mul_cs1 = c_ext * rd1_ext;     // 16 x 32 → 2 个 DSP
    wire signed [31:0] cs1     = mul_cs1 >>> COEF_FRAC;
    wire signed [31:0] s0      = vcur + cs1 - rd2;

    wire signed [63:0] sq1     = rd1 * rd1;           // 32 x 32 → 4 个 DSP
    wire signed [63:0] sq2     = rd2 * rd2;

    //  原来 mul_cs1(48) * rd2_ext(64) = 12 个 DSP。
    //  改成先把 c*s1 归一到 cs1(32) 再乘 s2(32) = 4 个 DSP。
    //  差别只是 (c*s1*s2)>>14 与 ((c*s1)>>14)*s2 的 1 LSB 舍入。
    wire signed [63:0] p_cs12  = cs1 * rd2_ext;
    wire signed [63:0] cs12    = p_cs12 >>> COEF_FRAC;
    wire signed [63:0] mag2    = sq1 - cs12 + sq2;

    //  ★ signed part-select 是无符号的（本项目第二条铁律），
    //    所以这里先把 mag2/pmax 右移 24 位再存成恰好 40 位的信号，
    //    而不是写 mag2[63:24]。
    wire signed [39:0] mag2_sh = mag2 >>> 24;
    wire signed [39:0] pmax_sh = pmax >>> 24;
    // 峰值 * 3，用于"峰值 > 平均 bin 的 2.8 倍"判决
    wire signed [41:0] pmax_sh_3 = {1'b0, pmax_sh, 1'b0} + {2'b00, pmax_sh};

    wire signed [63:0] hp_63   = $signed(hp) * 32'sd63;
    wire signed [63:0] hp_d    = $signed(bx) - $signed(xprev);
    wire signed [31:0] hp_next = (hp_63 + hp_d) >>> 6;

    wire [31:0] sh_abs = s0[31]   ? (~s0   + 32'd1) : s0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hp <= 32'sd0; xprev <= 32'sd0;
            gst <= CLR; bidx <= 5'd0; clr_i <= 5'd0; fcnt <= 8'd0;
            rd1 <= 32'sd0; rd2 <= 32'sd0; ccur <= 16'sd0; vcur <= 32'sd0;
            pmax <= 64'sd0; pidx <= 5'd0;
            psum <= 44'd0; tonal <= 1'b0;
            peak_bin <= 5'd0; peak_hz10 <= 8'd0; peak_mag <= 64'd0;
            valid <= 1'b0; frm_cnt <= 8'd0; frm_tgl <= 1'b0;
            pk_sh <= 32'd0;
            dbg_hp <= 32'd0; dbg_in <= 32'd0; dbg_s1 <= 32'd0;
        end
        else begin
            valid <= 1'b0;

            case (gst)
            //--------------------------------------------------------------
            CLR: begin
                s1[clr_i] <= 32'sd0;
                s2[clr_i] <= 32'sd0;
                if (clr_i == NBIN - 1) begin
                    clr_i <= 5'd0;
                    gst   <= G_IDLE;
                end
                else begin
                    clr_i <= clr_i + 5'd1;
                end
            end
            //--------------------------------------------------------------
            G_IDLE: begin
                if (tick) begin
                    // 2026-10-20：为过综合减重，去掉 pk_hp / pk_in 的峰值保持
                    // （共 64 个触发器 + 2 组比较器）。dbg_hp / dbg_in 恒输出 0，
                    // 只保留 dbg_s1 —— 它是判断 Goertzel 状态是否正常最直接的一个。
                    hp    <= hp_next;
                    xprev <= bx;
                    vcur  <= hp_next >>> 6;
                    bidx  <= 5'd0;
                    gst   <= G_READ;
                end
            end
            //--------------------------------------------------------------
            G_READ: begin
                rd1  <= s1[bidx];
                rd2  <= s2[bidx];
                ccur <= coef_of(bidx);
                gst  <= G_CALC;
            end
            //--------------------------------------------------------------
            G_CALC: begin
                if (bidx == 5'd6 && sh_abs > pk_sh) pk_sh <= sh_abs;
                s1[bidx] <= s0;
                s2[bidx] <= rd1;
                if (bidx == NBIN - 1) begin
                    bidx <= 5'd0;
                    if (fcnt == LAST_FRM) begin
                        frm_cnt <= fcnt + 8'd1;
                        frm_tgl <= ~frm_tgl;
                        gst     <= P_READ;
                    end
                    else begin
                        fcnt    <= fcnt + 8'd1;
                        frm_cnt <= fcnt + 8'd1;
                        frm_tgl <= ~frm_tgl;
                        gst     <= G_IDLE;
                    end
                end
                else begin
                    bidx <= bidx + 5'd1;
                    gst  <= G_READ;
                end
            end
            //--------------------------------------------------------------
            P_READ: begin
                rd1  <= s1[bidx];
                rd2  <= s2[bidx];
                ccur <= coef_of(bidx);
                gst  <= P_CALC;
            end
            P_CALC: begin
                if ((mag2 >= 64'sd0) && (mag2 > pmax)) begin
                    pmax <= mag2;
                    pidx <= bidx;
                end
                // 累计全部 bin 的能量（负值按 0 计，避免相消）
                if (mag2 >= 64'sd0) begin
                    psum <= psum + {4'd0, mag2_sh};
                end
                if (bidx == NBIN - 1) begin
                    bidx <= 5'd0;
                    gst  <= P_DONE;
                end
                else begin
                    bidx <= bidx + 5'd1;
                    gst  <= P_READ;
                end
            end
            P_DONE: begin
                peak_bin  <= pidx;
                peak_hz10 <= 8'd20 + {2'b00, pidx, 2'b00} + {4'b0000, pidx};
                peak_mag  <= (pmax >= 64'sd0) ? pmax : 64'sd0;
                valid     <= 1'b1;
                // 音调判决：峰值够大，且是平均 bin 的 2 倍以上
                //   pmax_sh = pmax>>24，psum = Σ(mag2>>24)，两者同一标度
                //   {1'b0, pmax_sh, 1'b0} = pmax_sh * 2
                // psum 此时已含全部 17 个 bin（含峰值本身）
                tonal     <= (pmax > MIN_MAG) &&
                             (pmax_sh_3 > psum);
                dbg_hp    <= 32'd0;   // 已移除峰值保持，恒 0
                dbg_in    <= 32'd0;
                dbg_s1    <= pk_sh;
                pk_sh     <= 32'd0;
                pmax      <= 64'sd0;
                psum      <= 44'd0;
                pidx      <= 5'd0;
                fcnt      <= 8'd0;
                frm_cnt   <= 8'd0;
                frm_tgl   <= ~frm_tgl;
                clr_i     <= 5'd0;
                gst       <= CLR;
            end
            default: gst <= CLR;
            endcase
        end
    end

endmodule

`endif
