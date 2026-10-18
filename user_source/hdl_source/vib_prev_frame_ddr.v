//=====================================================================
//  vib_prev_frame_ddr.v  ——  用 DDR 存"上一帧灰度"，算帧差 It
//
//  它解决什么问题：
//    帧差 It(x,y) = I_t(x,y) - I_{t-1}(x,y) 需要**上一帧整幅灰度**。
//    640x360 灰度 = 230400 字节 = 1.84 Mbit，远超 ERAM 空闲量（约 1360 Kbit），
//    所以必须放 DDR。放 DDR 又要解决两件事：
//      ① DDR 只能按行突发访问，而像素是流式的 → 需要行缓冲
//      ② DDR 接口在 S_ddr_clk 域，像素在 S_csi_rx_clk 域
//
//  架构：
//      csi 域：把抽头来的 640x360 灰度按 16 像素打包成 1 个 128bit 字，
//              推入 w128_d512_fifo（工程里现成的**双时钟 FIFO**）。
//      ddr 域：每凑够一行 40 个字就
//              (a) 从 FIFO 取 40 个字到 cur_mem
//              (b) 从 DDR 读回上一帧同一行 40 个字到 prev_mem
//              (c) 逐字算 16 个 |It| 累加，并把当前行写回 DDR 同一地址
//
//  ★ 为什么改回用 FIFO 而不是自己搭双时钟 RAM：
//      上一版我用 reg 数组在 csi 域写、在 ddr 域组合读，指望工具推断双时钟
//      RAM。结果整条链路一个动作都没有（ITPX/ITLN 恒 0）。
//      w128_d512_fifo 是工程里 video_in/video_out 已经在用的 IP，时序明确
//      （re 之后 1 拍 dout 有效），所以这里改用现成 IP，不赌工具推断。
//
//  ★ 为什么只做单向跨时钟域：
//      "上一帧"来自 DDR、"当前帧"来自 FIFO，两边都在 ddr 域，
//      所以 It 在 ddr 域算完即可，不需要反向再跨一次。
//
//  ★ 为什么就地读写只要一份 DDR 区域：
//      读第 y 行 -> 算 It -> 写第 y 行，地址相同，中间没有别人碰它。
//
//  自检（走串口日志）：
//      ITPX 每帧参与 It 的像素数，必须 = 230400 = 0x00038400
//      ITLN 每帧处理行数，        必须 = 360    = 0x00000168
//      ITSM 每帧 Σ|It|：静止场景接近 0；画面一动立刻涨（最直观的"通了"证据）
//      ITER 异常计数，必须 = 0
//      ITNW "凑够一行"的次数，应约 360/秒 —— 用来定位卡在哪一级：
//               ITNW 一直 0        -> csi 侧/FIFO 没数据进来
//               ITNW 在涨但 ITLN=0 -> 卡在 ddr 域，看 ITST
//      ITST 状态机当前状态：0=等行 1=取FIFO 2=读DDR 3=写回
//=====================================================================
module vib_prev_frame_ddr #(
    parameter [24:0] BASE_ADDR = 25'd24000000,   // 48 MB 处，与自检同一区域
    parameter [9:0]  LINES     = 10'd360         // 输出行数
)(
    // ---------------- csi 域（接 vib_video_tap 的输出）----------------
    input  wire         csi_clk,          // S_csi_rx_clk
    input  wire         csi_rst_n,        // S_rst_n
    input  wire         px_valid,
    input  wire [7:0]   px_data,
    input  wire         px_frame_start,
    input  wire         px_line_end,

    // ---------------- ddr 域 ----------------
    input  wire         clk,              // S_ddr_clk
    input  wire         rst_n,            // S_rst_n

    output wire         O_wr_en,
    output wire         O_rd_en,
    output wire [24:0]  O_addr,
    output wire [127:0] O_wr_data,
    input  wire         I_ready,          // 来自 vib_ddr_arb.O_vib_ready
    input  wire         I_rd_valid,       // 来自 vib_ddr_arb.O_vib_rd_valid
    input  wire [127:0] I_rd_data,
    output wire         O_want,           // 接 vib_ddr_arb.I_vib_want

    // ---------------- 统计（ddr 域，给串口日志）----------------
    output reg  [31:0]  st_it_px,         // 每帧 It 像素数，应 = 0x00038400
    output reg  [31:0]  st_it_sum,        // 每帧 Σ|It|
    output reg  signed [31:0] st_it_sgn,  // 每帧有符号 ΣIt（区分亮度变化/真实运动）
    output reg  [31:0]  st_lines,         // 每帧行数，应 = 360
    output reg  [31:0]  st_err,           // 异常计数，应 = 0
    output reg  [31:0]  st_line_rdy,      // "凑够一行"次数（定位用）
    output reg  [31:0]  st_state,         // 状态机状态（定位用）
    output reg          st_tgl,           // 统计量已更新（供跨域原子快照）

    // ---------------- 给 B2c 梯度级的流式输出（同在 ddr 域） ----------------
    //   每写回一拍（每行 40 拍）同时送出：
    //     lk_cur = 当前帧 g 的 16 个像素
    //     lk_dif = 帧差 It 的 16 个有符号字节（二进制补码）
    //   像素 j 都位于 [127-8j -: 8]，与内部 cur_word_r 的打包顺序一致
    output wire         lk_word_valid,
    output wire [127:0] lk_cur_w,
    output wire [127:0] lk_prev_w
);

    localparam [5:0] WL = 6'd40;          // 一行 40 个 128bit 字（640 像素）

    //==================================================================
    // 一、csi 域：16 像素打包成 1 个 128bit 字（第一个像素在高位）
    //==================================================================
    reg  [127:0] c_pack;
    reg  [3:0]   c_sub;
    reg          c_sof_tgl;

    wire [127:0] c_word = {c_pack[119:0], px_data};
    wire         c_push = px_valid & (c_sub == 4'd15);

    always @(posedge csi_clk or negedge csi_rst_n) begin
        if (!csi_rst_n) begin
            c_pack    <= 128'd0;
            c_sub     <= 4'd0;
            c_sof_tgl <= 1'b0;
        end
        else begin
            if (px_valid) begin
                c_pack <= c_word;
                c_sub  <= c_sub + 4'd1;
            end
            if (px_line_end)
                c_sub <= 4'd0;            // 640 像素 = 40 字，本来天然对齐，保险起见复位
            if (px_frame_start)
                c_sof_tgl <= ~c_sof_tgl;
        end
    end

    //==================================================================
    // 二、跨时钟域：用工程现成的双时钟 FIFO（512 深 x 128bit）
    //     re 之后 1 拍 dout 有效（和 video_in.v 的用法一致）
    //==================================================================
    wire [127:0] f_dout;
    wire         f_empty;
    wire         f_full;
    wire [8:0]   f_cnt;
    wire         f_re;

    w128_d512_fifo u_line_fifo (
        .rst        ( ~rst_n    ),
        .clkw       ( csi_clk   ),
        .clkr       ( clk       ),
        .we         ( c_push    ),
        .di         ( c_word    ),
        .re         ( f_re      ),
        .dout       ( f_dout    ),
        .valid      (           ),
        .full_flag  ( f_full    ),
        .empty_flag ( f_empty   ),
        .afull      (           ),
        .aempty     (           ),
        .wrusedw    (           ),
        .rdusedw    ( f_cnt     )
    );

    //==================================================================
    // 三、ddr 域：frame start 同步（统计用）
    //==================================================================
    reg  [1:0] sof_sync;
    reg        sof_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sof_sync <= 2'b00;
            sof_d    <= 1'b0;
        end
        else begin
            sof_sync <= {sof_sync[0], c_sof_tgl};
            sof_d    <= sof_sync[1];
        end
    end
    wire sof_new = sof_sync[1] ^ sof_d;

    //==================================================================
    // 四、ddr 域：行状态机
    //==================================================================
    reg  [127:0] cur_mem  [0:39];
    reg  [127:0] prev_mem [0:39];
    reg  [5:0]   rd_i;                    // 已发出的 FIFO 读次数 0..40
    reg  [5:0]   cw;                      // FIFO 取字计数 0..39
    reg  [5:0]   bcnt;                    // DDR 拍计数 0..39
    reg  [5:0]   rcnt;                    // 读回计数 0..39
    reg          rd_go_d;                 // FIFO 读延迟一拍
    reg  [9:0]   line_idx;
    reg  [2:0]   st;
    reg          first_frame;
    reg  [24:0]  line_addr;
    reg  [31:0]  it_px_acc, it_sum_acc, ln_acc;
    reg  signed [31:0] it_sgn_acc;
    reg  [31:0]  ln_rdy_cnt;

    localparam [2:0] ST_IDLE  = 3'd0,     // 等凑够一行
                     ST_FIFO  = 3'd1,     // 从 FIFO 取 40 字
                     ST_DDRRD = 3'd2,     // 从 DDR 读上一帧 40 字
                     ST_WR    = 3'd3,     // 写回 + 算 It
                     ST_DRAIN = 3'd4;     // 等最后几个读回，防止跨行污染

    // ST_DRAIN 最长等多久（ddr 时钟）。行周期约 2300 拍，正常几十拍就收齐；
    // 设这个上限是为了"万一真丢了一个读回"不死等，报 ITER 后继续跑。
    localparam [15:0] DRAIN_MAX = 16'd8191;
    reg  [15:0] drain_cnt;

    wire [24:0] beat_addr = line_addr + {bcnt, 3'b0};
    wire        use_idx0  = sof_new;

    // FIFO 读：rd_i < 40 时才继续发
    assign f_re   = (st == ST_FIFO) && (rd_i < WL) && ~f_empty;
    assign O_rd_en = (st == ST_DDRRD) & I_ready;
    assign O_wr_en = (st == ST_WR)    & I_ready;
    assign O_addr  = beat_addr;
    assign O_want  = (st != ST_IDLE);

    //------------------------------------------------------------------
    // 出/入两个字：数组读出统一放在 always @(*) 里
    //   （不在连续赋值里直接索引数组，避免工具推断方式不确定）
    //------------------------------------------------------------------
    reg  [127:0] cur_word_r, prev_word_r;
    always @(*) begin
        cur_word_r  = cur_mem[bcnt];
        prev_word_r = prev_mem[bcnt];
    end
    assign O_wr_data = cur_word_r;

    //------------------------------------------------------------------
    // ★ 送给 B2c 的是**上一帧的灰度本身**，不是 8bit 的差值
    //
    //   原来这里算 lk_dif = cur - prev 并按 8 位截断，这是错的：
    //   cur,prev 都是 0..255，差值范围 -255..255，8 位补码只能表示
    //   -128..127。于是 cur=255,prev=0 的 255 会变成 8'hFF（按有符号读 = -1），
    //   cur=0,prev=255 的 -255 变成 8'h01（= +1）—— 符号和大小全错，
    //   LK 的 bx/by = Σ(梯度·It) 直接不可信。
    //   现在改为送 prev（8bit 精确无损），由 B2c 内部用 9bit 算
    //   dit = cur - prev，精度完整且接口宽度不变。
    //------------------------------------------------------------------
    assign lk_word_valid = O_wr_en;      // 每写回一拍（每行 40 拍）
    assign lk_cur_w      = cur_word_r;
    assign lk_prev_w     = prev_word_r;  // 上一帧同一行的 16 个像素

    //------------------------------------------------------------------
    // It：一拍算完一个字的 16 个字节（打包时第一个像素在高位 [127:120]）
    //------------------------------------------------------------------
    wire [31:0]        abs_sum [0:15];
    wire signed [31:0] sgn_sum [0:15];
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_abs
            // dj = cur - prev，9bit 二进制补码，天然就是有符号差值（范围 -255..255）
            wire [8:0] dj = {1'b0, cur_word_r[127 - 8*gi -: 8]}
                          - {1'b0, prev_word_r[127 - 8*gi -: 8]};
            assign abs_sum[gi] = dj[8] ? {23'd0, (~dj + 9'd1)} : {23'd0, dj};
            assign sgn_sum[gi] = {{23{dj[8]}}, dj};      // 符号扩展成 32bit
        end
    endgenerate

    wire [31:0] sum16 = abs_sum[0]  + abs_sum[1]  + abs_sum[2]  + abs_sum[3]
                      + abs_sum[4]  + abs_sum[5]  + abs_sum[6]  + abs_sum[7]
                      + abs_sum[8]  + abs_sum[9]  + abs_sum[10] + abs_sum[11]
                      + abs_sum[12] + abs_sum[13] + abs_sum[14] + abs_sum[15];

    // 有符号的 ΣIt 是**区分"整体亮度变化"和"真实运动"的关键诊断量**：
    //   自动曝光/增益变化 -> 整体同号变化，ΣIt 会很大且同号
    //   随机噪声/真实运动 -> 正负抵消，ΣIt 接近 0
    wire signed [31:0] sgn16 = sgn_sum[0]  + sgn_sum[1]  + sgn_sum[2]  + sgn_sum[3]
                             + sgn_sum[4]  + sgn_sum[5]  + sgn_sum[6]  + sgn_sum[7]
                             + sgn_sum[8]  + sgn_sum[9]  + sgn_sum[10] + sgn_sum[11]
                             + sgn_sum[12] + sgn_sum[13] + sgn_sum[14] + sgn_sum[15];
    reg f_full_d;
    assign err_drain_to = (st == ST_DRAIN) && (drain_cnt >= DRAIN_MAX);
    assign err_full_evt = f_full & ~f_full_d;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) f_full_d <= 1'b0;
        else        f_full_d <= f_full;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_i        <= 6'd0;
            cw          <= 6'd0;
            bcnt        <= 6'd0;
            rcnt        <= 6'd0;
            rd_go_d     <= 1'b0;
            drain_cnt   <= 16'd0;
            line_idx    <= 10'd0;
            st          <= ST_IDLE;
            first_frame <= 1'b1;
            line_addr   <= BASE_ADDR;
            it_px_acc   <= 32'd0;
            it_sum_acc  <= 32'd0;
            it_sgn_acc  <= 32'sd0;
            ln_acc      <= 32'd0;
            ln_rdy_cnt  <= 32'd0;
            st_it_px    <= 32'd0;
            st_it_sum   <= 32'd0;
            st_it_sgn   <= 32'sd0;
            st_lines    <= 32'd0;
            st_err      <= 32'd0;
            st_line_rdy <= 32'd0;
            st_state    <= 32'd0;
            st_tgl      <= 1'b0;
        end
        else begin
            st_state <= {29'd0, st};

            //----------------------------------------------------------
            // 帧首：锁存上一帧统计
            //----------------------------------------------------------
            if (sof_new) begin
                st_it_px    <= it_px_acc;
                st_lines    <= ln_acc;
                st_line_rdy <= ln_rdy_cnt;    // 每帧"凑够一行"次数，正常约 360
                st_tgl      <= ~st_tgl;       // 统计量已更新（供跨域原子快照）
                if (first_frame) begin
                    first_frame <= 1'b0;      // 第一帧没有有效"上一帧"，Σ 不计
                    st_it_sum  <= 32'd0;
                    st_it_sgn  <= 32'sd0;
                end
                else begin
                    st_it_sum <= it_sum_acc;
                    st_it_sgn <= it_sgn_acc;
                end
                it_px_acc  <= 32'd0;
                it_sum_acc <= 32'd0;
                it_sgn_acc <= 32'sd0;
                ln_acc     <= 32'd0;
                ln_rdy_cnt <= 32'd0;
                line_idx   <= 10'd0;
            end

            //----------------------------------------------------------
            // FIFO 读出流水
            //----------------------------------------------------------
            rd_go_d <= f_re;
            if (f_re) begin
                // 每读一个字，计数 +1（下一个字）
            end
            if (rd_go_d) begin
                cur_mem[cw] <= f_dout;
                cw          <= cw + 6'd1;
            end

            //----------------------------------------------------------
            // ★★★ 读回数据收集：必须在 case 外面，任何状态都要收 ★★★
            //
            //   这个 bug 藏了很久：早先它被写在 case 的 ST_WR 分支里面，
            //   于是只有 ST_WR 状态才收读回数据。但读回**大部分是在 ST_DDRRD
            //   期间就回来的**（DDR 读延迟 >= 40 拍，而按仲裁器 25% 占空比发
            //   40 个读命令要跑 ~160 拍），这些数据全落在 ST_WR 之外被丢掉。
            //
            //   后果：每行 40 个读回只收到约 20 个，prev_mem 另一半保持复位值 0，
            //         于是 It = cur - 0 = cur，处处同号且很大。
            //   板上实测的指纹（三个都对上，可据此确认已修复）：
            //     ΣIt / Σcur = 11.3M / 24.2M = 0.467  -> prev_mem 约 47% 是 0
            //     ITER 每帧约 350 次（共 360 行）      -> 每行都没收满 40 个
            //     ITSS ≈ ITSM（几乎全同号）            -> It = cur - 0 恒为正
            //----------------------------------------------------------
            if (I_rd_valid && (rcnt != 6'd40)) begin
                prev_mem[rcnt] <= I_rd_data;         // rcnt 只会到 39
                rcnt <= rcnt + 6'd1;                 // 40 = 已收满
            end

            case (st)
            //----------------------------------------------------------
            ST_IDLE: begin
                if (f_cnt >= WL && ~f_empty) begin
                    ln_rdy_cnt <= ln_rdy_cnt + 32'd1;
                    rd_i <= 6'd0;
                    cw   <= 6'd0;
                    st   <= ST_FIFO;
                end
            end
            //----------------------------------------------------------
            ST_FIFO: begin                    // 取 40 个字
                if (f_re)
                    rd_i <= rd_i + 6'd1;
                if (rd_go_d && (cw == 6'd39)) begin
                    bcnt <= 6'd0;
                    rcnt <= 6'd0;                 // 本行开始收集读回
                    if (use_idx0) line_idx <= 10'd0;
                    line_addr <= BASE_ADDR
                               + ({15'd0, use_idx0 ? 10'd0 : line_idx} << 8)
                               + ({15'd0, use_idx0 ? 10'd0 : line_idx} << 6);
                    st   <= ST_DDRRD;
                end
            end
            //----------------------------------------------------------
            ST_DDRRD: begin                   // 发 40 个读命令
                if (I_ready) begin
                    if (bcnt == 6'd39) begin
                        bcnt <= 6'd0;
                        // 这里**绝不能**复位 rcnt：读回数据在本状态期间就已经开始
                        // 到达（rcnt 已经数到几十），在这里清零会让剩下的读回数据
                        // 从 prev_mem[0] 重新覆盖。rcnt 只在每行开始时
                        // （ST_FIFO -> ST_DDRRD）复位一次。详见下面 case 外的说明。
                        //
                        // ★ 发完读命令**先等读回收齐**再进 ST_WR。
                        //   早先是发完就直接进 ST_WR，靠"读延迟40拍、仲裁25%占空比"
                        //   的时序凑巧让读回及时到齐 —— 逻辑上没有任何保证。
                        //   一旦某拍没到齐，ST_WR 第一拍就会拿 prev_mem 的复位值/
                        //   上一行残留去算 It 和 lk_dif，而且 ITER 可能仍是 0，
                        //   表现为 ITSM/ITSS/LKAX 不可信但没有任何报错。
                        drain_cnt <= 16'd0;
                        st        <= ST_DRAIN;
                    end
                    else bcnt <= bcnt + 6'd1;
                end
            end
            //----------------------------------------------------------
            ST_DRAIN: begin
                if (rcnt == 6'd40) begin
                    st <= ST_WR;
                end
                else if (drain_cnt >= DRAIN_MAX) begin
                    // err_drain_to <= 1'b1;   ← 删掉，由 assign 自动产生
                    st <= ST_WR;
                end
                else begin
                    drain_cnt <= drain_cnt + 16'd1;
                end
            end 
            //----------------------------------------------------------
            ST_WR: begin                      // 写回 + 算 It（此时 prev_mem 已全部有效）
                // ★ sof_new 与 ST_WR 同拍时，上面的清零会被这里的累加
                //   覆盖（非阻塞后写胜），帧首标志丢失、末几行统计算进下一帧。
                //   正常时序 sof_new 落在 ST_IDLE，但 FIFO 积压时可能撞上。
                if (I_ready && !sof_new) begin
                    it_px_acc  <= it_px_acc  + 32'd16;
                    it_sum_acc <= it_sum_acc + sum16;
                    it_sgn_acc <= it_sgn_acc + sgn16;
                    if (bcnt == 6'd39) begin
                        bcnt     <= 6'd0;
                        ln_acc   <= ln_acc + 32'd1;
                        line_idx <= line_idx + 10'd1;
                        st       <= ST_IDLE;   // 读回已在 ST_DRAIN 收齐，不必再等
                    end
                    else bcnt <= bcnt + 6'd1;
                end
            end
            default: st <= ST_IDLE;
            endcase

            // ★ st_err 的两个来源合成一次加法，避免同拍互相覆盖
            if (err_drain_to | err_full_evt) st_err <= st_err + 32'd1;
        end
    end



endmodule
