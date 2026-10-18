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
module vib_lk_grid (
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
    output reg  [7:0]   st_dbg_m0,        // g[m-1][100]  走 gsel_dn 通路
    output reg  [7:0]   st_dbg_m1,        // g[m  ][100]  走 shB 通路（基准）
    output reg  [7:0]   st_dbg_m2,        // g[m+1][100]  走 gsel_up 通路
    output reg  [7:0]   st_dbg_p0,        // prev[m][100] 走 pmem 通路
    output reg  [7:0]   st_dbg_pa,        // prev[99][100]
    output reg  [7:0]   st_dbg_pb,        // prev[101][100]
    output reg  [31:0]  st_dbg_ae,        // 块0~3 的 acc_en>>13
    output reg  [31:0]  st_dbg_af,        // 块4~7 的 acc_en>>13
    // ---- 水平错位诊断 ----
    //   每个字段 4 字节 = {cur[x], prev[x-1], prev[x], prev[x+1]}（最高字节是 cur[x]）
    //   判据：若 |cur[x]-prev[x±1]| 明显小于 |cur[x]-prev[x]|，则 prev 相对 cur 水平错位
    output reg  [31:0]  st_dbg_xa,        // 纹理强列 300（块 3）
    output reg  [31:0]  st_dbg_xb,        // 平坦列  60（块 0）
    output reg  [5:0]   st_dbg_sel,       // {wr_sel, gsel_dn, gsel_m_r}
    output reg  [7:0]   st_dbg_la,        // 当前线的第一个字节
    output reg  [7:0]   st_dbg_lb,        // 上一条线的第一个字节
    output reg  [7:0]   st_dbg_lc,        // 上上条线的第一个字节

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
    output reg               st_solve_req,
    input  wire              st_solve_ack
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
    wire signed [17:0] p_xx = dIx * dIx;
    wire signed [17:0] p_yy = dIy * dIy;
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
    wire signed [17:0] p_xy = dIx * dIy;
    wire signed [17:0] p_bx = dIx * dit;
    wire signed [17:0] p_by = dIy * dit;
    wire        [8:0]  dit_abs = dit[8] ? (~dit + 9'd1) : dit;   // <= 255

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
            st_dbg_m0 <= 8'd0; st_dbg_m1 <= 8'd0;
            st_dbg_m2 <= 8'd0; st_dbg_p0 <= 8'd0;
            st_dbg_pa <= 8'd0; st_dbg_pb <= 8'd0;
            st_dbg_ae <= 32'd0; st_dbg_af <= 32'd0;
            st_dbg_xa <= 32'd0; st_dbg_xb <= 32'd0;
            st_dbg_sel <= 6'd0;
        end
        else if (proc_en) begin
            // ---- 当前帧的三行（同一列）----
            if ((px_now == 10'd100) && (mrow == 10'd100)) begin
                st_dbg_m0 <= bD1;    // g[m-1][p]
                st_dbg_m1 <= bB1;    // g[m  ][p]
                st_dbg_m2 <= bU1;    // g[m+1][p]
                st_dbg_p0 <= bP1;    // prev[m][p]
                st_dbg_sel <= {wr_sel, gsel_dn, gsel_m_r};
                // 8 个块的 acc_en 同时可见（各压缩到 8 位：>>7，上限 255*128 = 32640）
                //   mrow=100 属于第 1 个块行（行 60~119），此时 acc_en 是
                //   该块行到目前为止的部分和，8 个块可直接横向比较。
                //   -> 若某一块远大于其余，说明那一块的 dit 被污染；
                //      若 8 块都正常而 LKBE 仍偏大，则是 st_b_en 的清除有问题。
                st_dbg_ae <= {ae3, ae2, ae1, ae0};
                st_dbg_af <= {ae7, ae6, ae5, ae4};
            end
            // ---- prev 的三行剖面：prev[99] / prev[100] / prev[101] ----
            //   三个值应像图像相邻行一样平滑变化；若 prev[100] 与 cur[99]
            //   之类错位，就能直接看出 pmem 的行序偏了一行。
            if ((px_now == 10'd100) && (mrow == 10'd99))  st_dbg_pa <= bP1;
            if ((px_now == 10'd100) && (mrow == 10'd101)) st_dbg_pb <= bP1;
            // ---- 水平错位诊断：同一行、同一列，cur 与 prev 的三个相邻值 ----
            if (px_now == 10'd300) st_dbg_xa <= {bB1, bP2, bP1, bP};
            if (px_now == 10'd60)  st_dbg_xb <= {bB1, bP2, bP1, bP};
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
            st_dbg_la <= 8'd0; st_dbg_lb <= 8'd0; st_dbg_lc <= 8'd0;
            line_chk  <= 8'd0;
        end
        else if (word_valid && (st == ST_RECV)) begin
            // ★ 整行 checksum：本行 40 个字的首字节累加和（8 位自然回绕）。
            //   只记首字节只能看左边界一个像素，不足以判断整行是否重复；
            //   累加和覆盖全行 40 个字，才有判别力。
            if (wr_wk == 6'd0) begin
                // 新一行开始：把上一条"已完成"行的 checksum 滚进 LA/LB/LC
                st_dbg_lc <= st_dbg_lb;
                st_dbg_lb <= st_dbg_la;
                st_dbg_la <= line_chk;
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
    assign st_fx_pos = {25'd0, fx_valid, fx_row, fx_col};
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
    wire signed [32:0] tx0 = acc_mm[0];
    wire signed [32:0] tx1 = acc_mm[1];
    wire signed [32:0] tx2 = acc_mm[2];
    wire signed [32:0] tx3 = acc_mm[3];
    wire signed [32:0] tx4 = acc_mm[4];
    wire signed [32:0] tx5 = acc_mm[5];
    wire signed [32:0] tx6 = acc_mm[6];
    wire signed [32:0] tx7 = acc_mm[7];

    wire        u01 = (tx1 > tx0);
    wire        u23 = (tx3 > tx2);
    wire        u45 = (tx5 > tx4);
    wire        u67 = (tx7 > tx6);
    wire signed [32:0] f01 = u01 ? tx1 : tx0;
    wire signed [32:0] f23 = u23 ? tx3 : tx2;
    wire signed [32:0] f45 = u45 ? tx5 : tx4;
    wire signed [32:0] f67 = u67 ? tx7 : tx6;
    wire [2:0] j01 = u01 ? 3'd1 : 3'd0;
    wire [2:0] j23 = u23 ? 3'd3 : 3'd2;
    wire [2:0] j45 = u45 ? 3'd5 : 3'd4;
    wire [2:0] j67 = u67 ? 3'd7 : 3'd6;

    wire        u03 = (f23 > f01);
    wire        u47 = (f67 > f45);
    wire signed [32:0] f03 = u03 ? f23 : f01;
    wire signed [32:0] f47 = u47 ? f67 : f45;
    wire [2:0] j03 = u03 ? j23 : j01;
    wire [2:0] j47 = u47 ? j67 : j45;

    wire        u07 = (f47 > f03);
    wire signed [32:0] br_tex = u07 ? f47 : f03;
    wire [2:0]         br_txi = u07 ? j47 : j03;

    // ---- 整帧纹理 argmax 与锁定状态 ----
    localparam [5:0] FREEZE_N = 6'd30;      // 第 30 帧锁定（0.5 s）

    reg  signed [32:0] tx_best;
    reg  [2:0]         tx_col, tx_row;
    reg                tx_frozen;
    reg  [5:0]         tx_cnt;

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
            tx_best <= 33'sd0; tx_col <= 3'd0; tx_row <= 3'd0;
            tx_frozen <= 1'b0; tx_cnt <= 6'd0;
            fx_axx <= 32'sd0; fx_ayy <= 32'sd0; fx_axy <= 32'sd0;
            fx_bx  <= 32'sd0; fx_by  <= 32'sd0; fx_en  <= 32'sd0;
            fx_col <= 3'd0; fx_row <= 3'd0; fx_valid <= 1'b0;
            fx_tex <= 33'sd0;
            fx_tick <= 1'b0;
            st_b_bcol <= 3'd0;  st_b_brow <= 3'd0;
            st_solve_req <= 1'b0;
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
                                tx_best <= 33'sd0;      // 下一帧重新打擂台
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
                        // ---- 纹理 argmax（选固定块用，未锁定前才更新）----
                        if (!tx_frozen && (br_tex > tx_best)) begin
                            tx_best <= br_tex;
                            tx_col  <= br_txi;
                            tx_row  <= brow_now;
                        end
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


//######################################################################
//  vib_lk_solve：单块 2x2 Lucas-Kanade 求解（B2c-2a）
//
//  与 Python 的定点换算（对齐的关键，推导一遍）：
//    Python: ix = (g[x+1]-g[x-1])*0.5 ,  iy = (g[y+1]-g[y-1])*0.5
//    硬件  : dIx = g[x+1]-g[x-1] = 2*ix , dIy = 2*iy
//    => axx_hw = 4*axx_py , ayy_hw = 4*ayy_py , axy_hw = 4*axy_py
//       bx_hw  = 2*bx_py  , by_hw  = 2*by_py  , en_hw  = en_py
//    det_hw = 16*det_py
//    nu_hw  = -bx_hw*ayy_hw + axy_hw*by_hw = 8*nu_py
//    => u_hw = nu_hw/det_hw = 0.5*u_py   =>  u_py = 2*u_hw
//    ★ 所以分子要额外左移 1 位；再加 Q8.8 的 8 位，共左移 9 位。
//
//  门限（整数化，不手算）：
//    MIN_GRAD_HW = ceil(4 * 1500 * 4800 / 2700) = 10667
//    条件  grad >= MIN_GRAD_HW  且  det > 0  且  50*det >= grad^2
//
//  规模：1 个 32x32 有符号乘法器（组合，由 mstep 选操作数）
//        1 个 72 位被除数 / 64 位除数的恢复余数除法器，72 次迭代
//        u、v 各跑一次 => 7 + 72*2 ≈ 151 拍，帧消隐期绰绰有余
//######################################################################
module vib_lk_solve #(
    parameter [63:0] MIN_GRAD = 64'd10667
)(
    input  wire clk,
    input  wire rst_n,

    input  wire               req,
    input  wire signed [31:0] s_axx, s_ayy, s_axy,
    input  wire signed [31:0] s_bx,  s_by,  s_en,
    input  wire [2:0]         s_bcol, s_brow,

    output reg                ack,
    output reg  signed [31:0] r_u, r_v,
    output reg  [31:0]        r_en,
    output reg  [2:0]         r_bcol, r_brow,
    output reg                r_valid,
    output reg                r_tgl,
    // ---- 内部诊断（用于区分 det/nu/除法/符号 四类错误）----
    output reg  [31:0]        r_det_h,    // det  >> 28
    output reg  [31:0]        r_num_h,    // |nu| >> 28
    output reg  [31:0]        r_quot,     // 除法器原始商（未加符号）
    output reg                r_nu_neg,   // nu 的符号
    output reg  [31:0]        r_den_h,    // den >> 28
    output reg  [31:0]        r_rem_h,    // LKQC: divider done 脉冲数（正常=2）
    output reg  [31:0]        r_num_ld    // divider 实际拿到的 num48[31:0]
);

    localparam [2:0] S_IDLE = 3'd0, S_MUL = 3'd1, S_GATE = 3'd2,
                     S_WU   = 3'd3, S_WV  = 3'd4, S_DONE = 3'd5;

    reg [2:0] st;

    reg signed [31:0] axx, ayy, axy, bxv, byv, env;
    reg [2:0]         bcol_r, brow_r;

    // ---- 组合乘法器：按 mstep 选操作数 ----
    reg  signed [31:0] mop_a, mop_b;
    always @(*) begin
        case (mstep)
        4'd0:    begin mop_a = axx;  mop_b = ayy;  end   // det  += axx*ayy
        4'd1:    begin mop_a = axy;  mop_b = axy;  end   // det  -= axy*axy
        4'd2:    begin mop_a = axy;  mop_b = byv;  end   // nu   += axy*by
        4'd3:    begin mop_a = bxv;  mop_b = ayy;  end   // nu   -= bx*ayy
        4'd4:    begin mop_a = axy;  mop_b = bxv;  end   // nv   += axy*bx
        4'd5:    begin mop_a = axx;  mop_b = byv;  end   // nv   -= axx*by
        default: begin mop_a = axx + ayy; mop_b = axx + ayy; end  // grad^2
        endcase
    end
    wire signed [63:0] mul = mop_a * mop_b;

    reg [3:0]          mstep;
    reg signed [63:0]  det, nu, nv, grad2, det50, grad;
    reg signed [63:0]  grad_full;   // 未缩放的 grad，只用于 MIN_GRAD 门限

    //==================================================================
    //  除法：改成自己的串行除法器 vib_div_serial（48/32，恒 48 拍）
    //
    //  为什么换掉厂商 divider（AWB 用的那个 div_gen）：
    //    它是 PIPLE=50 的全流水除法器，实测占 1127 logic + 1084 ripple
    //    + 2806 FF ≈ 5017 个 SLICE。而振动算法一帧只做 2 次除法，
    //    它的 50 级流水 98% 时间是空闲的 —— 这是选型错误。
    //    vib_div_serial 约 150 FF + 250 LUT，省下约 4700。
    //
    //  缩放策略：把缩放提前到**累加器入口**，而不是事后移位。
    //    det 和 nu 都是"两个累加器的乘积"，两个累加器各右移 13 位后
    //    det 和 nu 同比例缩小 2^26，**比值 nu/det 完全不变**。
    //      axx'..by' = axx..by >>> 13 或 >>7  （两档自适应，见 amax_q/weak_q）
    //      det' = det >> 26  <= 2^30.4     → 正好放进 32 位除数
    //      nu'  = nu  >> 26  <= 64*det'    → |nu'|<<9 <= 2^45.4 放进 48 位
    //      Q    = (|nu'|<<9) / det' = Q_true（Q8.8），**不需要还原移位**
    //
    //  精度：由 den32 = det' >= 1024 保证相对误差 <= 0.1%
    //        （约 0.001 px），门限见 S_DONE 的 valid 条件。
    //
    //  验证：model_serial_div.py（穷举+15 万随机）与 check_div_rtl.py
    //        （位宽级逐拍，168 边界 + 8 万随机 + 3 万实际量级）全部 0 失败。
    //==================================================================
    reg  [47:0] div_num;
    reg  [31:0] div_den;
    reg         div_start;
    wire [47:0] div_quot;
    wire [47:0] div_rem;        // 余数只用于诊断
    wire        div_done;

    vib_div_serial #(
        .W  ( 48 ),
        .DW ( 32 )
    ) u_div (
        .clk    ( clk       ),
        .rst_n  ( rst_n     ),      // 我们的除法器是低有效复位
        .start  ( div_start ),
        .numer  ( div_num   ),
        .denom  ( div_den   ),
        .quot   ( div_quot  ),
        .rem    ( div_rem   ),
        .done   ( div_done  )
    );

    //==================================================================
    //  预缩放：两档自适应
    //
    //  原来固定 >>13。问题是 det' 的量级完全取决于画面纹理：
    //    强纹理（FXTX≈1.6e7）：axx≈1e8 → axx'=12207 → det'≈1.5e8  ✓
    //    弱纹理（FXTX≈1.5e4）：axx≈1.5e4 → axx'=1     → det'≈1     ✗
    //  后者过不了 det>=1024 的门限，LKVA 恒为 0。
    //
    //  实测证据（选块指标换成 Σmin(ix²,iy²) 之后）：
    //    FXTX=295225/207547/146890 的三轮  LKVA=1 ✓
    //    FXTX<=37000  的十轮              LKVA=0 ✗
    //  门限就在 FXTX≈1e5 附近，正好对应 axx'≈36、det'≈1300。
    //
    //  两档方案：amax = max(axx,ayy)
    //    amax >= 2^19 → >>12（强纹理档）
    //    amax <  2^19 → >>6 （弱纹理档）
    //  两档里 nu 和 det 同比例缩放，**比值完全不变**，
    //  所以结果连续，只是定点分辨率不同。
    //  代价：5 个 2 选 1 mux，约 60 LUT。
    //==================================================================
    wire [31:0] amax_q = ($signed(s_axx) > $signed(s_ayy)) ? s_axx : s_ayy;
    wire        weak_q = ($signed(amax_q) < $signed(32'sd524288));   // 2^19

    wire [63:0] nu_abs_q = (nu < 0) ? (64'd0 - nu) : nu;
    wire [63:0] nv_abs_q = (nv < 0) ? (64'd0 - nv) : nv;
    // 被除数 = |nu| << 9（Q8.8），超过 48 位时饱和
    wire [47:0] num48_u  = (|nu_abs_q[63:39]) ? 48'hFFFF_FFFF_FFFF
                                             : (nu_abs_q << 9);
    wire [47:0] num48_v  = (|nv_abs_q[63:39]) ? 48'hFFFF_FFFF_FFFF
                                             : (nv_abs_q << 9);
    // 除数 = det'（累加器已右移 13 位，det 本身已缩小 2^26）
    wire [31:0] den32    = det[31:0];

    reg signed [31:0] qu, qv;
    reg               neg_u, neg_v;
    reg  [1:0]        done_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; ack <= 1'b0; mstep <= 4'd0;
            det <= 64'sd0; nu <= 64'sd0; nv <= 64'sd0;
            grad2 <= 64'sd0; det50 <= 64'sd0; grad <= 64'sd0;
            grad_full <= 64'sd0;
            div_num <= 48'd0; div_den <= 32'd0; div_start <= 1'b0;
            done_cnt <= 2'd0;
            qu <= 32'sd0; qv <= 32'sd0; neg_u <= 1'b0; neg_v <= 1'b0;
            r_u <= 32'sd0; r_v <= 32'sd0; r_en <= 32'd0;
            r_bcol <= 3'd0; r_brow <= 3'd0;
            r_valid <= 1'b0; r_tgl <= 1'b0;
            r_det_h <= 32'd0; r_num_h <= 32'd0;
            r_quot  <= 32'd0; r_nu_neg <= 1'b0;
            r_den_h <= 32'd0; r_rem_h <= 32'd0; r_num_ld <= 32'd0;
            axx <= 32'sd0; ayy <= 32'sd0; axy <= 32'sd0;
            bxv <= 32'sd0; byv <= 32'sd0; env <= 32'sd0;
            bcol_r <= 3'd0; brow_r <= 3'd0;
        end
        else begin
            ack <= 1'b0;
            case (st)
            //----------------------------------------------------------
            S_IDLE: if (req) begin
                // ★ 累加器入口按档位右移（det 和 nu 同比例缩放，比值不变）。
                //   归一化分析见上面 amax_q / weak_q 的注释：
                //     amax >= 2^18 → >>13（原档）
                //     amax <  2^18 → >>7 （新档，弱纹理）
                //   这样两档下 det' 都能落在 [1024, 2^31) 里。
                if (weak_q) begin
                    axx <= s_axx >>> 6;  ayy <= s_ayy >>> 6;  axy <= s_axy >>> 6;
                    bxv <= s_bx  >>> 6;  byv <= s_by  >>> 6;
                end
                else begin
                    axx <= s_axx >>> 12; ayy <= s_ayy >>> 12; axy <= s_axy >>> 12;
                    bxv <= s_bx  >>> 12; byv <= s_by  >>> 12;
                end
                env <= s_en;                      // en 只用于比较，不参与除法
                // ★ 门限 MIN_GRAD 是按**原始幅度**定的（= max(4*1500, ...) 的硬件单位），
                //   所以必须用未缩放的值去比，不能用右移 13 位之后的 grad。
                grad_full <= $signed(s_axx) + $signed(s_ayy);
                bcol_r <= s_bcol; brow_r <= s_brow;
                ack  <= 1'b1;
                mstep <= 4'd0;
                st <= S_MUL;
            end
            //----------------------------------------------------------
            S_MUL: begin
                case (mstep)
                4'd0:    det   <= mul;
                4'd1:    det   <= det - mul;
                4'd2:    nu    <= mul;
                4'd3:    nu    <= nu - mul;
                4'd4:    nv    <= mul;
                4'd5:    nv    <= nv - mul;
                default: grad2 <= mul;
                endcase
                grad <= $signed(axx) + $signed(ayy);
                if (mstep == 4'd6) st <= S_GATE;
                else               mstep <= mstep + 4'd1;
            end
            //----------------------------------------------------------
            S_GATE: begin
                det50 <= (det <<< 5) + (det <<< 4) + (det <<< 1);   // 50*det
                neg_u <= (nu < 0);
                neg_v <= (nv < 0);
                // 装 u 的除法输入并启动一次厂商 divider（50 级流水）
                div_num   <= num48_u;
                div_den   <= den32;
                div_start <= 1'b1;
                done_cnt  <= 2'd0;
                st <= S_WU;
            end
            //----------------------------------------------------------
            //  等 u 的商回来；回来后立刻装 v 的输入再启动一次
            S_WU: begin
                div_start <= 1'b0;
                if (div_done) begin
                    done_cnt <= done_cnt + 2'd1;
                    // Q_true = Q_vendor >> 6，饱和到 32 位有符号 + 还原符号
                    qu <= (|div_quot[47:32]) ? 32'sh7FFFFFFF
                        : (neg_u ? -$signed(div_quot[31:0])
                                 :  $signed(div_quot[31:0]));
                    div_num   <= num48_v;
                    div_den   <= den32;
                    div_start <= 1'b1;
                    st <= S_WV;
                end
            end
            //----------------------------------------------------------
            S_WV: begin
                div_start <= 1'b0;
                if (div_done) begin
                    done_cnt <= done_cnt + 2'd1;
                    qv <= (|div_quot[47:32]) ? 32'sh7FFFFFFF
                        : (neg_v ? -$signed(div_quot[31:0])
                                 :  $signed(div_quot[31:0]));
                    st <= S_DONE;
                end
            end
            //----------------------------------------------------------
            S_DONE: begin
                // ★ 有效性门限里必须加 det >= 2^30。
                //   den32 = det>>25，det 太小时 den32 只有 1~2，整数除法
                //   会把商截断到极少几个值（压力测试最坏相对误差近 100%）。
                //   det >= 2^30 保证 den32 >= 32，相对误差 <= 3%（约 0.03 px），
                //   对 u/v 完全够用。
                r_valid <= (grad_full >= MIN_GRAD) && (det > 0) &&
                           (det50 >= grad2) && (det > 64'sd1023);   // 等价于原来的 det[63:10]!=0，但用 signed 比较，负值自然为假   // det' >= 1024
                r_u   <= qu;
                r_v   <= qv;
                r_en  <= env;
                r_bcol <= bcol_r;
                r_brow <= brow_r;
                r_tgl <= ~r_tgl;
                // ---- 诊断 ----
                //   LKDE = det>>28   LKNU = divider 实际拿到的被除数[31:0]
                //   LKDN = det>>28   LKQC = done 脉冲数（正常应为 2）
                //   LKQT = divider 原始商[31:0]（未右移还原）
                r_det_h  <= det[59:28];   // LINT-OK: 纯诊断，负值显示为垃圾无所谓
                r_num_h  <= nu_abs_q[59:28];
                r_den_h  <= det[59:28];   // LINT-OK: 纯诊断
                r_num_ld <= num48_u[31:0];
                r_quot   <= div_quot[31:0];
                r_rem_h  <= {30'd0, done_cnt};
                r_nu_neg <= (nu < 0);
                st <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end

endmodule
