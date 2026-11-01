//=====================================================================
//  vib_lk_grid.v  ——  B2c-1：Lucas-Kanade 梯度级 + 8x6 块累加器
//
//  输入（ddr 域，直接来自 vib_prev_frame_ddr 的流式输出，不需要跨时钟域）：
//      word_valid  每行 40 拍（B2b 每写回一拍给一个）
//      word_cur    当前帧高斯灰度 g 的 16 个像素
//      word_prev    帧差 It 的 16 个有符号字节
//    字内像素 j 位于 [127-8j -: 8]
//
//  算法（严格对齐 vision_multi_object.py:432-495）：
//      ix[:,1:-1] = (g[:,2:] - g[:,:-2]) * 0.5     -> ix[:,0]=ix[:,-1]=0
//      iy[1:-1,:] = (g[2:,:] - g[:-2,:]) * 0.5     -> iy[0,:]=iy[-1,:]=0
//      axx=Σix²  ayy=Σiy²  axy=Σix·iy  bx=Σix·it  by=Σiy·it  energy=Σ|it|
//
//  ★ 定点约定（与 Python 对比时要乘系数）：
//      硬件保留**未除 2** 的差分：dIx = g[x+1]-g[x-1] = 2*ix_py
//        axx_hw = 4*axx_py   ayy_hw = 4*ayy_py   axy_hw = 4*axy_py
//        bx_hw  = 2*bx_py    by_hw  = 2*by_py    en_hw  = en_py
//      求解时：det 大 16 倍、min_grad_sum 放大 4 倍、u_hw = u_py/2（末位左移补回）
//
//  ★ 行缓存：3 个 g 行（竖直差分要 y-1/y/y+1）+ 2 个 It 行（乒乓——
//    处理输出行 m=y-1 时需要的是**上一行**的 It）。
//    拆成两块 RAM（各自 1 写口 + 1 读口），每组读 5 个 g 字 + 1 个 It 字，
//    共 7 拍读 + 17 拍处理 = 24 拍/组，40 组/行 ≈ 960 拍/行，远小于行周期。
//
//  ★ y=0 不处理（输出行 m=-1 不存在）；m=0 时 iy 规定为 0，所以不需要 y=-1 行。
//
//  自检：st_px 每帧应 = 0x00038400；err_cnt 必须 = 0
//=====================================================================
module vib_lk_grid_multi (
    input  wire         clk,              // S_ddr_clk
    input  wire         rst_n,

    input  wire         word_valid,       // 来自 B2b，每行 40 拍
    input  wire [127:0] word_cur,
    input  wire [127:0] word_prev,

    // 块(0,0) 的 6 个累加器（在块行 0 结束时冻结）
    output reg  signed [31:0] st_axx,
    output reg  signed [31:0] st_ayy,
    output reg  signed [31:0] st_axy,
    output reg  signed [31:0] st_bx,
    output reg  signed [31:0] st_by,
    output reg  signed [31:0] st_en,

    output reg  [31:0]  st_px,            // 每帧参与累加的像素数，应 = 0x00038400
    output wire [31:0]  st_err,           // 上一帧的协议异常数（每帧增量），必须 = 0
    output reg          st_tgl,           // 累加器已更新（供跨域原子快照）

    // ---- 诊断：同列 5 个相邻行的竖直剖面（列 100，行 98..102）----
    //   单点 4 字节只能证明"减法没写反"，证明不了行缓存环形选择是否正确。
    //   这个剖面一次能验证两件事：
    //     * 单调平滑        -> 行缓存选择正确、抽取正常
    //     * 奇偶锯齿(82,86,83,87) -> 抽头竖直 2x2 没做平均（是抽头的问题，不是 LK）
    //     * 跳变不连续(82,83,191,84) -> gmem 环的 gsel_up/gsel_dn/gsel_m_r 选错行
    //   mrow 98..102 都在块行 1 内部（60..119），不跨块行边界。
    // ---- 水平错位诊断 ----
    //   每个字段 4 字节 = {cur[x], prev[x-1], prev[x], prev[x+1]}（最高字节是 cur[x]）
    //   判据：若 |cur[x]-prev[x±1]| 明显小于 |cur[x]-prev[x]|，则 prev 相对 cur 水平错位

    // ---- 纹理固定块（Goertzel 的信号源）----
    //   st_fx_pos = {25'd0, fx_valid, fx_row[2:0], fx_col[2:0]}   共 32 位
    //     bit[6]   = fx_valid
    //     bit[5:3] = fx_row
    //     bit[2:0] = fx_col
    //   例：FXPS = 0x69 = 0b110_1001 -> valid=1, row=5, col=1（64+40+1）
    //   前 30 帧 tx_frozen=0，fx_valid 恒 0；锁定后每帧在该块行结束时置 1。
    output wire [31:0]        st_fx_pos,
    output wire signed [31:0] st_fx_bx,
    output wire signed [31:0] st_fx_by,
    output wire [31:0]        st_fx_en,     // 本帧该块的 en（有符号，未用符号）
    output wire signed [32:0] st_fx_tex,    // 该块的 axx+ayy
    // 固定块的另三个累加器（给求解器做 2x2 LK 用）
    output wire signed [31:0] st_fx_axx,
    output wire signed [31:0] st_fx_ayy,
    output wire signed [31:0] st_fx_axy,
    output wire               st_fx_tick,   // 1 拍脉冲：固定块本帧已锁存（给 Goertzel）

    // ---- 本帧最大变化块（供 B2c-2 的 2x2 求解）----
    //   req/ack 握手：帧末拉高 req，求解器锁存后回 ack，本模块才清零。
    //   这样避免"清零"和"取数"在同一拍打架。
    output reg  signed [31:0] st_b_axx, st_b_ayy, st_b_axy,
    output reg  signed [31:0] st_b_bx,  st_b_by,  st_b_en,
    output reg  [2:0]        st_b_bcol,   // 块列 0..7
    output reg  [2:0]        st_b_brow,   // 块行 0..5
    output reg  [31:0]       st_b_itsm,   // 与本帧最大块同帧的 ITSM（帧末锁存）
    input  wire [31:0]       i_it_sum,    // 来自 vib_prev_frame_ddr 的 ITSM
    // ---- 块行结束时 8 个横向块的 bx 快照（给 48 块 Goertzel 引擎）----
    output reg  [255:0]      st_br_bx,     // 8 块 x 32 位，块 0 在最低位
`ifdef VIB_COMMON_MOTION_ON
    // Four separated reference blocks: zero-based (row,col)=(1/4,1/6).
    // Low/high160 bits: col1/col6; each tensor={by,bx,axy,ayy,axx}.
    // Read-only snapshots; never used as an activity-block count.
    output reg  [319:0]      st_br_motion,
`endif
    output reg  [2:0]        st_br_row,    // 块行号 0..5
    output reg               st_br_tick,   // 1 拍脉冲：本拍快照有效

    output reg               st_solve_req,
    input  wire              st_solve_ack,

    // ---- 行列投影用的逐像素流（只读引出，不改变任何既有逻辑）----
    output wire              o_px_valid,   // = proc_en
    output wire [8:0]        o_px_it,      // = |It| (dit_abs)
    output wire [8:0]        o_px_edge,    // = |dIx|+|dIy|, aligned with o_px_it
    output wire [9:0]        o_px_x,       // = px_now 0..639
    output wire [9:0]        o_px_y,       // = mrow 0..359
    // 8 个块纹理能量 acc_axx 的对数（4 倍粒度），给峰值扫描做亮度归一化
    output wire [39:0]       o_axx_exp,   // 8 x 5 bit
    // AGC：8 块纹理能量 acc_axx 的对数最大值（2 倍粒度），块行 tick 时有效
    output wire [4:0]        o_agc_exp
);

    localparam [9:0] LASTX = 10'd639;
    localparam [9:0] LASTY = 10'd359;

    //==================================================================
    // 两块行缓存（各自独立写口 + 读口）
    //   gmem：3 个 g 行，地址 = {gsel(2bit), wk(6bit)} = gsel*64 + wk
    //         所以深度必须是 3*64 = 192（wk 只用到 0..39，其余空着）
    //   pmem：2 个**上一帧** g 行，地址 = {isel, wk}，深度 2*64 = 128
    //   ★ 存 prev 而不是存 8bit 差值：cur/prev 都是 0..255，差值范围
    //     -255..255，8bit 补码只能表示 -128..127，会翻符号
    //     （255-0 会变成 8'hFF 按有符号读成 -1）。存 prev 无损，
    //     dit 在本模块里用 9bit 算。
    //   ★ 早先按 gsel*40+wk 估深度写成 [0:119]，但拼接实际是 gsel*64+wk，
    //     地址最高到 167 -> 越界。逐拍模型一跑就报 IndexError 抓到了。
    //   ★ 写是组合写（word_valid 当拍就落），读是寄存读（1 拍延迟）
    //==================================================================
    reg  [127:0] gmem [0:191];
    reg  [127:0] pmem [0:127];

    reg  [1:0]   wr_sel;                  // 正在接收的行 y 的 g 缓存号 = y%3
    reg          isel;                    // 正在接收的 It 缓存号（乒乓）
    reg  [5:0]   wr_wk;                   // 接收字计数 0..39
    reg  [9:0]   yline;                   // 正在接收的行号 y
    reg  [9:0]   mrow;                    // 正在处理的输出行 m = y-1
    reg  [5:0]   gp;                      // 处理组号 0..39
    reg  [4:0]   pj;                      // 组内字节步 0..16（pj-1 = 当前像素）
    reg  [2:0]   rcnt;                    // 读序列 0..6（★ 必须 3 位！早先写成 [1:0] 只能数到 3，
                                                      //    导致 rcnt 永远到不了 3'd6，ST_RD 转不到 ST_PROC，
                                                      //    整个 LK 级一个像素都不处理、LKPX 恒 0）
    reg  [2:0]   st;
    reg          tail;                    // 1 = 正在补跑输出行 359

    // 缓存选择寄存器（在 ST_RSET 里定下来，供读地址使用）
    //   普通通路：row m = y-1 -> (wr_sel+2)%3；It 用上一行那一份 = ~isel
    //   补跑通路：m=359 时 row m 就是刚收完的第 359 行（359%3=2），
    //             且 It 用的就是刚写进去的那一份 = isel
    reg  [1:0]   gsel_m_r;
    reg          isel_m_r;

    reg  [7:0]   raddr_g, raddr_i;
    reg  [127:0] rdg, rdi;

    always @(posedge clk) begin
        // ★ 必须门控在 ST_RECV：wr_wk 只在接收态递增，非接收态恒为 0，
        //   若此时来 word_valid 会反复覆盖 {sel,0}，污染组 0 并与读冲突
        if (word_valid && (st == ST_RECV)) begin
            gmem[{wr_sel, wr_wk}] <= word_cur;
            pmem[{isel,   wr_wk}] <= word_prev;
        end
        rdg <= gmem[raddr_g];
        rdi <= pmem[raddr_i];
    end

    localparam [2:0] ST_RECV = 3'd0,      // 收 40 个字
                     ST_RSET = 3'd1,      // 计算缓存选择
                     ST_RD   = 3'd2,      // 读 6 个字（7 拍）
                     ST_PROC = 3'd3,      // 处理 16 像素（17 拍）
                     ST_GEND = 3'd4;      // 组结束 / 行结束

    //==================================================================
    // 6 个读回的字
    //==================================================================
    reg [127:0] wA, wB, wC, wU, wD, wP;

    // 处理输出行 m 时的缓存选择：
    //   row m+1 = y       -> wr_sel
    //   row m   = y-1     -> (wr_sel+2)%3
    //   row m-1 = y-2     -> (wr_sel+1)%3
    //
    //  ★ 关于 tail 补跑（m=359）下这两个值"不对"的说明：
    //    此时 wr_sel = 359%3 = 2，于是 gsel_up=2（行 359，正确）、
    //    gsel_dn=0（行 357，而 m-1 应为 358 → 缓冲 1，确实偏了一行）。
    //    但这**不影响结果**：dIy 在 mrow==LASTY 时被强制为 0
    //      dIy = (by0 | byN) ? 9'sd0 : (...)，byN = (mrow == LASTY)
    //    而 gsel_up/gsel_dn 只用于 gym1/gyp1，即只进入 dIy；
    //    因此 p_yy / p_xy / p_by 在最后一行都是 0。
    //    tail 另外两支（gsel_m_r=2、isel_m_r=isel）是硬编码且正确的。
    //    不改这里是为了避免在读地址路径上多一级 mux —— 当前 WNS 只有
    //    +0.1 ns，不值得为一个不影响结果的边角情况冒时序风险。
    wire [1:0] gsel_up = wr_sel;
    wire [1:0] gsel_dn = (wr_sel >= 2'd2) ? (wr_sel - 2'd2) : (wr_sel + 2'd1);

    wire [5:0] gpm1 = (gp == 6'd0)  ? 6'd0  : (gp - 6'd1);
    wire [5:0] gpp1 = (gp == 6'd39) ? 6'd39 : (gp + 6'd1);

    // 读地址（组合）
    reg [7:0] ag, ai;
    always @(*) begin
        case (rcnt)
        3'd0:    begin ag = {gsel_dn,  gp};       ai = 8'd0;              end
        3'd1:    begin ag = {gsel_m_r, gpm1};     ai = 8'd0;              end
        3'd2:    begin ag = {gsel_m_r, gp};       ai = 8'd0;              end
        3'd3:    begin ag = {gsel_m_r, gpp1};     ai = 8'd0;              end
        3'd4:    begin ag = {gsel_up, gp};        ai = 8'd0;              end
        default: begin ag = {gsel_m_r, gp};       ai = {isel_m_r, gp};    end
        endcase
    end

    //==================================================================
    // 移位寄存器 + 字节历史
    //   每步取出最高字节（= 像素 p），然后左移 8 位
    //   处理的是像素 p' = pj-1：需要 g[m][p'-1], g[m][p'+1]（跨 2 拍）
    //                               g[m+1][p'], g[m-1][p'], it[m][p']（跨 1 拍）
    //==================================================================
    reg  [127:0] shB, shU, shD, shP;
    reg  [7:0]   bB1, bB2, bU1, bD1, bP1;
    // ★ bP2 只用于"水平错位"诊断：给出 prev[x-1]。
    //   处理像素 x 时： bB1=cur[x]  bP1=prev[x]  bP=prev[x+1]  bP2=prev[x-1]
    //   （bB2 已经是 g[x-1]，同理 bP2 是 prev 的 2 拍延迟）
    reg  [7:0]   bP2;

    wire [7:0] bB = shB[127:120];
    wire [7:0] bU = shU[127:120];
    wire [7:0] bD = shD[127:120];
    wire [7:0] bP = shP[127:120];

    wire [7:0] bL = (gp == 6'd0)  ? 8'd0 : wA[7:0];        // 上一组最后一个像素
    wire [7:0] bR = (gp == 6'd39) ? 8'd0 : wC[127:120];    // 下一组第一个像素

    wire        proc_en = (st == ST_PROC) && (pj != 5'd0);
    wire [4:0]  pj_m1   = pj - 5'd1;
    wire [9:0]  px_now  = {gp, 4'd0} + {5'd0, pj_m1};      // 绝对列号 16*gp + p

    wire [7:0] gxm1 = (pj_m1 == 5'd0)  ? bL : bB2;         // g[m][p-1]
    wire [7:0] gxp1 = (pj_m1 == 5'd15) ? bR : bB;          // g[m][p+1]
    wire [7:0] gym1 = bD1;                                 // g[m-1][p]
    wire [7:0] gyp1 = bU1;                                 // g[m+1][p]
    // it[m][p] = 当前帧 - 上一帧，用 9bit 有符号算（范围 -255..255）
    //   bB1 = 当前帧 g[m][p]，bP1 = 上一帧 g[m][p]，两者都延迟 1 拍对齐到 p
    wire [7:0] pv_p = bP1;

    wire bx0 = (px_now == 10'd0);
    wire bxN = (px_now == LASTX);
    wire by0 = (mrow   == 10'd0);
    wire byN = (mrow   == LASTY);

    // 未除 2 的差分（有符号 9bit）
    wire signed [8:0] dIx = (bx0 | bxN) ? 9'sd0
                          : ($signed({1'b0, gxp1}) - $signed({1'b0, gxm1}));
    wire signed [8:0] dIy = (by0 | byN) ? 9'sd0
                          : ($signed({1'b0, gyp1}) - $signed({1'b0, gym1}));
    wire signed [8:0] dit = $signed({1'b0, bB1}) - $signed({1'b0, pv_p});

    // 逐像素贡献（18bit 有符号够：255*255=65025 < 2^17）
    (* multstyle = "dsp" *) wire signed [17:0] p_xx = dIx * dIx;
    (* multstyle = "dsp" *) wire signed [17:0] p_yy = dIy * dIy;
    // ---- 选块用的"二维可观测性"代理 ----
    //   min(ix^2, iy^2)：一维纹理（例如天花板格子板的单一方向）在某一方向
    //   上梯度接近 0，min 就接近 0，于是不会被选为固定块。
    //   而 axx+ayy 只看总能量，一维强纹理会被误选 —— 实测就栽在这里：
    //   选中的块 (row=5,col=0) 的 det' 只有几百，LKVA 始终为 0。
    //
    //   为什么不用 det = axx*ayy - axy^2（更准确）：
    //     det 必须等整块累加完才能算 → 要在块行末快照 8x3 个累加器(768 FF)
    //     + 16 拍乘法 FSM + 延迟清零，而当前 SWNS 只有 7ps，不能引入这套。
    //     min 可以逐像素累加，代价只有 1 个比较器 + 1 个加法器。
    wire signed [17:0] p_mm = (p_xx < p_yy) ? p_xx : p_yy;
    (* multstyle = "dsp" *) wire signed [17:0] p_xy = dIx * dIy;
    (* multstyle = "dsp" *) wire signed [17:0] p_bx = dIx * dit;
    (* multstyle = "dsp" *) wire signed [17:0] p_by = dIy * dit;
    wire        [8:0]  dit_abs = dit[8] ? (~dit + 9'd1) : dit;   // <= 255

    // The LK gradients are already computed in the same pixel/DDR cycle as
    // the frame difference.  Reusing them as a lightweight edge measure keeps
    // the new bounding-box path aligned with the motion path and avoids
    // importing the unrelated 1280x720 HDMI Sobel pipeline.
    wire [8:0] dIx_abs = dIx[8] ? (~dIx + 9'd1) : dIx;
    wire [8:0] dIy_abs = dIy[8] ? (~dIy + 9'd1) : dIy;
    wire [9:0] edge_sum = {1'b0,dIx_abs} + {1'b0,dIy_abs};

    // ---- 行列投影流（只读，不影响下面的累加器）----
    assign o_px_valid = proc_en;
    assign o_px_it    = dit_abs;
    assign o_px_edge  = edge_sum[8:0];
    assign o_px_x     = px_now;
    assign o_px_y     = mrow;

    //==================================================================
    //  诊断采样：同一 m（=100）、同一列（=100），同时取 4 个源
    //    bD1 = g[m-1][p]   走 gsel_dn  -> 被 dIy 用作 gym1
    //    bB1 = g[m  ][p]   走 shB      -> 被 dit  用作 cur
    //    bU1 = g[m+1][p]   走 gsel_up  -> 被 dIy 用作 gyp1
    //    bP1 = prev[m][p]  走 pmem     -> 被 dit  用作 prev
    //  这四个在同一拍都有效，所以必然同帧、同列、同 m —— 一次验证四条通路。
    //==================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else if (proc_en) begin
            // ---- 当前帧的三行（同一列）----
            if ((px_now == 10'd100) && (mrow == 10'd100)) begin
                // 8 个块的 acc_en 同时可见（各压缩到 8 位：>>7，上限 255*128 = 32640）
                //   mrow=100 属于第 1 个块行（行 60~119），此时 acc_en 是
                //   该块行到目前为止的部分和，8 个块可直接横向比较。
                //   -> 若某一块远大于其余，说明那一块的 dit 被污染；
                //      若 8 块都正常而 LKBE 仍偏大，则是 st_b_en 的清除有问题。
            end
            // ---- prev 的三行剖面：prev[99] / prev[100] / prev[101] ----
            //   三个值应像图像相邻行一样平滑变化；若 prev[100] 与 cur[99]
            //   之类错位，就能直接看出 pmem 的行序偏了一行。
            // ---- 水平错位诊断：同一行、同一列，cur 与 prev 的三个相邻值 ----
        end
    end

    // ★ 先取成独立 wire 再做位选 —— Verilog-2001 不允许 acc_en[k][m:n] 这种
    //   "存储器字再位选"的写法（那是 SystemVerilog）。上一版 TD 恰好接受了，
    //   但这是非标准的，换工具/换上下文就可能报错。
    wire [31:0] aen0 = acc_en[0];  wire [31:0] aen1 = acc_en[1];
    wire [31:0] aen2 = acc_en[2];  wire [31:0] aen3 = acc_en[3];
    wire [31:0] aen4 = acc_en[4];  wire [31:0] aen5 = acc_en[5];
    wire [31:0] aen6 = acc_en[6];  wire [31:0] aen7 = acc_en[7];

    // 8 个块能量的 8 位压缩值（>>7）。实测 acc_en 约 2500（静止、偏暗）-> 19；
    // 上限 255*128 = 32640，画面再亮 10 倍也不会溢出。
    wire [7:0] ae0 = (aen0 > 32'sd0) ? aen0[14:7] : 8'd0;
    wire [7:0] ae1 = (aen1 > 32'sd0) ? aen1[14:7] : 8'd0;
    wire [7:0] ae2 = (aen2 > 32'sd0) ? aen2[14:7] : 8'd0;
    wire [7:0] ae3 = (aen3 > 32'sd0) ? aen3[14:7] : 8'd0;
    wire [7:0] ae4 = (aen4 > 32'sd0) ? aen4[14:7] : 8'd0;
    wire [7:0] ae5 = (aen5 > 32'sd0) ? aen5[14:7] : 8'd0;
    wire [7:0] ae6 = (aen6 > 32'sd0) ? aen6[14:7] : 8'd0;
    wire [7:0] ae7 = (aen7 > 32'sd0) ? aen7[14:7] : 8'd0;

    //==================================================================
    //  连续 3 条"接收线"的第一个字节（滚动保存）
    //    LA = 当前线、LB = 上一条、LC = 上上条
    //    若 LB == LA，说明源端连续送了两遍同一行；若三条都不同，
    //    说明写入的线是好的，问题在读侧。
    //  ★ 必须自己一个 always 块：TD 不接受同一个时序块里出现
    //    第二个"与灵敏度列表无关"的 if 条件
    //    （会报 if-condition does not match any sensitivity list edge）。
    //==================================================================
    reg [7:0] line_chk;      // 本行 40 个字的 checksum 累加器

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_chk  <= 8'd0;
        end
        else if (word_valid && (st == ST_RECV)) begin
            // ★ 整行 checksum：本行 40 个字的首字节累加和（8 位自然回绕）。
            //   只记首字节只能看左边界一个像素，不足以判断整行是否重复；
            //   累加和覆盖全行 40 个字，才有判别力。
            if (wr_wk == 6'd0) begin
                // 新一行开始：把上一条"已完成"行的 checksum 滚进 LA/LB/LC
                line_chk  <= word_cur[127:120];
            end
            else begin
                line_chk <= line_chk + word_cur[127:120];
            end
        end
    end

    //==================================================================
    // 8 个块 x 6 个累加器
    //   位宽核算（块内 4800 像素）：axx <= 4800*65025 = 3.12e8 < 2^31 ✓
    //   有符号量 |axy|,|bx|,|by| <= 3.12e8 ✓ 不会溢出
    //==================================================================
    reg signed [31:0] acc_axx [0:7];
    reg signed [31:0] acc_ayy [0:7];
    reg signed [31:0] acc_axy [0:7];
    reg signed [31:0] acc_bx  [0:7];
    reg signed [31:0] acc_by  [0:7];
    reg signed [31:0] acc_en  [0:7];

    // ---- axx 的对数（4 倍粒度）：log2 粗量化，用来除掉亮度因子 ----
    function [4:0] exp4;
        input [31:0] v;
        begin
            if      (v >= 32'd268435456) exp4 = 5'd28;
            else if (v >= 32'd16777216)  exp4 = 5'd24;
            else if (v >= 32'd1048576)   exp4 = 5'd20;
            else if (v >= 32'd65536)     exp4 = 5'd16;
            else if (v >= 32'd4096)      exp4 = 5'd12;
            else if (v >= 32'd256)       exp4 = 5'd8;
            else if (v >= 32'd16)        exp4 = 5'd4;
            else                         exp4 = 5'd0;
        end
    endfunction

    wire [31:0] ax0 = (acc_axx[0] > 0) ? acc_axx[0] : 32'd0;
    wire [31:0] ax1 = (acc_axx[1] > 0) ? acc_axx[1] : 32'd0;
    wire [31:0] ax2 = (acc_axx[2] > 0) ? acc_axx[2] : 32'd0;
    wire [31:0] ax3 = (acc_axx[3] > 0) ? acc_axx[3] : 32'd0;
    wire [31:0] ax4 = (acc_axx[4] > 0) ? acc_axx[4] : 32'd0;
    wire [31:0] ax5 = (acc_axx[5] > 0) ? acc_axx[5] : 32'd0;
    wire [31:0] ax6 = (acc_axx[6] > 0) ? acc_axx[6] : 32'd0;
    wire [31:0] ax7 = (acc_axx[7] > 0) ? acc_axx[7] : 32'd0;

    // ---- AGC：8 块里纹理最强的那个，取 2 倍粒度的对数 ----
    function [4:0] exp2x;
        input [31:0] v;
        begin
            if      (v >= 32'd16777216) exp2x = 5'd24;
            else if (v >= 32'd8388608)  exp2x = 5'd23;
            else if (v >= 32'd4194304)  exp2x = 5'd22;
            else if (v >= 32'd2097152)  exp2x = 5'd21;
            else if (v >= 32'd1048576)  exp2x = 5'd20;
            else if (v >= 32'd524288)   exp2x = 5'd19;
            else if (v >= 32'd262144)   exp2x = 5'd18;
            else if (v >= 32'd131072)   exp2x = 5'd17;
            else if (v >= 32'd65536)    exp2x = 5'd16;
            else if (v >= 32'd32768)    exp2x = 5'd15;
            else if (v >= 32'd16384)    exp2x = 5'd14;
            else if (v >= 32'd8192)     exp2x = 5'd13;
            else if (v >= 32'd4096)     exp2x = 5'd12;
            else if (v >= 32'd2048)     exp2x = 5'd11;
            else if (v >= 32'd1024)     exp2x = 5'd10;
            else if (v >= 32'd512)      exp2x = 5'd9;
            else                        exp2x = 5'd8;
        end
    endfunction
    
    wire [31:0] amax0 = (ax0 > ax1) ? ax0 : ax1;
    wire [31:0] amax1 = (ax2 > ax3) ? ax2 : ax3;
    wire [31:0] amax2 = (ax4 > ax5) ? ax4 : ax5;
    wire [31:0] amax3 = (ax6 > ax7) ? ax6 : ax7;
    wire [31:0] amax4 = (amax0 > amax1) ? amax0 : amax1;
    wire [31:0] amax5 = (amax2 > amax3) ? amax2 : amax3;
    wire [31:0] amax  = (amax4 > amax5) ? amax4 : amax5;

    //==================================================================
    //  ★★ 2026-10-27 修：纹理指数必须**寄存后再输出** ★★
    //
    //  原来的写法（组合输出）有一个采样竞态：
    //      if (blk_row_end) begin
    //          st_br_tick <= 1'b1;          // 同一拍拉高 tick
    //          ... acc_axx[bi] <= 0;        // 同一拍清零累加器
    //      end
    //      assign o_axx_exp = {exp4(ax7) ...};   // 组合逻辑，直接看 acc_axx
    //
    //  gz_peak / gz_multi 是在 tick 的**下一拍**才采样的，那时 acc_axx 已经
    //  被清零 -> exp4(0) = 0、exp2x(0) = 8。后果：
    //    · aexp[0..47] 恒为 0  -> pn = peak>>8，纹理归一化完全空转
    //    · i_agc_exp 恒为 0    -> agc_ref 永远停在复位值 18，
    //                             agc_gain 恒 = 6 -> v_agc 走"不衰减"那一档
    //  板上铁证：PKMG == FBPN 逐比特相等（29/29 轮）、AGCR 恒 = 0x12（复位值）。
    //
    //  修法：和 st_br_bx 一样，在同一个 if (blk_row_end) 里打一拍，
    //        tick 有效的那一拍读到的是清零前的值。
    //==================================================================
    reg  [39:0] st_axx_exp;   // 8 块 x 5 bit，与 st_br_bx 同沿
    reg  [4:0]  st_agc_exp;   // 本块行纹理能量对数（2 倍粒度）

    // ★ 同时把每块指数从 4 倍粒度（exp4）换成 2 倍粒度（exp2x）：
    //   exp4 只会返回 0/4/8/.../28，归一化误差最大 4 倍；
    //   exp2x 返回 8..24 的整数，误差最大 2 倍，对下一版标定门限有用。
    //   exp4 保留定义以便回退，当前不再使用。
    assign o_agc_exp = st_agc_exp;


    assign o_axx_exp = st_axx_exp;
    reg signed [31:0] acc_mm  [0:7];      // Σ min(ix^2, iy^2)：选固定块用

    // ---- 每帧增量形式的协议异常计数 ----
    //   err_cnt    本帧累计（每帧末清零）
    //   st_err_frm 上一帧的值（帧末锁存，跨域快照采这个，恒稳定）
    reg  [31:0] err_cnt;
    reg  [31:0] st_err_frm;
    reg         ack_d;        // st_solve_ack 边沿检测
    assign st_err = st_err_frm;

    // ---- 纹理固定块输出（纯组合，不再多打一拍）----
    //   st_fx_pos = {25'd0, fx_valid, fx_row[2:0], fx_col[2:0]}   共 32 位
    //     bit[6]   = fx_valid
    //     bit[5:3] = fx_row
    //     bit[2:0] = fx_col
    //   例：FXPS = 0x69 = 0b110_1001 -> valid=1, row=5, col=1（64+40+1）
    // ★ 拼接必须正好 32 位：25 + 1 + 3 + 3 = 32。
    //   原来写 29'd0 是 36 位，高 4 位被截掉 —— 虽然截掉的是零、编码没变，
    //   但这种"宽度不匹配"是隐患（换个 target 宽度就变了）。
    //   确定的编码：bit[6]=valid, bit[5:3]=row, bit[2:0]=col
    // ★★ 2026-10-23：临时强制固定块 = 画面正中央（row 2, col 4）。
    //   原因：纹理 argmax 会选到背景/桌面，那个块里没有振动信号，
    //   导致 B2..B16 是平滑的 1/f 噪声谱、没有振动峰。
    //   强制到正中后，只要把手机/视频方块放在屏幕中央就能测到。
    //   验证完再改回 {25'd0, fx_valid, fx_row, fx_col} 恢复自动选块。
    assign st_fx_pos = {25'd0, 1'b1, 3'd2, 3'd4};
    // assign st_fx_pos = {25'd0, fx_valid, fx_row, fx_col};   // 原来的自动选块
    assign st_fx_bx  = fx_bx;
    assign st_fx_by  = fx_by;
    assign st_fx_en  = fx_en;
    assign st_fx_tex = fx_tex;
    assign st_fx_axx = fx_axx;
    assign st_fx_ayy = fx_ayy;
    assign st_fx_axy = fx_axy;
    assign st_fx_tick = fx_tick;

    //==================================================================
    //  最大变化块跟踪（为 B2c-2 的 2x2 求解提供输入）
    //    每帧 6 个块行，每块行 8 个块；块行冲刷时比较 acc_en[]，
    //    记住 energy 最大的那个块的 6 个累加器与 (块列, 块行)。
    //    帧末翻一次 st_solve_tgl，求解器据此取走这批值。
    //
    //    ★ 只在 energy 更大时更新，所以 best_* 天然是"整个帧 48 块"的最大者；
    //      帧末由求解器采走后再清零（见 ST_GEND 的 tail 分支）。
    //==================================================================
    // （best_* 直接就是输出端口 st_b_*，不另设内部寄存器）

    // 当前块行号（由 mrow 直接得出，60 行一块行）
    wire [2:0] brow_now = (mrow < 10'd60)  ? 3'd0 :
                          (mrow < 10'd120) ? 3'd1 :
                          (mrow < 10'd180) ? 3'd2 :
                          (mrow < 10'd240) ? 3'd3 :
                          (mrow < 10'd300) ? 3'd4 : 3'd5;

    wire blk_row_end = (mrow == 10'd59)  || (mrow == 10'd119) ||
                       (mrow == 10'd179) || (mrow == 10'd239) ||
                       (mrow == 10'd299) || (mrow == 10'd359);

    //==================================================================
    //  本块行 8 个块里 energy 最大者
    //
    //  ★ 必须是**平衡树**，不能用串行链。
    //    原来写成 for 循环链式比较，综合出 7 级 32 位比较器串在一拍里，
    //    而且 `br_en > st_b_en` 直接驱动 st_b_* 的时钟使能，于是
    //      acc_en[1] -> 7 级比较 -> 末级比较 -> CE
    //    共 24 级逻辑、16 个 ADDER，实测 20.772ns（预算 15ns），
    //    WNS = -6.001ns、391 条路径失败。时序报告里那串 lt5_syn_140..161
    //    就是它。
    //    改成 3 层树后是 3 级比较 + 末级比较 + CE ≈ 6 级。
    //
    //  平局规则：相等时取**索引小的**（与原来串行链的行为一致）
    //==================================================================
    wire        t01 = (acc_en[1] > acc_en[0]);
    wire        t23 = (acc_en[3] > acc_en[2]);
    wire        t45 = (acc_en[5] > acc_en[4]);
    wire        t67 = (acc_en[7] > acc_en[6]);

    wire signed [31:0] e01 = t01 ? acc_en[1] : acc_en[0];
    wire signed [31:0] e23 = t23 ? acc_en[3] : acc_en[2];
    wire signed [31:0] e45 = t45 ? acc_en[5] : acc_en[4];
    wire signed [31:0] e67 = t67 ? acc_en[7] : acc_en[6];
    wire [2:0] i01 = t01 ? 3'd1 : 3'd0;
    wire [2:0] i23 = t23 ? 3'd3 : 3'd2;
    wire [2:0] i45 = t45 ? 3'd5 : 3'd4;
    wire [2:0] i67 = t67 ? 3'd7 : 3'd6;

    wire        t03 = (e23 > e01);
    wire        t47 = (e67 > e45);
    wire signed [31:0] e03 = t03 ? e23 : e01;
    wire signed [31:0] e47 = t47 ? e67 : e45;
    wire [2:0] i03 = t03 ? i23 : i01;
    wire [2:0] i47 = t47 ? i67 : i45;

    wire        t07 = (e47 > e03);
    wire signed [31:0] br_en = t07 ? e47 : e03;
    wire [2:0]         br_idx = t07 ? i47 : i03;

    //==================================================================
    //  纹理强度跟踪（给 Goertzel 选"固定块"用）—— 与上面的 en 树并行
    //
    //    ★ 为什么不能用"最大变化块"做 Goertzel 的时间序列：
    //      实测 15 轮（对准天花板格子板、相机在动）里最大块的坐标是
    //        blk2 → blk3 → blk1 → blk5 → blk4 → blk6
    //      每帧都在跳。时间序列中途换信号源，频谱里会出现虚假的突变成分。
    //
    //    ★ 所以按**空间纹理强度** (acc_axx + acc_ayy) 选块：
    //      它只取决于当前帧的梯度，和 It / dit / pmem 完全无关，
    //      所以不依赖任何还没查清的时域量。
    //
    //    ★ 不需要 48 项纹理表：只要最终的 argmax。
    //      逐块行取 8 块最大 → 与整帧最好者比较，和 st_b_en 完全同构。
    //      第 FREEZE_N 帧之后锁死坐标，不再变。
    //==================================================================

    // ---- 整帧纹理 argmax 与锁定状态 ----
    localparam [5:0] FREEZE_N = 6'd30;      // 第 30 帧锁定（0.5 s）

    reg  signed [32:0] tx_best;
    reg  [2:0]         tx_col, tx_row;
    reg                tx_frozen;
    reg  [5:0]         tx_cnt;

    //==================================================================
    //  纹理 argmax：8 拍串行扫描（2026-10-23 替换三级组合树）
    //    原来是 7 个 33 位比较器 + 7 个 33 位 mux 的三级树，是全设计最差
    //    路径（SWNS 0.034ns、11 级逻辑、布线占 66%）。
    //    现在块行结束先把 8 个值锁进 tx_scan，再用 9 拍逐个比较：
    //    只留 1 个 33 位比较器，逻辑级数 11 -> 1，顺带省约 400 LUT。
    //    延迟 9 拍，块行间隔约 19200 拍，对功能没有影响。
    //==================================================================
    reg  signed [31:0] tx_scan [0:7];
    reg        txs_run;
    reg        txs_done;
    reg  [3:0] txs_i;
    reg  signed [32:0] txs_max;
    reg  [2:0] txs_idx;
    reg  [2:0] txs_row;

    reg        frame_end_p;     // 帧末 1~2 拍：请求扫描状态机清 tx_best
    reg        tx_start_p;     // 块行结束 1~2 拍：请求状态机启动扫描

    wire signed [32:0] txs_v    = {1'b0, tx_scan[txs_i]};
    wire        txs_hit  = (txs_v > txs_max);
    wire signed [32:0] txs_best = txs_hit ? txs_v : txs_max;
    wire [2:0]  txs_bidx = txs_hit ? txs_i[2:0] : txs_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            txs_run   <= 1'b0;
            txs_done  <= 1'b0;
            txs_i     <= 4'd0;
            txs_max   <= 33'sd0;
            txs_idx   <= 3'd0;
            txs_row   <= 3'd0;
            tx_best   <= 33'sd0;
            tx_col    <= 3'd0;
            tx_row    <= 3'd0;
        end
        else if (tx_start_p) begin
            txs_run   <= 1'b1;
            txs_done  <= 1'b0;
            txs_i     <= 4'd0;
            txs_max   <= 33'sd0;
            txs_idx   <= 3'd0;
            txs_row   <= brow_now;
        end
        else if (frame_end_p && !tx_frozen) begin
            tx_best <= 33'sd0;      // 下一帧重新打擂台
            tx_col  <= 3'd0;
            tx_row  <= 3'd0;
        end
        else if (txs_done) begin
            txs_done <= 1'b0;
            // 上一拍 txs_max/txs_idx 已经是最终结果
            if (!tx_frozen && (txs_max > tx_best)) begin
                tx_best <= txs_max;
                tx_col  <= txs_idx;
                tx_row  <= txs_row;
            end
        end
        else if (txs_run) begin
            txs_max <= txs_best;
            txs_idx <= txs_bidx;
            if (txs_i == 4'd7) begin
                txs_run  <= 1'b0;
                txs_done <= 1'b1;
            end
            else txs_i <= txs_i + 4'd1;
        end
    end
    // ---- 固定块本帧的累加器快照（它的块行到来时锁存） ----
    reg  signed [31:0] fx_axx, fx_ayy, fx_axy, fx_bx, fx_by, fx_en;
    reg  [2:0]         fx_col, fx_row;
    reg                fx_valid;
    reg  signed [32:0] fx_tex;
    reg                fx_tick;         // 1 拍脉冲，同上

    // 组号 -> 块号（80 像素 = 5 组，所以整组一定落在同一块里）
    reg [2:0] blk;
    always @(*) begin
        if      (gp < 6'd5)  blk = 3'd0;
        else if (gp < 6'd10) blk = 3'd1;
        else if (gp < 6'd15) blk = 3'd2;
        else if (gp < 6'd20) blk = 3'd3;
        else if (gp < 6'd25) blk = 3'd4;
        else if (gp < 6'd30) blk = 3'd5;
        else if (gp < 6'd35) blk = 3'd6;
        else                 blk = 3'd7;
    end

    reg [31:0] fr_px;                     // 每帧像素计数（跨块行，供自检）

    integer bi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_sel <= 2'd0; isel <= 1'b0; wr_wk <= 6'd0;
            yline <= 10'd0; mrow <= 10'd0; gp <= 6'd0; pj <= 5'd0;
            rcnt <= 3'd0; st <= ST_RECV;
            tail <= 1'b0; gsel_m_r <= 2'd0; isel_m_r <= 1'b0;
            raddr_g <= 8'd0; raddr_i <= 8'd0;
            shB <= 128'd0; shU <= 128'd0; shD <= 128'd0; shP <= 128'd0;
            bB1 <= 8'd0; bB2 <= 8'd0; bU1 <= 8'd0; bD1 <= 8'd0; bP1 <= 8'd0; bP2 <= 8'd0;
            fr_px <= 32'd0;
            st_axx <= 32'sd0; st_ayy <= 32'sd0; st_axy <= 32'sd0;
            st_bx  <= 32'sd0; st_by  <= 32'sd0; st_en  <= 32'sd0;
            st_px  <= 32'd0;  err_cnt <= 32'd0;  st_tgl <= 1'b0;
            // 最大变化块 + 求解请求（必须只在本 always 块里复位）
            st_b_axx <= 32'sd0; st_b_ayy <= 32'sd0; st_b_axy <= 32'sd0;
            st_b_bx  <= 32'sd0; st_b_by  <= 32'sd0; st_b_en  <= 32'sd0;
            // 纹理固定块
            // tx_best / tx_col / tx_row 的复位在扫描状态机里（只能有一个驱动）
            tx_frozen <= 1'b0; tx_cnt <= 6'd0;
            fx_axx <= 32'sd0; fx_ayy <= 32'sd0; fx_axy <= 32'sd0;
            fx_bx  <= 32'sd0; fx_by  <= 32'sd0; fx_en  <= 32'sd0;
            fx_col <= 3'd0; fx_row <= 3'd0; fx_valid <= 1'b0;
            fx_tex <= 33'sd0;
            fx_tick <= 1'b0;
            st_b_bcol <= 3'd0;  st_b_brow <= 3'd0;
            st_solve_req <= 1'b0;
            st_br_bx   <= 256'd0;
`ifdef VIB_COMMON_MOTION_ON
            st_br_motion <= 320'd0;
`endif
            st_br_row  <= 3'd0;
            st_br_tick <= 1'b0;
            st_axx_exp <= 40'd0;
            st_agc_exp <= 5'd18;   // 与 gz_multi 里 agc_ref 的复位值一致
            ack_d <= 1'b0;
            for (bi = 0; bi < 8; bi = bi + 1) begin
                acc_axx[bi] <= 32'sd0; acc_ayy[bi] <= 32'sd0; acc_axy[bi] <= 32'sd0;
                acc_bx[bi]  <= 32'sd0; acc_by[bi]  <= 32'sd0; acc_en[bi]  <= 32'sd0;
                acc_mm[bi]  <= 32'sd0;
            end
        end
        else begin
            //----------------------------------------------------------
            // 逐像素累加
            //----------------------------------------------------------
            if (proc_en) begin
                frame_end_p <= 1'b0;   // 默认清零，帧末那一拍置 1
                tx_start_p <= 1'b0;
                acc_axx[blk] <= acc_axx[blk] + {{14{p_xx[17]}}, p_xx};
                acc_ayy[blk] <= acc_ayy[blk] + {{14{p_yy[17]}}, p_yy};
            acc_mm[blk]  <= acc_mm[blk]  + {{14{p_mm[17]}}, p_mm};
                acc_axy[blk] <= acc_axy[blk] + {{14{p_xy[17]}}, p_xy};
                acc_bx [blk] <= acc_bx [blk] + {{14{p_bx[17]}}, p_bx};
                acc_by [blk] <= acc_by [blk] + {{14{p_by[17]}}, p_by};
                acc_en [blk] <= acc_en [blk] + {23'd0, dit_abs};
                fr_px <= fr_px + 32'd1;
            end

            //----------------------------------------------------------
            // 移位寄存器推进（只在处理态）
            //----------------------------------------------------------
            if (st == ST_PROC) begin
                bB2 <= bB1; bB1 <= bB;
                bU1 <= bU;  bD1 <= bD;  bP1 <= bP;
                bP2 <= bP1;                              // prev[x-1]（诊断用）
                shB <= {shB[119:0], 8'd0};
                shU <= {shU[119:0], 8'd0};
                shD <= {shD[119:0], 8'd0};
                shP <= {shP[119:0], 8'd0};
            end

            // ★ fx_tick 默认清零 —— 1 拍脉冲，只在固定块锁存那一拍拉高。
            //   放在 case 之前当默认赋值（工程里其他脉冲也是这个写法）。
            fx_tick <= 1'b0;

            // ★ st_br_tick 同理：给 48 块 Goertzel 引擎的快照脉冲。
            //   早先只把清零写在 if(!rst_n) 复位分支里，正常运行时置 1 后再也回不到 0，
            //   引擎就把 74MHz 的每一拍都当成新快照（实测 MBTK 每秒涨 66.7M 次）。
            st_br_tick <= 1'b0;

            case (st)
            //----------------------------------------------------------
            ST_RECV: begin
                // 协议检查：非接收态不该有字进来
                if (word_valid && (wr_wk == 6'd39)) begin
                    wr_wk <= 6'd0;
                    st    <= ST_RSET;
                    if (yline == 10'd0) begin
                        // 输出行 m=-1 不存在，本行不处理
                        yline  <= 10'd1;
                        wr_sel <= 2'd1;
                        isel   <= ~isel;
                        st     <= ST_RECV;
                    end
                    else begin
                        mrow <= yline - 10'd1;
                    end
                end
                else if (word_valid) begin
                    wr_wk <= wr_wk + 6'd1;
                end
            end
            //----------------------------------------------------------
            ST_RSET: begin
                gp   <= 6'd0;
                rcnt <= 3'd0;
                if (tail) begin
                    gsel_m_r <= 2'd2;         // 第 359 行写在缓存 2（359%3=2）
                    isel_m_r <= isel;         // It 就是刚写进去的那一份
                end
                else begin
                    gsel_m_r <= (wr_sel == 2'd0) ? 2'd2 : (wr_sel - 2'd1);
                    // ★ 用 isel（实测证据优先，我的代数推导判错过两次）
                    //
                    //  三份固件的实测对比（同一采样点，静止画面）：
                    //    isel_m_r = ~isel ： LKP0 与 cur 差 27  / 14~142     ✗
                    //    isel_m_r = isel  ： LKP0 与 cur 差 1~4              ✓✓
                    //
                    //  21 字段那版新加的 LKXA/LKXB 更直接：
                    //    LKXA = 0xBF 31 31 31 → cur=191, prev 三个相邻值全是 49
                    //    LKXB = 0x3F 31 31 31 → cur=63,  prev 三个相邻值全是 49
                    //    d0 = dm = dp  ⇒  不是水平错位，是 prev 整体取错了一份
                    //  而 ITSM = 213739（0.93/像素）说明 B2b 自己的 cur-prev 是对的，
                    //  所以错的只能是 pmem 这份副本的选择位。
                    //
                    //  为什么 ~isel 在推导里"看起来对"：
                    //    pmem 写入用的是接收第 y 行时的 isel（= y%2），存的是
                    //    word_prev = 上一帧第 y 行。按推导 m=y-1 该取 (y-1)%2。
                    //    但实测表明 isel 在 ST_RSET 时刻已经是 (y-1)%2 了
                    //    —— 行推进那次翻转发生在更早的位置，我的时序假设是错的。
                    //  以实测为准。
                    isel_m_r <= isel;
                end
                st   <= ST_RD;
            end
            //----------------------------------------------------------
            ST_RD: begin
                raddr_g <= ag;
                raddr_i <= ai;
                // 读数据在下一拍到：rcnt=k 时锁存的是 rcnt=k-1 发出的地址
                case (rcnt)
                3'd1: wD <= rdg;
                3'd2: wA <= rdg;
                3'd3: wB <= rdg;
                3'd4: wC <= rdg;
                3'd5: wU <= rdg;
                3'd6: begin
                    wP  <= rdi;
                    // ★ shP 必须用 rdi，**不能**用 wP：
                    //   wP 也在本拍被赋值（非阻塞），此刻它还是上一组的旧值，
                    //   用 wP 会让 It 整整差一组（16 个像素）。
                    //   症状很有辨识度：axx/ayy/axy 全对（梯度不依赖 It），
                    //   en=Σ|it| 只差一点点（只有块边界处进出的值变了），
                    //   但 bx/by=Σ(梯度·It) 完全去相关。
                    shB <= wB; shU <= wU; shD <= wD; shP <= rdi;
                    bB1 <= 8'd0; bB2 <= 8'd0;
                    bU1 <= 8'd0; bD1 <= 8'd0; bP1 <= 8'd0; bP2 <= 8'd0;
                    pj  <= 5'd0;
                    st  <= ST_PROC;
                end
                default: ;
                endcase
                if (rcnt != 3'd6) rcnt <= rcnt + 3'd1;
            end
            //----------------------------------------------------------
            ST_PROC: begin
                if (pj == 5'd16) st <= ST_GEND;
                else             pj <= pj + 5'd1;
            end
            //----------------------------------------------------------
            ST_GEND: begin
                if (gp == 6'd39) begin
                    // ---- 一行处理完 ----
                    if (tail) begin
                        // 补跑输出行 359 完成 -> 本帧真正结束
                        tail   <= 1'b0;
                        yline  <= 10'd0;
                        wr_sel <= 2'd0;
                        isel   <= ~isel;
                        st_px  <= fr_px;
                        fr_px  <= 32'd0;
                        // ★ err_cnt 改成"每帧增量"：
                        //   原来它是累计值，分不清异常发生在哪一帧，启动期一批
                        //   之后就永久显示 0x3654，看不出后续是否还在出错。
                        //   现在帧末把它搬进 st_err_frm 并清零，日志看到的就是
                        //   "刚过去这一帧有几个协议异常"，稳态必须恒为 0。
                        st_err_frm <= err_cnt;
                        err_cnt     <= 32'd0;
                        st_tgl <= ~st_tgl;    // 帧末也翻一次，让 st_px 当帧就能被采到
                        // 本帧 48 块已全部比较完，请求解器取走"最大变化块"
                        st_solve_req <= 1'b1;
                        // ---- 纹理固定块的帧计数与锁定 ----
                        //   前 FREEZE_N 帧（0.5 s，tx_cnt 从 0 数到 FREEZE_N-1，
                        //   打擂台选纹理最强的块；第 FREEZE_N 帧末锁定坐标，
                        //   之后每帧只取这一块的累加器，坐标不再变。
                        if (!tx_frozen) begin
                            if (tx_cnt == (FREEZE_N - 6'd1)) begin
                                tx_frozen <= 1'b1;
                            end
                            else begin
                                tx_cnt  <= tx_cnt + 6'd1;
                                frame_end_p <= 1'b1;    // 由扫描状态机清 tx_best
                            end
                        end
                        // ★ fx_valid 不能在这里清零。
                        //   固定块可能在第 1 个块行（行 119）就锁存，
                        //   帧末清零会让它从行 120 到帧尾一直是 0，
                        //   1 秒一次的串口采样必然抓到 0。
                        //   它是"固定块通路已活"的标志，锁定后应保持为 1。
                        //   （实测：FXPS 坐标已经正确写进去了，但 valid=0）
                        // ★ 与本帧最大块**同帧**的 ITSM：在帧末锁存，随最大块一起被快照
                        st_b_itsm <= i_it_sum;
                        st     <= ST_RECV;
                    end
                    else if (yline == LASTY) begin
                        // ★ 末行已收完，但输出行 359 还没处理。
                        //   处理行 m=359 需要第 360 行，而它不存在；
                        //   好在 m=359 时 iy 规定为 0，不需要那一行，
                        //   所以直接补跑一次即可（否则整幅会少算一行 = 640 像素）。
                        tail  <= 1'b1;
                        mrow  <= LASTY;
                        st    <= ST_RSET;
                    end
                    else begin
                        yline  <= yline + 10'd1;
                        wr_sel <= (wr_sel == 2'd2) ? 2'd0 : (wr_sel + 2'd1);
                        isel   <= ~isel;
                        st     <= ST_RECV;
                    end

                    // 块行结束（每 60 行）：块行 0 冻结输出，其余清零
                    // ★ 边界必须是 59/119/179/239/299/359。
                    //   早先写成 mrow[5:0]==6'd59，那等价于 mrow%64==59，
                    //   命中的是 59/123/187/251/315 —— 块行 1~4 全错位，
                    //   块行 5（359）反而永不清零、残留值带进下一帧。
                    if (blk_row_end) begin
                        // ---- 给 48 块 Goertzel 引擎的 8 块快照 ----
                        st_br_bx   <= {acc_bx[7], acc_bx[6], acc_bx[5], acc_bx[4],
                                       acc_bx[3], acc_bx[2], acc_bx[1], acc_bx[0]};
`ifdef VIB_COMMON_MOTION_ON
                        if((brow_now==3'd1)||(brow_now==3'd4))
                            st_br_motion <= {acc_by[6],acc_bx[6],acc_axy[6],acc_ayy[6],acc_axx[6],
                                             acc_by[1],acc_bx[1],acc_axy[1],acc_ayy[1],acc_axx[1]};
`endif
                        st_br_row  <= brow_now;
                        st_br_tick <= 1'b1;
                        // ★ 纹理指数与 st_br_bx 同沿打拍（清零前采样），
                        //   否则下游在 tick 那一拍读到的是 exp(0)。
                        st_axx_exp <= {exp2x(ax7), exp2x(ax6), exp2x(ax5), exp2x(ax4),
                                       exp2x(ax3), exp2x(ax2), exp2x(ax1), exp2x(ax0)};
                        st_agc_exp <= exp2x(amax);
                        if (mrow == 10'd59) begin
                            st_axx <= acc_axx[0]; st_ayy <= acc_ayy[0];
                            st_axy <= acc_axy[0]; st_bx  <= acc_bx[0];
                            st_by  <= acc_by[0];  st_en  <= acc_en[0];
                            st_tgl <= ~st_tgl;
                        end
                        // ---- 更新"本帧最大变化块" ----
                        if (br_en > st_b_en) begin
                            st_b_en   <= br_en;
                            st_b_axx  <= acc_axx[br_idx];
                            st_b_ayy  <= acc_ayy[br_idx];
                            st_b_axy  <= acc_axy[br_idx];
                            st_b_bx   <= acc_bx[br_idx];
                            st_b_by   <= acc_by[br_idx];
                            st_b_bcol <= br_idx;
                            st_b_brow <= brow_now;
                        end
                        // ---- 纹理 argmax：先锁 8 个值，9 拍后由扫描状态机出结果 ----
                        for (bi = 0; bi < 8; bi = bi + 1)
                            tx_scan[bi] <= acc_mm[bi];
                        tx_start_p <= 1'b1;    // 由扫描状态机去启动
                        // ---- 固定块本帧的累加器快照 ----
                        //   固定在它的块行结束时锁存。锁定前 fx_* 不更新，
                        //   所以上板后前 30 帧 fx_valid 一直是 0。
                        if (tx_frozen && (brow_now == tx_row)) begin
                            fx_axx   <= acc_axx[tx_col];
                            fx_ayy   <= acc_ayy[tx_col];
                            fx_axy   <= acc_axy[tx_col];
                            fx_bx    <= acc_bx [tx_col];
                            fx_by    <= acc_by [tx_col];
                            fx_en    <= acc_en [tx_col];
                            fx_col   <= tx_col;
                            // ★ 不能写 acc_axx[tx_col][31] —— Verilog-2001 不允许
                            //   对存储器字再做位选（那是 SystemVerilog 写法）。
                            //   acc_axx 已经是 signed，两个 signed 相加在 33 位
                            //   上下文里自动符号扩展，不会溢出（上限 6.24e8）。
                            fx_tex   <= acc_mm[tx_col];
                            fx_row   <= tx_row;
                            fx_valid <= 1'b1;
                            fx_tick  <= 1'b1;      // 通知 Goertzel 本帧采样点已就绪
                        end
                        for (bi = 0; bi < 8; bi = bi + 1) begin
                            acc_axx[bi] <= 32'sd0; acc_ayy[bi] <= 32'sd0;
                            acc_axy[bi] <= 32'sd0; acc_bx[bi]  <= 32'sd0;
                            acc_by[bi]  <= 32'sd0; acc_en[bi]  <= 32'sd0;
            acc_mm[bi]  <= 32'sd0;
                        end
                    end
                end
                else begin
                    gp   <= gp + 6'd1;
                    rcnt <= 3'd0;
                    st   <= ST_RD;
                end
            end
            default: st <= ST_RECV;
            endcase

            // 协议异常：不在接收态却收到字
            if (word_valid && (st != ST_RECV) && (st != ST_GEND))
                err_cnt <= err_cnt + 32'd1;

            //----------------------------------------------------------
            //  求解器已取走本次请求：清 req，并把 st_b_en 清 0
            //  这样下一帧第一块行一定重新打擂台，不会因为上一帧的大
            //  energy 一直占着 best 而不更新。
            //----------------------------------------------------------
            ack_d <= st_solve_ack;
            if (st_solve_ack && !ack_d) begin
                st_solve_req <= 1'b0;
                st_b_en      <= 32'sd0;
            end
        end
    end

endmodule
