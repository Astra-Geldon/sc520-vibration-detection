//=============================================================================
//  vib_gz_store.v  ——  48x17 Goertzel 状态存储 + 上电自检
//
//  阶段 0 的唯一目的：**证明 48x17 = 26,112 bit 的阵列能被综合成 RAM**
//  而不是 816 个触发器。48 块全屏方案完全取决于这一点：
//    52,224 bit 做成触发器 → 需要 52,224 个 FF，而全片只有 42,432 → 不可能
//
//  ★★ 这个 BIST 自己踩过的坑，写在这里避免重犯 ★★
//    (1) 第一版测试数据用 gx1[i] = i —— 是地址的纯函数，综合器直接把数据
//        推算出来，数组被完全优化掉（eram=0、dram lut 只有 384，而两个
//        816x32 数组至少要 1,600 个 LUT）。自检因此毫无意义。
//        改为 LFSR：有状态、不可折叠。
//    (2) LFSR 若用固定种子，仍可能被预计算。改为**运行时种子**
//        （来自自由运行的计数器），结构上不可能折叠。
//    (3) 只检查"写和 + 读和 = 0"太弱：地址重复或漏读可能相互抵消。
//        改为**位置敏感的旋转-XOR 校验**：写流算一份、读流算一份，比对。
//        旋转让校验对地址和顺序都敏感。
//
//  ★ 数组**没有异步复位**（有复位循环就推不成 RAM）。
//  ★ 读写都走时钟沿（同步），组合读会阻止 RAM 推断。
//=============================================================================
`ifndef VIB_GZ_STORE_V
`define VIB_GZ_STORE_V

module vib_gz_store #(
    parameter NB   = 48,        // 块数 8x6
    parameter NBIN = 17         // 频点数
)(
    input  wire        clk,
    input  wire        rst_n,
    output reg  [31:0] o_wcrc,  // 写流的旋转-XOR 校验
    output reg  [31:0] o_rcrc,  // 读流的旋转-XOR 校验（必须等于 o_wcrc）
    output reg         o_match, // o_wcrc == o_rcrc
    output reg         o_busy,
    output reg         o_done
);

    localparam [10:0] NA = NB * NBIN;          // 816

    // ---- 存储本体（无异步复位）------------------------------------------
    reg [31:0] gx1 [0:NA-1];
    reg [31:0] gx2 [0:NA-1];

    reg [10:0] addr;
    reg        we;
    reg [31:0] wd1, wd2;
    reg [31:0] rd1_q, rd2_q;

    // 同步写 / 同步读（都必须走时钟沿）
    always @(posedge clk) begin
        if (we) begin
            gx1[addr] <= wd1;
            gx2[addr] <= wd2;
        end
    end

    always @(posedge clk) begin
        rd1_q <= gx1[addr];
        rd2_q <= gx2[addr];
    end

    // ---- 运行时种子：自由运行的计数器 ------------------------------------
    //   把它混进 LFSR 初值，测试序列每次上电都不同 → 综合器无法预计算
    reg [31:0] free_cnt;
    always @(posedge clk) free_cnt <= free_cnt + 32'd1;

    // ---- LFSR（Galois，x^32 + x^22 + x^2 + 1）-----------------------------
    reg  [31:0] lfsr;
    reg  [31:0] seed;          // ★ 在写阶段开始时锁存的种子（读写必须同一个）
    reg  [31:0] seed_d;        // seed 打一拍，供写阶段第一拍使用
    wire [31:0] lfsr_nx = {lfsr[30:0],
                           lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};

    // ---- 旋转-XOR 校验 ---------------------------------------------------
    //   每拍：先把累加器循环左移 1 位，再异或 (data, data^addr)
    //   旋转使校验对"位置/顺序"敏感，异或 addr 使它对"地址错"敏感
    reg [31:0] wcrc, rcrc;
    wire [31:0] wmix = wd1 ^ wd2 ^ {21'd0, addr};
    wire [31:0] rmix = rd1_q ^ rd2_q ^ {21'd0, addr_d};
    reg  [10:0] addr_d;

    always @(posedge clk) addr_d <= addr;

    reg [1:0] st;
    localparam [1:0] S_WR = 2'd0, S_RD = 2'd1, S_DRAIN = 2'd2, S_FIN = 2'd3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr   <= 11'd0;
            lfsr   <= 32'h1;
            seed   <= 32'h1;
            seed_d <= 32'h1;
            we     <= 1'b0;
            wd1    <= 32'd0;
            wd2    <= 32'd0;
            wcrc   <= 32'd0;
            rcrc   <= 32'd0;
            o_wcrc   <= 32'd0;
            o_rcrc   <= 32'd0;
            o_match  <= 1'b0;
            o_busy   <= 1'b1;
            o_done   <= 1'b0;
            st       <= S_WR;
        end
        else begin
            case (st)
            //--------------------------------------------------------------
            //  写整表：816 拍；种子在此刻才混进 LFSR
            S_WR: begin
                we    <= 1'b1;
                // ★ free_cnt 是自由运行的，读阶段早就变了 —— 必须在
                //   addr==0 这一拍把它锁存成 seed，读写两阶段都用 seed。
                //   seed_d 是 seed 打一拍，供下一拍（addr==1）使用。
                seed   <= (addr == 11'd0) ? (32'h0001_0001 ^ free_cnt) : seed;
                seed_d <= seed;
                lfsr   <= (addr == 11'd0) ? seed_d : lfsr_nx;
                wd1    <= (addr == 11'd0) ? seed_d : lfsr;
                wd2    <= ~((addr == 11'd0) ? seed_d : lfsr);
                wcrc   <= {wcrc[30:0], wcrc[31]} ^ wmix;
                if (addr == NA - 1) begin
                    addr <= 11'd0;
                    st   <= S_RD;
                end
                else begin
                    addr <= addr + 11'd1;
                end
            end
            //--------------------------------------------------------------
            //  读整表：读数据晚一拍到，所以用 addr_d 与 rd1_q/rd2_q 对齐
            S_RD: begin
                we   <= 1'b0;
                // addr > 0 时，rd1_q/rd2_q 对应 addr-1
                if (addr > 11'd0 && addr < NA) begin
                    rcrc <= {rcrc[30:0], rcrc[31]} ^ rmix;
                end
                // 读阶段同步推进 LFSR，只为让期望序列与写阶段一致
                lfsr <= (addr == 11'd0) ? seed_d : lfsr_nx;   // 与写阶段一致：都用 seed_d
                if (addr >= NA) begin
                    st <= S_DRAIN;
                end
                else begin
                    addr <= addr + 11'd1;
                end
            end
            //--------------------------------------------------------------
            //  补最后一拍：此时 addr_d = NA-1，rd1_q/rd2_q 是 gx[NA-1]
            S_DRAIN: begin
                rcrc <= {rcrc[30:0], rcrc[31]} ^ rmix;
                st   <= S_FIN;
            end
            //--------------------------------------------------------------
            S_FIN: begin
                o_wcrc  <= wcrc;
                o_rcrc  <= rcrc;
                o_match <= (wcrc == rcrc);
                o_busy  <= 1'b0;
                o_done  <= 1'b1;
            end
            default: st <= S_FIN;
            endcase
        end
    end

endmodule

`endif
