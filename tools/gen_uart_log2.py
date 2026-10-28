#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Generate the repair-2 raw-spectrum and multi-target UART field table.
Run from any working directory; paths resolve relative to this script.
All changing fields are latched once per printed round.
Edit FIELDS here and regenerate uart_log_debug.v; do not hand-edit RTL.
"""
import io
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
     'user_source', 'hdl_source', 'uart_log_debug.v')

BANNER = "SC520 MIPI-HDMI UART LOG 115200 8N1\r\n"

# (label, value expression, comment, port declaration or None if internal)
FIELDS = [
    ('SEC ', 'run_sec', '运行秒数', None),
    ('VOFP', 'tap_px_per_frame', '抽头每帧像素数，应为230400', 'input wire [31:0] tap_px_per_frame, // 抽头每帧像素数，应为230400'),
    ('VOFL', 'tap_lines', '抽头每帧行数，应为360', 'input wire [31:0] tap_lines, // 抽头每帧行数，应为360'),
    ('ITPX', 'it_px', '上一帧差分像素数，应为230400', 'input wire [31:0] it_px, // 上一帧差分像素数，应为230400'),
    ('ITLN', 'it_lines', '上一帧差分行数，应为360', 'input wire [31:0] it_lines, // 上一帧差分行数，应为360'),
    ('VSUM', 'vsum', '抽头每帧灰度和', 'input wire [31:0] vsum, // 抽头每帧灰度和'),
    ('MBFR', 'mb_frm', '刚完成窗口的帧数，应为64', 'input wire [31:0] mb_frm, // 刚完成窗口的帧数，应为64'),
    ('ACT ', 'mb_active', '原始峰值raw>>8大于25的块数，突出度筛选前，0到48', 'input wire [31:0] mb_active, // 原始峰值raw>>8大于25的块数，突出度筛选前，0到48'),
    ('HZ1 ', "{24'd0,mb_obj_hz10[7:0]}", '已确认目标1频率乘10，无效为0', 'input wire [31:0] mb_obj_hz10, // 已确认目标1频率乘10，无效为0'),
    ('HZ2 ', "{24'd0,mb_obj_hz10[15:8]}", '已确认目标2频率乘10，无效为0', None),
    ('HZ3 ', "{24'd0,mb_obj_hz10[23:16]}", '已确认目标3频率乘10，无效为0', None),
    ('HZ4 ', "{24'd0,mb_obj_hz10[31:24]}", '已确认目标4频率乘10，无效为0', None),
    ('AGCR', 'mb_agc_ref', 'AGC参考对数', 'input wire [31:0] mb_agc_ref, // AGC参考对数'),
    ('PBLK', 'mb_best_blk', '本窗口全局原始峰值块，块号=row乘8加col', 'input wire [31:0] mb_best_blk, // 本窗口全局原始峰值块，块号=row乘8加col'),
    ('STK0', 'mb_streak', '四个独立目标槽连续匹配窗口数，每槽3bit', 'input wire [31:0] mb_streak, // 四个独立目标槽连续匹配窗口数，每槽3bit'),
    ('CLRC', 'mb_clr', '状态清零写次数，应为816即0x330', 'input wire [31:0] mb_clr, // 状态清零写次数，应为816即0x330'),
    ('PKMG', 'mb_mag', '本窗口全局原始峰值raw>>8，与PBLK对应', 'input wire [31:0] mb_mag, // 本窗口全局原始峰值raw>>8，与PBLK对应'),
    ('FXBX', 'fx_bx', 'LK诊断固定块bx', 'input wire [31:0] fx_bx, // LK诊断固定块bx'),
    ('FXEN', 'fx_en', 'LK诊断固定块能量', 'input wire [31:0] fx_en, // LK诊断固定块能量'),
    ('F04 ', 'b2', '本窗口PBLK的4Hz频点能量raw>>8，bin4', 'input wire [31:0] b2, // 本窗口PBLK的4Hz频点能量raw>>8，bin4'),
    ('F06 ', 'b4', '本窗口PBLK的6Hz频点能量raw>>8，bin8', 'input wire [31:0] b4, // 本窗口PBLK的6Hz频点能量raw>>8，bin8'),
    ('F10 ', 'b8', '本窗口PBLK的10Hz频点能量raw>>8，bin16', 'input wire [31:0] b8, // 本窗口PBLK的10Hz频点能量raw>>8，bin16'),
    ('F08 ', 'b12', '本窗口PBLK的8Hz频点能量raw>>8，bin12', 'input wire [31:0] b12, // 本窗口PBLK的8Hz频点能量raw>>8，bin12'),
    ('TON1', 'tonal_map_lo', '原始峰值与突出度合格块位图低32位', 'input wire [31:0] tonal_map_lo, // 原始峰值与突出度合格块位图低32位'),
    ('TON2', 'tonal_map_hi', '原始峰值与突出度合格块位图高16位', 'input wire [31:0] tonal_map_hi, // 原始峰值与突出度合格块位图高16位'),
    ('OBP1', 'obj_pos', '四个网格框，每字节bit6有效、bit5至3行、bit2至0列', 'input wire [31:0] obj_pos, // 四个网格框，每字节bit6有效、bit5至3行、bit2至0列'),
    ('FBPN', 'fx_pn', 'PBLK原始峰值raw>>8，保留旧字段名，等于PKMG', 'input wire [31:0] fx_pn, // PBLK原始峰值raw>>8，保留旧字段名，等于PKMG'),
    ('OBM1', 'obj_pn0', '已确认目标1原始峰值raw>>8，与OBP1同槽位', 'input wire [31:0] obj_pn0, // 已确认目标1原始峰值raw>>8，与OBP1同槽位'),
    ('OBM2', 'obj_pn1', '已确认目标2原始峰值raw>>8，与OBP1同槽位', 'input wire [31:0] obj_pn1, // 已确认目标2原始峰值raw>>8，与OBP1同槽位'),
    ('OBM3', 'obj_pn2', '已确认目标3原始峰值raw>>8，与OBP1同槽位', 'input wire [31:0] obj_pn2, // 已确认目标3原始峰值raw>>8，与OBP1同槽位'),
    ('OBM4', 'obj_pn3', '已确认目标4原始峰值raw>>8，与OBP1同槽位', 'input wire [31:0] obj_pn3, // 已确认目标4原始峰值raw>>8，与OBP1同槽位'),
    ('CHLK', 'chal_blk', '本窗口最强合格块号，无合格块为63', 'input wire [31:0] chal_blk, // 本窗口最强合格块号，无合格块为63'),
    ('QACT', 'qact', '原始峰值大于25且突出度通过的块数，确认前，0到48', 'input wire [31:0] qact, // 原始峰值大于25且突出度通过的块数，确认前，0到48'),
    ('WPRD', 'wprd', '窗口周期，单位为50MHz时钟拍', 'input wire [31:0] wprd, // 窗口周期，单位为50MHz时钟拍'),
    ('VTAP', 'tap_ovf', '抽头异常计数，应为0', 'input wire [31:0] tap_ovf, // 抽头异常计数，应为0'),
    ('ITER', 'it_err', '上一帧缓存异常计数，应为0', 'input wire [31:0] it_err, // 上一帧缓存异常计数，应为0'),
    ('SCNC', 'mb_scan', '刚完成窗口的频点扫描计数', 'input wire [31:0] mb_scan, // 刚完成窗口的频点扫描计数'),
    ('WINC', 'mb_win', '已完成窗口数，8bit回绕', 'input wire [31:0] mb_win, // 已完成窗口数，8bit回绕'),
    ('RVER', "32'h0002_0001", '修复2版本标识，应为00020001', None),
    ('RBIN', 'raw_bin', '本窗口PBLK的原始峰值bin，0到16', 'input wire [31:0] raw_bin, // 本窗口PBLK的原始峰值bin，0到16'),
    ('RHZ ', 'raw_hz', '本窗口原始峰值Hz10，未合格也报告，峰值0时为0', 'input wire [31:0] raw_hz, // 本窗口原始峰值Hz10，未合格也报告'),
    ('AEXP', 'raw_aexp', 'PBLK纹理指数，仅诊断，不参与候选门限', 'input wire [31:0] raw_aexp, // PBLK纹理指数，仅诊断'),
    ('CNFM', 'confirmed', '独立确认的目标数，0到4', 'input wire [31:0] confirmed, // 独立确认的目标数，0到4'),
    ('TNST', 'tn_status', 'bit0原始最强块合格，bit1存在已确认目标', 'input wire [31:0] tn_status, // bit0原始最强块合格，bit1存在已确认目标'),
]

BANNER_LEN = len(BANNER)
NF = len(FIELDS)

# SEC直接读取，其余测量值在每轮开头一起快照。
SNAP_FROM = 1
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
//  每轮先打 1 行横幅，再打 {nf} 行状态，每行 {flen} 字节，共 {rbytes} 字节
//  （115200 下约 {rms:.1f} ms 打完，所以"每秒一轮"绰绰有余）：
//
//      {banner_plain}
{field_help}
//
//  判读方法：
//    * 能看到整齐的上面这些行        -> 波特率 / 帧格式 / 引脚 都对 ✓
//    * SEC 每秒 +1，连续不乱         -> 时钟假设正确 ✓
//    * RVER = 00020001               -> 当前为原始频谱候选修复版本
//    * VOFP/ITPX=00038400，VOFL/ITLN=00000168 -> 640x360抽头与帧差计数正确
//    * CLRC/SCNC=00000330，WINC递增   -> 48块乘17频点窗口持续完成
//    * ACT/QACT/CNFM                 -> 原始能量块数/突出度合格块数/确认目标数
//    * PBLK/RBIN/RHZ/AEXP/F04/F06/F08/F10 -> 同一窗口、同一原始最强块
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
//            标志位在本模块中用两拍同步。
//            多位测量值由顶层通过源域完成toggle复制到本时钟域，
//            本模块再于每轮开始统一快照，避免字段跨窗口混用。
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
    //   一轮要发 {rms:.1f} ms，期间顶层窗口快照可能更新。
    //   每秒开轮的那一拍，把SEC之外的字段一次性打进快照寄存器，
    //   整轮日志都从快照读，频率、位置、原始频谱和候选计数保持一致。
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
