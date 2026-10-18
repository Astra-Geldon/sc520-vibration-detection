//=====================================================================
//  vib_ddr_arb.v  ——  512Mbit DDR 三路仲裁器
//
//  背景（一定要先看这段）：
//    官方工程里 video_in（写）和 video_out（读）是这样共享 DDR 的：
//      * 双方各自维护一个 busy 标志（O_video_in_wr_busy / O_video_out_rd_busy）
//      * video_in  只在 !video_out_rd_busy 时才发起 240 拍的写突发
//      * video_out 只在 !video_in_wr_busy  时才发起 240 拍的读突发
//      * 两者都通过 mc_to_user_interface（一个 155bit x 512 的命令 FIFO）排队
//    也就是说：**同一时刻只有一个客户端在读写**，靠 busy 标志互斥。
//
//  问题在于"读回数据没有 tag"：
//    mc_to_user_interface 的 O_ddr_user_rd_valid / O_ddr_user_rd_data 是
//    **共享且无标识**的——DDR 回来的数据不告诉你是谁的。
//    官方设计之所以没问题，是因为只有 video_out 一个读者。
//    一旦加上算法通路也去读 DDR，就会分不清数据归谁。
//
//  本模块的解决办法：
//    1) 用 I_vib_want / O_vib_own 把"算法占用 DDR"做成第三份 busy 标志，
//       参与同一套互斥（vi/vo 也会看到 O_vib_own，见 video_in/video_out 的
//       I_vib_ddr_busy 新增端口）。
//    2) 读命令按发出顺序压入一个 1bit x 512 的 **tag FIFO**，读回数据按 tag
//       路由给对应客户端。因为官方设计本来就假设"读回顺序 = 读命令顺序"
//       （video_out 靠 240 拍计数配平），所以 tag FIFO 是安全的。
//    3) ready 信号按 own 分开门控，保证同一拍只会有一个客户端的命令被入队，
//       即使 busy 标志在边界拍上有一拍竞争也不会串数据。
//
//  地址单位：1 个单位 = 2 字节；一个 128bit 拍 = 16 字节 = 8 个单位。
//            （见 video_in.v:199 的 addr + 'd8，以及 25bit 地址 x 2B = 64MB）
//=====================================================================
module vib_ddr_arb #(
    parameter integer TAG_AW   = 9,     // tag FIFO 深度 = 2^9 = 512
    parameter integer OWN_MAX  = 64,    // 连续占用上限（拍）
    parameter integer COOL_MAX = 192    // 释放后强制冷却（拍）
)(
    input  wire         clk,
    input  wire         rst_n,

    //---------------- DDR 控制器侧（接 mc_to_user_interface）----------------
    output wire         O_ddr_wr_en,
    output wire         O_ddr_rd_en,
    output wire [24:0]  O_ddr_addr,
    output wire [127:0] O_ddr_wr_data,
    input  wire         I_ddr_ready,      // = O_ddr_user_ready
    input  wire         I_ddr_rd_valid,   // = O_ddr_user_rd_valid
    input  wire [127:0] I_ddr_rd_data,    // = O_ddr_user_rd_data

    //---------------- video_in 客户端（只写）----------------
    input  wire         I_vi_wr_en,
    input  wire [24:0]  I_vi_addr,
    input  wire [127:0] I_vi_wr_data,
    output wire         O_vi_ready,       // 接 video_in.I_ddr_user_ready
    input  wire         I_vi_busy,        // = video_in.O_video_in_wr_busy

    //---------------- video_out 客户端（只读）----------------
    input  wire         I_vo_rd_en,
    input  wire [24:0]  I_vo_addr,
    output wire         O_vo_ready,       // 接 video_out.I_ddr_user_ready
    input  wire         I_vo_busy,        // = video_out.O_video_out_rd_busy
    output wire         O_vo_rd_valid,    // 接 video_out.I_ddr_user_rd_valid
    output wire [127:0] O_vo_rd_data,

    //---------------- 算法通路客户端（读 + 写）----------------
    input  wire         I_vib_wr_en,
    input  wire         I_vib_rd_en,
    input  wire [24:0]  I_vib_addr,
    input  wire [127:0] I_vib_wr_data,
    output wire         O_vib_ready,      // 接算法模块的 I_ready
    output wire         O_vib_rd_valid,
    output wire [127:0] O_vib_rd_data,
    input  wire         I_vib_want,       // 算法请求占用（整个传输期间保持高）
    output wire         O_vib_own         // 已占用 -> 给 video_in/video_out 的 I_vib_ddr_busy
);

    //------------------------------------------------------------------
    // 授权：算法通路优先级最低，只在 video_in / video_out 都空闲时抢占。
    //
    // ★ 为什么要限制连续占用（OWN_MAX）并强制冷却（COOL_MAX）：
    //   如果算法一次占用 DDR 几千拍不放，video_in 的 512 深 FIFO 会被摄像头
    //   灌满溢出（摄像头只管按 4 像素/拍 往外吐，不会等），显示帧就花了。
    //   所以这里把算法的占用率硬性限制在 OWN_MAX/(OWN_MAX+COOL_MAX)
    //   = 64/256 = 25% 以内。视频通路实际只需要 DDR 的 ~16% 带宽，
    //   算法上一帧缓存只需要 ~4%，两边都够，而且互相不会饿死。
    //
    //   注意：释放期间算法可能有"已发出但还没回来的读"，这不会有问题——
    //   读回数据是按 tag FIFO 路由的，与当前 own 状态无关（见下）。
    //------------------------------------------------------------------
    reg  [15:0] own_cnt;
    reg  [15:0] cool_cnt;

    wire own_timeout = (own_cnt  >= OWN_MAX);
    wire cool_done   = (cool_cnt >= COOL_MAX);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)           own_cnt <= 16'd0;
        else if (vib_own)     own_cnt <= own_timeout ? own_cnt : (own_cnt + 16'd1);
        else                  own_cnt <= 16'd0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)           cool_cnt <= 16'd0;
        else if (vib_own)     cool_cnt <= 16'd0;
        else if (!cool_done)  cool_cnt <= cool_cnt + 16'd1;
    end

    reg vib_own;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            vib_own <= 1'b0;
        else if (vib_own)
            vib_own <= I_vib_want & ~own_timeout;        // 传输结束或超时则释放
        else
            vib_own <= I_vib_want & cool_done & ~I_vi_busy & ~I_vo_busy;
    end

    assign O_vib_own = vib_own;

    //------------------------------------------------------------------
    // ready 分开门控：同一拍只会有一个客户端的命令被入队
    //------------------------------------------------------------------
    assign O_vi_ready  = I_ddr_ready & ~vib_own;
    assign O_vo_ready  = I_ddr_ready & ~vib_own;
    assign O_vib_ready = I_ddr_ready &  vib_own;

    //------------------------------------------------------------------
    // 命令总线三选一
    //------------------------------------------------------------------
    assign O_ddr_wr_en   = vib_own ? I_vib_wr_en   : I_vi_wr_en;
    assign O_ddr_rd_en   = vib_own ? I_vib_rd_en   : I_vo_rd_en;
    assign O_ddr_addr    = vib_own ? I_vib_addr
                                   : (I_vi_wr_en ? I_vi_addr : I_vo_addr);
    assign O_ddr_wr_data = vib_own ? I_vib_wr_data : I_vi_wr_data;

    //------------------------------------------------------------------
    // 读回 tag FIFO：记下每个读命令是谁发的，按顺序把读回数据路由回去
    //------------------------------------------------------------------
    reg  [TAG_AW-1:0] tag_wp;
    reg  [TAG_AW-1:0] tag_rp;
    reg               tag_mem [0:(1<<TAG_AW)-1];

    wire tag_empty  = (tag_wp == tag_rp);
    wire tag_owner  = tag_empty ? 1'b0 : tag_mem[tag_rp];

    always @(posedge clk) begin
        if (O_ddr_rd_en)
            tag_mem[tag_wp] <= vib_own;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          tag_wp <= {TAG_AW{1'b0}};
        else if (O_ddr_rd_en) tag_wp <= tag_wp + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                            tag_rp <= {TAG_AW{1'b0}};
        else if (I_ddr_rd_valid && !tag_empty) tag_rp <= tag_rp + 1'b1;
    end

    assign O_vo_rd_valid  = I_ddr_rd_valid & ~tag_owner;
    assign O_vo_rd_data   = I_ddr_rd_data;

    assign O_vib_rd_valid = I_ddr_rd_valid &  tag_owner;
    assign O_vib_rd_data  = I_ddr_rd_data;

endmodule
