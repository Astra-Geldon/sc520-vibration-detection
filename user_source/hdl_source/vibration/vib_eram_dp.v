//=============================================================================
//  vib_eram_dp.v  ——  真双口 ERAM 的可复用包装
//
//  为什么需要它：
//    安路 TD 对"普通 reg 数组"的 RAM 推断不可靠（实测 vib_gz_store 的
//    816x32 阵列被推成了 1024 个分布式 RAM slice，一点 ERAM 都没用上）。
//    而 blk_mem_gen_awb_delay_signal 的原语层用的是 PH1P_LOGIC_ERAM，
//    可以直接例化 —— 这样存储必然进 20Kbit 的块 RAM，不占 slice。
//
//  原语参考：user_source/ip_source/blk_mem_gen_awb_delay_signal/
//              ram_f84573da5ab5.v
//
//  ★ 不要登记进 .al，由顶层用 `include 拉入
//=============================================================================
`ifndef VIB_ERAM_DP_V
`define VIB_ERAM_DP_V

module vib_eram_dp #(
    parameter W_A  = 64,          // 端口 A 数据宽度
    parameter AW_A = 10,          // 端口 A 地址宽度
    parameter D_A  = 816,         // 端口 A 深度
    parameter W_B  = 64,          // 端口 B 数据宽度
    parameter AW_B = 10,
    parameter D_B  = 816,
    parameter REGMODE_A = "NOREG",     // "NOREG" = 输出不额外打拍
    parameter REGMODE_B = "NOREG"
)(
    input  wire            clk,
    input  wire            rst_n,

    // ---- 端口 A ----
    input  wire [W_A-1:0]  dia,
    input  wire [AW_A-1:0] addra,
    input  wire            wea,
    output wire [W_A-1:0]  doa,

    // ---- 端口 B ----
    input  wire [W_B-1:0]  dib,
    input  wire [AW_B-1:0] addrb,
    input  wire            web,
    output wire [W_B-1:0]  dob
);

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A (W_A      ),
        .DATA_WIDTH_B (W_B      ),
        .ADDR_WIDTH_A (AW_A     ),
        .ADDR_WIDTH_B (AW_B     ),
        .DATA_DEPTH_A (D_A      ),
        .DATA_DEPTH_B (D_B      ),
        .MODE         ("DP"     ),
        .REGMODE_A    (REGMODE_A),
        .REGMODE_B    (REGMODE_B),
        .WRITEMODE_A  ("NORMAL" ),
        .WRITEMODE_B  ("NORMAL" ),
        .IMPLEMENT    ("20K(FAST)"),
        .ECC_ENCODE   ("DISABLE"),
        .ECC_DECODE   ("DISABLE"),
        .CLKMODE      ("ASYNC"  ),
        .SSROVERCE    ("DISABLE"),
        .OREGSET_A    ("RESET"  ),
        .OREGSET_B    ("RESET"  ),
        .RESETMODE_A  ("ASYNC"  ),
        .RESETMODE_B  ("ASYNC"  ),
        .ASYNC_RESET_RELEASE_A ("ASYNC"),
        .ASYNC_RESET_RELEASE_B ("ASYNC"),
        .INIT_FILE    ("NONE"   ),
        .FILL_ALL     ("NONE"   )
    ) u_eram (
        .dia   (dia   ),
        .dib   (dib   ),
        .addra (addra ),
        .addrb (addrb ),
        .cea   (1'b1  ),
        .ceb   (1'b1  ),
        .ocea  (1'b0  ),
        .oceb  (1'b0  ),
        .clka  (clk   ),
        .clkb  (clk   ),
        .wea   (wea   ),
        .web   (web   ),
        .bea   (1'b0  ),
        .beb   (1'b0  ),
        .rsta  (~rst_n),
        .rstb  (~rst_n),
        .doa   (doa   ),
        .ecc_sbiterr  (),
        .ecc_dbiterr  (),
        .ecc_sbiterrinj (1'b0),
        .ecc_dbiterrinj (1'b0),
        .dob   (dob   )
    );

endmodule

`endif // VIB_ERAM_DP_V
