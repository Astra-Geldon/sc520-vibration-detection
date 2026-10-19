#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Regenerate uart_log_debug.v with 18 status fields (adds clock / pixel-rate /
DDR-self-test measurements).  Tables are generated so lengths and indices
cannot be miscounted by hand."""
import io
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
     'user_source', 'hdl_source', 'uart_log_debug.v')

BANNER = "SC520 MIPI-HDMI UART LOG 115200 8N1\r\n"

# (label, value expression, comment, port declaration or None if internal)
FIELDS = [
    ("SEC ", "run_sec",             "运行秒数（每轮 +1）", None),
    # ("DIV ", "DIV",                 "波特率分频值 = 50MHz/115200 = 434 = 0x1B2", None),
    # ("PLL ", "{31'd0, pll_s[1]}",   "PLL 锁定", None),
    # ("DDR ", "{31'd0, ddr_s[1]}",   "DDR 初始化校准完成", None),
    # ("CAM ", "{31'd0, cam_s[1]}",   "摄像头寄存器配置完成（粘滞标志）", None),
    # ("I2C ", "{31'd0, i2c_s[1]}",   "摄像头 I2C 错误（1 = 有错）", None),
    # ("SID ", "{16'd0, sid_s2}",     "摄像头 Sensor ID", None),
    # ("SIOK", "{31'd0, siok_s[1]}",  "摄像头 ID 校验通过（0xEE4B / 0x9E4B）", None),
    # ("MIPI", "{28'd0, mipi_code}",  "MIPI 诊断码 0..7", None),
    # ("HS  ", "{31'd0, hs_s[1]}",    "已收到 MIPI HS 数据（粘滞标志）", None),
    # ("CSIF", "{31'd0, csif_s[1]}",  "已解析出完整 CSI 帧（粘滞标志）", None),
    # ("RAW ", "{31'd0, raw_s[1]}",   "已出现 RAW10 流水（粘滞标志）", None),
    # ("VID ", "{31'd0, vid_s[1]}",   "已读到非零视频数据（粘滞标志）", None),
    # ("CSIH", "csi_hz",              "S_csi_rx_clk 实测频率(Hz)", "input wire [31:0] csi_hz,             // 实测 S_csi_rx_clk 频率(Hz)"),
    # ("PIXS", "px_per_sec",          "ISP 有效像素率(px/s)", "input wire [31:0] px_per_sec,         // 实测像素率(px/s)"),
    # ("FPS ", "fps",                 "每秒帧数", "input wire [31:0] fps,                // 实测帧率"),
    # ("PXFR", "px_per_frame",        "每帧像素数，应 = 0x000E1000", "input wire [31:0] px_per_frame,       // 实测每帧像素数，应 = 0x000E1000"),
    # ("DTRD", "ddr_words_read",      "DDR 自检已读回字数，应 = 0x00003840", "input wire [31:0] ddr_words_read,     // DDR 自检读回字数，应 = 0x00003840"),
    # ("DTER", "ddr_err_cnt",         "DDR 自检比较错误数，必须 = 0", "input wire [31:0] ddr_err_cnt,        // DDR 自检比较错误数，必须 = 0"),
    # ("VOFP", "tap_px_per_frame",    "抽头每帧输出像素数，应 = 0x00038400", "input wire [31:0] tap_px_per_frame,   // 抽头每帧输出像素数(640x360)，应 = 0x00038400"),
    # ("VOFL", "tap_lines",           "抽头每帧输出行数，应 = 360", "input wire [31:0] tap_lines,          // 抽头每帧输出行数，应 = 360 = 0x00000168"),
    # ("VTAP", "tap_ovf",             "抽头异常计数，必须 = 0", "input wire [31:0] tap_ovf,            // 抽头异常计数（溢出/对不齐），必须 = 0"),
    # ("ITPX", "it_px",               "上一帧差分像素数，应 = 0x00038400", "input wire [31:0] it_px,              // 每帧参与 It 的像素数，应 = 0x00038400"),
    # ("ITLN", "it_lines",            "上一帧差分行数，应 = 360", "input wire [31:0] it_lines,           // 每帧处理行数，应 = 360 = 0x00000168"),
    ("VSUM", "vsum", "抽头 Σ灰度（摄像头活着的证据）", "input wire [31:0] vsum, // 抽头每帧 Σ灰度：非 0 说明抽头拿到像素了"),
#     ("ITPX", "itpx", "B2b 每帧像素数（应为 230400）", "input wire [31:0] itpx, // B2b 每帧 It 像素数，应恒为 230400"),
#     ("GPIX", "gpx", "高斯每帧输出像素数（应 230400）", "input wire [31:0] gpx, // 高斯每帧输出像素数，应恒为 230400"),
#     ("GLIN", "gln", "高斯每帧输出行数（应 360）", "input wire [31:0] gln, // 高斯每帧输出行数，应恒为 360"),
#     ("ITSM", "it_sum",              "每帧 Σ|It|：静止接近 0，一动就涨", "input wire [31:0] it_sum,             // 每帧 Σ|It|：静止场景接近 0，画面一动立刻涨"),
#     ("ITER", "it_err",              "上一帧差分异常计数，必须 = 0", "input wire [31:0] it_err,             // 上一帧差分异常计数，必须 = 0"),
    # ("ITNW", "it_line_rdy",         "每帧凑够一行次数，应约 360", "input wire [31:0] it_line_rdy,        // 每帧'凑够一行'次数，正常约 360；=0 说明 csi 侧没数据"),
    # ("ITST", "it_state",            "状态 0=等行 1=取FIFO 2=读DDR 3=写回 4=等读回", "input wire [31:0] it_state,           // 状态机状态 0=等行 1=取FIFO 2=读DDR 3=写回 4=等读回收齐"),
    # ("GOFP", "g_px",                "高斯级每帧输出像素数，应 = 0x00038400", "input wire [31:0] g_px,               // 高斯级每帧输出像素数，应 = 0x00038400"),
    # ("GOFL", "g_lines",             "高斯级每帧输出行数，应 = 360", "input wire [15:0] g_lines,            // 高斯级每帧输出行数，应 = 360 = 0x00000168"),
#     ("LKEN", "lk_en",               "块(0,0) Σ|It|", "input wire signed [31:0] lk_en,       // 块(0,0) 的 Σ|It|，与 Python 的 energy 相同"),
#     ("LKPX", "lk_px",               "LK 每帧像素数，应 = 0x00038400", "input wire [31:0] lk_px,              // LK 每帧参与累加的像素数，应 = 0x00038400"),
#     ("LKER", "lk_err",              "LK 异常计数，必须 = 0", "input wire [31:0] lk_err,             // LK 异常计数，必须 = 0"),

    # ---- 诊断采样：固定像素(行100/列100)，每帧采一次 ----
    #   用来判定 LKAX/LKAY 不平衡到底是场景还是数据通路问题
    # ---- 诊断：同列(列100)连续 5 个相邻行的 g，每帧采一次 ----
    #   一次能验证两件事：行缓存环形选择是否正确、抽头竖直 2x2 是否真做了平均
    #     单调平滑         -> 正常
    #     奇偶锯齿(82,86,83) -> 抽头竖直没平均
    #     跳变(82,83,191,84) -> gmem 环选错行
    # ("LKR0", "lk_dbg_r0",           "诊断 g[98][100]",  "input wire [7:0] lk_dbg_r0,          // 诊断: g[98][100]"),
    # ("LKR1", "lk_dbg_r1",           "诊断 g[99][100]",  "input wire [7:0] lk_dbg_r1,          // 诊断: g[99][100]"),
    # ("LKR2", "lk_dbg_r2",           "诊断 g[100][100]", "input wire [7:0] lk_dbg_r2,          // 诊断: g[100][100]"),
    # ("LKR3", "lk_dbg_r3",           "诊断 g[101][100]", "input wire [7:0] lk_dbg_r3,          // 诊断: g[101][100]"),
    # ("LKR4", "lk_dbg_r4",           "诊断 g[102][100]", "input wire [7:0] lk_dbg_r4,          // 诊断: g[102][100]"),
    # ---- B2c-2a：2x2 求解结果（最大变化块）----
#     ("LKU ", "lk_u",                "u 的 Q8.8（像素/帧，有符号）", "input wire signed [31:0] lk_u,  // u = 2*nu_hw/det_hw，Q8.8 像素/帧"),
#     ("LKV ", "lk_v",                "v 的 Q8.8（像素/帧，有符号）", "input wire signed [31:0] lk_v,  // v = 2*nv_hw/det_hw，Q8.8 像素/帧"),
#     ("LKVA", "lk_va",               "该块通过门限（1=有效）", "input wire lk_va,              // 1 = 该块通过门限，u/v 有效"),
#     ("LKBL", "lk_bl",               "最大变化块的列 0..7", "input wire [2:0] lk_bl,        // 最大变化块的块列 0..7"),
#     ("LKBR", "lk_br",               "最大变化块的行 0..5", "input wire [2:0] lk_br,        // 最大变化块的块行 0..5"),
#     ("LKBE", "lk_be", "最大块 en", "input wire [31:0] lk_be, // 最大变化块的 acc_en（诊断 LKBE 恒定用）"),
#     ("LKAE", "lk_ae", "块0~3 的 acc_en>>13", "input wire [31:0] lk_ae, // 8 块能量诊断: 块0~3 的 acc_en>>13（8 位一个字节）"),
#     ("LKAF", "lk_af", "块4~7 的 acc_en>>13", "input wire [31:0] lk_af, // 8 块能量诊断: 块4~7 的 acc_en>>13（8 位一个字节）"),
#     ("LKXA", "lk_xa", "列300 cur/prev-1/prev/prev+1", "input wire [31:0] lk_xa, // 水平错位诊断: 列300 的 {cur[x],prev[x-1],prev[x],prev[x+1]}"),
#     ("LKXB", "lk_xb", "列 60 cur/prev-1/prev/prev+1", "input wire [31:0] lk_xb, // 水平错位诊断: 列 60 的 {cur[x],prev[x-1],prev[x],prev[x+1]}"),
#     ("FXPS", "fxpos", "固定块 {valid,row,col}", "input wire [31:0] fxpos, // 纹理固定块: bit[6]=valid, bit[5:3]=row, bit[2:0]=col（共 32 位）"),
#     ("FXBX", "fxbx", "固定块 bx", "input wire signed [31:0] fxbx, // 固定块本帧的 bx"),
#     ("FXBY", "fxby", "固定块 by", "input wire signed [31:0] fxby, // 固定块本帧的 by"),
#     ("FXEN", "fxen", "固定块 en", "input wire [31:0] fxen, // 固定块本帧的 en"),
#     ("FXTX", "fxtex", "固定块纹理 axx+ayy", "input wire [31:0] fxtex, // 固定块纹理强度 axx+ayy"),
#     ("LKIS", "lk_is",               "与 LKBE 同拍锁存的 ITSM", "input wire [31:0] lk_is, // 与 LKBE 同一拍锁存的 ITSM，用于验证 LKBE <= LKIS"),
    # ("LKDX", "lk_dbg_dix",          "诊断 dIx(行100/列100)", "input wire signed [8:0] lk_dbg_dix,  // 诊断: 行100/列100 处的水平差分 = g[m][p+1]-g[m][p-1]"),
]

BANNER_LEN = len(BANNER)
NF = len(FIELDS)

# 13 号及之后的字段是"会变的"（每秒/每帧更新），需要同一瞬间快照；
# 前面的字段是标志位和常量，变化一次就不再变，不必快照。
SNAP_FROM = 13
NSNAP = sum(1 for i in range(NF) if i >= SNAP_FROM)
FIELD_LEN = 15
# ★ 字段号位宽必须由字段数决定。曾经写死 5 位（当时 32 字段），
#   加到 40 字段后仍是 5 位 -> 最大只能表示 31：
#     * case 里的 5'd32..5'd39 被截断成 0..7，和前面撞项
#     * fld 永远到不了 FLD_LAST=39 -> 一轮永不结束、SEC 永远 0
FLD_BITS = max(1, (NF - 1).bit_length())   # 40 字段 -> 6 位
POS_BITS = 4
BIDX_BITS = 6
ROUND_BYTES = BANNER_LEN + NF * FIELD_LEN
ROUND_MS = ROUND_BYTES * 10 * 1000.0 / 115200.0


def vstr(ch):
    if ch == "\r":
        return "8'h0D"
    if ch == "\n":
        return "8'h0A"
    if ch == '"':
        return '"\\""'
    if ch == "\\":
        return '"\\\\"'
    return '"%s"' % ch


def banner_case():
    out = []
    for i, ch in enumerate(BANNER):
        nice = {"\r": "\\r", "\n": "\\n"}.get(ch, ch)
        out.append("        %d'd%-2d: ban = %-8s; // '%s'"
                   % (BIDX_BITS, i, vstr(ch), nice))
    return "\n".join(out)


def label_cases():
    out = []
    for i, (lbl, _e, _c, _p) in enumerate(FIELDS):
        assert len(lbl) == 4, lbl
        out.append('            %d\'d%-2d: s = "%s";' % (FLD_BITS, i, lbl))
    return "\n".join(out)


def value_cases():
    out = []
    for i, (_l, expr, comment, _p) in enumerate(FIELDS):
        # ★ 会变的字段改从"本轮快照"读，保证整轮日志互相自洽
        src = ("snap[%d]" % i) if i >= SNAP_FROM else expr
        out.append("        %d'd%-2d: v = %-18s; // %s" % (FLD_BITS, i, src, comment))
    out.append("        default:  v = 32'd0;")
    return "\n".join(out)


def snap_load_cases():
    """每秒开轮的那一拍，把所有会变的字段打进快照寄存器"""
    out = []
    for i, (_l, expr, _c, _p) in enumerate(FIELDS):
        if i >= SNAP_FROM:
            out.append("            snap[%2d] <= %s;" % (i, expr))
    return "\n".join(out)


def extra_ports():
    out = []
    for _l, _e, _c, p in FIELDS:
        if p:
            out.append("    %s" % p)
    return "\n".join(out)


def field_help():
    return "\n".join("//      %s 00000000   %s" % (l, c) for l, _e, c, _p in FIELDS)


TEMPLATE = u'''//=====================================================================
//  uart_log_debug.v  ——  串口日志打印（老工程移植 + 逐步扩展）
//
//  作用：通过串口每秒打印一轮板级状态，用来确认 UART 通路是否打通、
//        时钟/像素速率是否符合预期、以及各功能块跑到哪一步了。
//
//  时钟：clk = I_sys_clk = 50 MHz（见 camera_to_dsi_display.sdc: sys_clk_50m）
//  引脚：tx -> O_uart_tx -> 板子 H1（见 pin.adc）
//  串口：115200 8N1；板子 TX(H1) 接 USB-TTL 的 RXD，GND 共地
//
//  ---------------------------------------------------------------------
//  每轮先打 1 行横幅，再打 {nf} 行状态，每行 {flen} 字节，共 {rbytes} 字节//  （115200 下约 {rms:.1f} ms 打完，所以"每秒一轮"绰绰有余）：
//
//      {banner_plain}
{field_help}
//
//  判读方法：
//    * 能看到整齐的上面这些行        -> 波特率 / 帧格式 / 引脚 都对 ✓
//    * SEC 每秒 +1，连续不乱         -> 时钟假设正确 ✓
//    * DIV = 000001B2（434）         -> 分频值正确（50MHz 下 115200）✓
//    * PXFR = 000E1000（921600）     -> 视频流是 1280x720，抽头正确 ✓
//    * CSIH / PIXS                   -> 平均每像素几个 csi 时钟
//    * DTRD = 00003840 且 DTER = 0   -> DDR 算法区域读写自检通过 ✓
//    * 全是乱码                      -> 十有八九是 CLK_HZ 与真实时钟不符 ✗
//
//  ---------------------------------------------------------------------
//  ★ 与底层 uart_tx.v 的握手说明（沿用老工程踩过坑之后的写法）
//     底层 uart_tx.v 用的是 ready/valid 握手，但它的 tx_data_ready 不是
//     "空闲常高"，而且在状态切换那一拍有竞争。历史上用**电平**推进会出现
//     "每个字节被重发"（现象：串口里看到重复字符）。所以这里：
//        ① 等 tx_ready=1（uart 空闲）才装载下一个字节
//        ② tx_valid 只给 **1 拍脉冲**，数据与它同拍寄存
//        ③ 再等 ready 变低（字节被取走）后变高（这一字节发完）
//     这样 uart 每个字节只会在唯一的那个 IDLE 拍被锁存一次，不会重复 ✓
//  ---------------------------------------------------------------------
//  复位说明：rst_n 接 I_rst_n（板级复位），这样 PLL 还没锁的时候
//            串口就已经在打印了，便于定位问题。
//            状态输入分两类，都做了两拍同步：
//              a) 粘滞标志 / 慢变化电平（PLL/CAM/I2C/HS/...）—— 安全
//              b) 每秒刷新的测量值（CSIH/PIXS/FPS/PXFR/DTRD/DTER）
//                 —— 它们本来就只 1 秒变一次，跨域采样同样安全
//=====================================================================
module uart_log_debug #(
    parameter integer CLK_HZ = 50_000_000,   // 本模块时钟频率（Hz）
    parameter integer BAUD   = 115200        // 波特率
)(
    input  wire        clk,                 // I_sys_clk = 50MHz
    input  wire        rst_n,               // 异步复位，低有效
    input  wire        pll_lock,            // PLL 锁定
    input  wire        ddr_init_done,       // DDR 初始化校准完成
    input  wire        cam_cfg_done,        // 摄像头寄存器配置完成（粘滞）
    input  wire        cam_i2c_error,       // 摄像头 I2C 错误
    input  wire [15:0] sensor_id,           // 摄像头 Sensor ID
    input  wire        sensor_id_ok,        // 摄像头 ID 校验通过（0xEE4B/0x9E4B）
    input  wire [3:0]  mipi_diag_status,    // MIPI 诊断码 0..7
    input  wire        hs_seen,             // 已收到 MIPI HS 数据（粘滞）
    input  wire        csi_frame_seen,      // 已解析出 CSI 帧（粘滞）
    input  wire        raw10_seen,          // 已出现 RAW10 流水（粘滞）
    input  wire        video_nonzero_seen,  // 已读到非零视频数据（粘滞）
{extra_ports}
    output wire        tx                   // 串口输出 -> O_uart_tx -> H1
);

    //------------------------------------------------------------------
    // 波特率分频（四舍五入）。这个值会被打印出来，方便核对 CLK_HZ 是否写对。
    //   50_000_000 / 115200 = 434.03 -> 434 = 0x1B2
    //------------------------------------------------------------------
    localparam [31:0] DIV = (CLK_HZ + BAUD/2) / BAUD;

    //------------------------------------------------------------------
    // 一轮消息的长度参数
    //------------------------------------------------------------------
    localparam integer NF        = {nf};   // 状态行（字段）个数
    localparam integer FLD_LAST  = {nf} - 1;
    localparam integer POS_LAST  = {flen} - 1;
    localparam integer BIDX_LAST = {blen} - 1;

    //------------------------------------------------------------------
    // 1 秒节拍
    //   tick 复位成 CLK_HZ-1，于是复位后第一个时钟就产生一次节拍，
    //   上电后立刻先打一轮，之后才是每 1 秒一轮。
    //------------------------------------------------------------------
    reg  [31:0] tick;
    wire        tick_1s = (tick == (CLK_HZ - 1));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tick <= (CLK_HZ - 1);
        else        tick <= tick_1s ? 32'd0 : (tick + 32'd1);
    end

    //------------------------------------------------------------------
    // 跨时钟域同步：状态输入全是粘滞标志 / 慢变化电平，打两拍即可
    //------------------------------------------------------------------
    reg  [1:0]  pll_s, ddr_s, cam_s, i2c_s, hs_s, csif_s, raw_s, vid_s, siok_s;
    reg  [15:0] sid_s1, sid_s2;
    reg  [3:0]  mipi_s1, mipi_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pll_s  <= 2'b00; ddr_s  <= 2'b00; cam_s  <= 2'b00; i2c_s  <= 2'b00;
            hs_s   <= 2'b00; csif_s <= 2'b00; raw_s  <= 2'b00; vid_s  <= 2'b00;
            siok_s <= 2'b00;
            sid_s1 <= 16'd0; sid_s2 <= 16'd0;
            mipi_s1 <= 4'd0; mipi_s2 <= 4'd0;
        end
        else begin
            pll_s  <= {{pll_s[0],  pll_lock}};
            ddr_s  <= {{ddr_s[0],  ddr_init_done}};
            cam_s  <= {{cam_s[0],  cam_cfg_done}};
            i2c_s  <= {{i2c_s[0],  cam_i2c_error}};
            hs_s   <= {{hs_s[0],   hs_seen}};
            csif_s <= {{csif_s[0], csi_frame_seen}};
            raw_s  <= {{raw_s[0],  raw10_seen}};
            vid_s  <= {{vid_s[0],  video_nonzero_seen}};
            siok_s <= {{siok_s[0], sensor_id_ok}};
            mipi_s1 <= mipi_diag_status;
            mipi_s2 <= mipi_s1;
            // Sensor ID 在配置完成后才稳定，等配置完成再采样
            if (cam_s[1]) sid_s1 <= sensor_id;
            sid_s2 <= sid_s1;
        end
    end

    wire [3:0] mipi_code = mipi_s2;

    //------------------------------------------------------------------
    // 运行秒数（每打印完一轮 +1）
    //------------------------------------------------------------------
    reg  [31:0] run_sec;

    //------------------------------------------------------------------
    // 4 位十六进制 -> ASCII
    //------------------------------------------------------------------
    function [7:0] hx;
        input [3:0] n;
        begin
            if (n < 4'd10) hx = 8'h30 + {{4'd0, n}};          // '0'..'9'
            else           hx = 8'h41 + {{4'd0, n}} - 8'd10;  // 'A'..'F'
        end
    endfunction

    //------------------------------------------------------------------
    // 字段标签：给出第 f 个字段的第 p 个字符（p: 0..3，从左到右）
    //------------------------------------------------------------------
    function [7:0] lbl;
        input [{fbits}:0] f;
        input [1:0] p;
        reg  [31:0] s;
        begin
            case (f)
{label_cases}
            default: s = "????";
            endcase
            case (p)
            2'd0:    lbl = s[31:24];
            2'd1:    lbl = s[23:16];
            2'd2:    lbl = s[15: 8];
            default: lbl = s[ 7: 0];
            endcase
        end
    endfunction

    //------------------------------------------------------------------
    // 当前字段的 32bit 值（由 fld 组合译码）
    //------------------------------------------------------------------
    reg  [31:0] v;

    always @(*) begin
        case (fld)
{value_cases}
        endcase
    end

    //------------------------------------------------------------------
    // 当前字段的十六进制 nibble（由 pos 组合译码，只见 pos = 5..12）
    //------------------------------------------------------------------
    reg  [3:0] nib;

    always @(*) begin
        case (pos)
        4'd5:    nib = v[31:28];
        4'd6:    nib = v[27:24];
        4'd7:    nib = v[23:20];
        4'd8:    nib = v[19:16];
        4'd9:    nib = v[15:12];
        4'd10:   nib = v[11: 8];
        4'd11:   nib = v[ 7: 4];
        default: nib = v[ 3: 0];
        endcase
    end

    //------------------------------------------------------------------
    // ★ 整轮日志的快照（本轮新增，修一个真实的观测问题）
    //
    //   下面的 v 是**组合译码**：每个字段是"发到它那一刻"才去取值。
    //   而一轮要发 {rms:.1f} ms，一帧只有 16.7 ms —— 于是
    //     ITSM(字段25) 与 ITSS(字段29) 相隔 4 字段 = 60 字节 = 5.2 ms，
    //     约 31% 的概率落在相邻两帧上。
    //   实测出现过 |ITSS| > ITSM（= 1.67e7 > 1.78e5），这违反三角不等式
    //   |ΣIt| <= Σ|It|，同帧绝不可能 —— 说明两个字段本来就来自不同帧，
    //   不是算法算错。
    //
    //   修法：每秒开轮的那一拍，把所有"会变的"字段（13 号及之后）
    //         一次性打进快照寄存器，整轮日志都从快照读 -> 同一轮内自洽。
    //   代价：{nsnap} 个 32bit 寄存器。标志位/常量不必快照。
    //------------------------------------------------------------------
    wire        snap_ld = (st_r == ST_TICK) && tick_1s;   // 开轮那一拍
    reg  [31:0] snap [0:NF-1];

    always @(posedge clk) begin
        if (snap_ld) begin
{snap_load_cases}
        end
    end

    //------------------------------------------------------------------
    // 横幅：由 bidx 组合译码，共 {blen} 字节
    //------------------------------------------------------------------
    reg  [7:0] ban;

    always @(*) begin
        case (bidx)
{banner_cases}
        default: ban = 8'h20;               // 空格
        endcase
    end

    //------------------------------------------------------------------
    // 一轮消息的字节指针
    //------------------------------------------------------------------
    reg              in_banner;   // 1 = 正在发横幅
    reg  [{bbits}:0] bidx;        // 横幅字节下标
    reg  [{fbits}:0] fld;         // 字段号
    reg  [{pbits}:0] pos;         // 字段内字节位置

    //------------------------------------------------------------------
    // 当前要发的字节
    //   横幅：全部来自 ban
    //   状态行：label(4) + space(1) + hex 8 位(8) + CR + LF = {flen} 字节
    //------------------------------------------------------------------
    reg  [7:0] cur;

    always @(*) begin
        if (in_banner)
            cur = ban;
        else if (pos < 4'd4)
            cur = lbl(fld, pos[1:0]);
        else if (pos == 4'd4)
            cur = 8'h20;                    // space
        else if (pos < 4'd13)
            cur = hx(nib);                  // 8 位十六进制，高位在前
        else if (pos == 4'd13)
            cur = 8'h0D;                    // CR
        else
            cur = 8'h0A;                    // LF
    end

    //------------------------------------------------------------------
    // 发送状态机（1 拍脉冲 + busy 等待，见文件头说明）
    //------------------------------------------------------------------
    localparam ST_TICK = 2'd0,   // 等 1 秒节拍
               ST_LOAD = 2'd1,   // 等 uart 空闲 -> 装载一个字节并给 pulse
               ST_BUSY = 2'd2;   // 等这一字节发完

    reg  [1:0] st_r;
    reg        tx_valid;
    reg  [7:0] tx_data;
    wire       tx_ready;
    reg        seen_low;         // 已经观察到 ready 变低（字节被取走）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_r      <= ST_TICK;
            in_banner <= 1'b1;
            bidx      <= 0;
            fld       <= 0;
            pos       <= 0;
            run_sec   <= 32'd0;
            tx_valid  <= 1'b0;
            tx_data   <= 8'd0;
            seen_low  <= 1'b0;
        end
        else case (st_r)
        // ---------------- 等 1 秒节拍 ----------------
        ST_TICK: begin
            tx_valid <= 1'b0;
            if (tick_1s) begin
                in_banner <= 1'b1;
                bidx      <= 0;
                fld       <= 0;
                pos       <= 0;
                st_r      <= ST_LOAD;
            end
        end
        // ---------------- 装载一个字节 ----------------
        // 必须等 tx_ready=1（uart 在 IDLE 且没在收字节）才装载，
        // 这样 uart 只会在下一个 IDLE 拍锁存一次，不会重复发 ✓
        ST_LOAD: begin
            if (tx_ready) begin
                tx_data  <= cur;         // cur 由 in_banner/bidx/fld/pos 组合译码
                tx_valid <= 1'b1;        // 只给 1 拍脉冲
                seen_low <= 1'b0;
                st_r     <= ST_BUSY;
            end
        end
        // ---------------- 等这个字节发完，然后推进指针 ----------------
        ST_BUSY: begin
            tx_valid <= 1'b0;            // 脉冲已经给过了
            if (!tx_ready) begin
                seen_low <= 1'b1;        // 字节被取走
            end
            else if (seen_low) begin     // ready 回来了 = 这一字节发完
                if (in_banner) begin
                    if (bidx == BIDX_LAST) begin
                        in_banner <= 1'b0;   // 横幅发完，转入状态行
                        fld       <= 0;
                        pos       <= 0;
                    end
                    else begin
                        bidx <= bidx + 1'b1;
                    end
                    st_r <= ST_LOAD;
                end
                else if (pos != POS_LAST) begin
                    pos  <= pos + 1'b1;      // 同一行下一个字符
                    st_r <= ST_LOAD;
                end
                else if (fld != FLD_LAST) begin
                    pos  <= 0;               // 下一行
                    fld  <= fld + 1'b1;
                    st_r <= ST_LOAD;
                end
                else begin
                    run_sec <= run_sec + 32'd1;  // 一轮打完，秒数 +1
                    st_r    <= ST_TICK;
                end
            end
        end
        default: st_r <= ST_TICK;
        endcase
    end

    //------------------------------------------------------------------
    // 底层 UART 发送器（官方 uart_tx.v，未修改）
    //   注意：uart_tx 的 CLK_FRE 单位是 MHz，所以传 CLK_HZ/1000000 = 50
    //------------------------------------------------------------------
    uart_tx #(
        .CLK_FRE   (CLK_HZ / 1000000),
        .BAUD_RATE (BAUD)
    ) u_uart_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .tx_data       (tx_data),
        .tx_data_valid (tx_valid),
        .tx_data_ready (tx_ready),
        .tx_pin        (tx)
    );

endmodule
'''


def build():
    return TEMPLATE.format(
        nf=NF,
        flen=FIELD_LEN,
        rbytes=ROUND_BYTES,
        rms=ROUND_MS,
        blen=BANNER_LEN,
        bbits=BIDX_BITS - 1,
        fbits=FLD_BITS - 1,
        pbits=POS_BITS - 1,
        banner_plain=BANNER.replace("\r", "\\r").replace("\n", "\\n"),
        field_help=field_help(),
        extra_ports=extra_ports(),
        banner_cases=banner_case(),
        label_cases=label_cases(),
        value_cases=value_cases(),
        snap_load_cases=snap_load_cases(),
        nsnap=NSNAP,
    ).replace("\n", "\r\n")


def main():
    data = build().encode("utf-8")
    with io.open(OUT, "wb") as f:
        f.write(data)
    print("wrote %s (%d bytes)" % (OUT, len(data)))
    print("banner=%d, fields=%d, round=%d bytes, %.1f ms"
          % (BANNER_LEN, NF, ROUND_BYTES, ROUND_MS))


if __name__ == "__main__":
    main()
