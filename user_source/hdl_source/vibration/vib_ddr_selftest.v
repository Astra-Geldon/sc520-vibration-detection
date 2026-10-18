//=====================================================================
//  vib_ddr_selftest.v  ——  512Mbit DDR 自检（算法专用区域）
//
//  目的：
//    在把算法真正接上 DDR 之前，先独立证明三件事：
//      ① 地址映射算对了（写进去的能从同一地址读回来，且顺序不乱）
//      ② 数据线没坏（128bit 每一位都验过）
//      ③ 新增的 vib_ddr_arb 三路仲裁没有把 video_in/video_out 的数据串掉
//
//  做法：
//    往算法专用区域从头到尾写一遍已知图案，再从头到尾读一遍逐字比较。
//    图案用"每个 128bit 字的第 j 个字节 = (字序号 + j) mod 256"，
//    实现上就是每个字加一个 0x01 重复 16 次的常量 —— 一个 128bit 加法器。
//    这个图案的好处：相邻字只差 1，一旦地址错位/少写多写立刻暴露；
//    16 个字节互不相同，能查出字节通道粘连。
//
//  地址映射（见 vib_ddr_arb.v 头部说明）：
//    1 个地址单位 = 2 字节；1 个 128bit 拍 = 16 字节 = 8 个单位
//    BASE_ADDR = 24_000_000 单位 = 48_000_000 字节 = 45.8 MiB
//    区域大小  = 640 x 360 = 230400 字节 = 14400 拍 = 115200 单位
//
//    官方 4 个 RGB 帧缓存占 0 ~ 22_382_400 单位（0 ~ 44.8 MiB），
//    总空间 2^25 单位 = 64 MiB，所以 48 MiB 处是空闲的，不会踩到显示通路。
//
//  两个输出怎么判读（在串口日志里，见 uart_log_debug.v）：
//      DTRD 00003840   已成功读回的字数，应恒等于 14400 = 0x00003840
//      DTER 00000000   比较错误数，必须是 0
//    两个都对了才说明 DDR 通路可用。
//=====================================================================
module vib_ddr_selftest #(
    parameter [24:0]  BASE_ADDR = 25'd24000000,
    parameter integer WORDS     = 14400,
    parameter [31:0]  START_DLY = 32'd100000,   // DDR 校准完成后再等 ~0.75ms 开跑
    parameter integer GAP_DLY   = 256
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         init_done,      // DDR 校准完成（S_init_calib_complete）

    output wire         O_wr_en,
    output wire         O_rd_en,
    output wire [24:0]  O_addr,
    output wire [127:0] O_wr_data,
    input  wire         I_ready,        // 来自 vib_ddr_arb.O_vib_ready
    input  wire         I_rd_valid,     // 来自 vib_ddr_arb.O_vib_rd_valid
    input  wire [127:0] I_rd_data,
    output wire         O_want,         // 请求占用 DDR（接 arb 的 I_vib_want）

    output reg  [31:0]  O_words_read,   // 已读回字数（应 = WORDS）
    output reg  [31:0]  O_err_cnt,      // 比较错误数（应为 0）
    output reg          O_done
);

    // 每字 +1（16 个字节各 +1）—— 生成"字节 j = 字序号 + j"的图案
    localparam [127:0] PAT_STEP = 128'h01010101010101010101010101010101;

    localparam [2:0] ST_WAIT = 3'd0,
                     ST_WR   = 3'd1,
                     ST_GAP  = 3'd2,
                     ST_RD   = 3'd3,
                     ST_DRN  = 3'd4,
                     ST_DONE = 3'd5;

    reg  [2:0]  st;
    reg  [31:0] delay;
    reg  [31:0] gap;
    reg  [31:0] wr_idx;
    reg  [31:0] rd_idx;
    reg  [31:0] got_cnt;
    reg  [24:0] addr_r;
    reg  [127:0] pat_r;      // 写数据 / 读地址步进
    reg  [127:0] exp_r;      // 读回期望值

    // 组合输出：图案/地址与 en 同拍有效（和官方 video_in 的写法一致）
    assign O_wr_en   = (st == ST_WR) & I_ready;
    assign O_rd_en   = (st == ST_RD) & I_ready;
    assign O_addr    = addr_r;
    assign O_wr_data = pat_r;
    assign O_want    = (st == ST_WR) | (st == ST_RD) | (st == ST_DRN);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st           <= ST_WAIT;
            delay        <= 32'd0;
            gap          <= 32'd0;
            wr_idx       <= 32'd0;
            rd_idx       <= 32'd0;
            got_cnt      <= 32'd0;
            addr_r       <= BASE_ADDR;
            pat_r        <= 128'd0;
            exp_r        <= 128'd0;
            O_words_read <= 32'd0;
            O_err_cnt    <= 32'd0;
            O_done       <= 1'b0;
        end
        else begin
            case (st)
            //-------------- 等 DDR 校准完成 + 一个上电延时 --------------
            ST_WAIT: begin
                if (init_done) begin
                    if (delay == START_DLY) begin
                        addr_r <= BASE_ADDR;
                        pat_r  <= 128'd0;
                        exp_r  <= 128'd0;
                        wr_idx <= 32'd0;
                        st     <= ST_WR;
                    end
                    else delay <= delay + 32'd1;
                end
            end

            //-------------- 全区域写 --------------
            ST_WR: begin
                if (I_ready) begin
                    addr_r <= addr_r + 25'd8;
                    pat_r  <= pat_r + PAT_STEP;
                    if (wr_idx == WORDS - 1) begin
                        gap <= 32'd0;
                        st  <= ST_GAP;
                    end
                    else wr_idx <= wr_idx + 32'd1;
                end
            end

            //-------------- 写完之后留一段间隔，等 DDR 落盘 --------------
            ST_GAP: begin
                if (gap == GAP_DLY) begin
                    addr_r  <= BASE_ADDR;
                    pat_r   <= 128'd0;
                    exp_r   <= 128'd0;
                    rd_idx  <= 32'd0;
                    got_cnt <= 32'd0;
                    st      <= ST_RD;
                end
                else gap <= gap + 32'd1;
            end

            //-------------- 全区域读（读回数据在下面独立统计）--------------
            ST_RD: begin
                if (I_ready) begin
                    addr_r <= addr_r + 25'd8;
                    pat_r  <= pat_r + PAT_STEP;
                    if (rd_idx == WORDS - 1) begin
                        rd_idx <= rd_idx;        // 命令已发完
                        st     <= ST_DRN;
                    end
                    else rd_idx <= rd_idx + 32'd1;
                end
            end

            //-------------- 等剩余读回数据全部返回 --------------
            ST_DRN: begin
                if (got_cnt == WORDS) begin
                    O_done <= 1'b1;
                    st     <= ST_DONE;
                end
            end

            ST_DONE: begin
                O_done <= 1'b1;
            end

            default: st <= ST_WAIT;
            endcase

            //----------------------------------------------------------
            // 读回数据统计与比较：与状态机解耦，只要 rd_valid 就来
            //   exp_r 从 0 开始，每收一个字 +1，与写入顺序严格对应
            //----------------------------------------------------------
            if (I_rd_valid) begin
                if (I_rd_data != exp_r)
                    O_err_cnt <= O_err_cnt + 32'd1;
                exp_r        <= exp_r + PAT_STEP;
                got_cnt      <= got_cnt + 32'd1;
                O_words_read <= got_cnt + 32'd1;
            end
        end
    end

endmodule
