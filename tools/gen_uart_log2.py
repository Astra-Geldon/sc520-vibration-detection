#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Generate the compact, coherent 1 Hz vibration UART log.

Edit FIELD_GROUPS and this template, then regenerate the RTL. The generator
is self-contained; it never reads uart_log_debug.v to construct its output.
Run from any directory. Use --check to verify without rewriting the RTL.
Legacy disabled diagnostic input ports remain for top-level compatibility.
"""
import argparse
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / 'user_source/hdl_source/uart_log_debug.v'

# One group is one physical CRLF line. Labels are always four characters.
# All values, including SEC, are sampled once when the round starts.
FIELD_GROUPS = [
    # Round identity and source errors.
    [('SEC ', 'run_sec'), ('WINC', 'mb_win'), ('RVER', "32'h0002_000A"),
     ('VTAP', 'tap_ovf'), ('ITER', 'it_err')],
    # Raw, qualified, confirmed counts; consecutive counts; grid positions.
    [('ACT ', 'mb_active'), ('QACT', 'qact'), ('CNFM', 'confirmed'),
     ('STK0', 'mb_streak'), ('OBP1', 'obj_pos')],
    # Confirmed slot frequencies, Hz times ten; zero when invalid.
    [('HZ1 ', "{24'd0,mb_obj_hz10[7:0]}"),
     ('HZ2 ', "{24'd0,mb_obj_hz10[15:8]}"),
     ('HZ3 ', "{24'd0,mb_obj_hz10[23:16]}"),
     ('HZ4 ', "{24'd0,mb_obj_hz10[31:24]}")],
    # Confirmed slot RAW peak >> 8, retaining their historical names.
    [('OBM1', 'obj_pn0'), ('OBM2', 'obj_pn1'),
     ('OBM3', 'obj_pn2'), ('OBM4', 'obj_pn3')],
    # Observer is this window's raw strongest block. Exclude +/-one bin
    # when finding P2HZ/P2MG; raw RHZ does not imply qualification.
    [('PBLK', 'mb_best_blk'), ('RHZ ', 'raw_hz'), ('PKMG', 'mb_mag'),
     ('P2HZ', 'diag_second_hz'), ('P2MG', 'diag_second_mag')],
    # Strongest qualified candidate and its same-window selection masks.
    [('QBLK', 'chal_blk'), ('QHZ ', 'diag_qual_hz'),
     ('QMAG', 'diag_qual_mag'), ('QSTA', 'diag_qual_status')],
    # Window/frame/state health, including all48 *27 states.
    [('MBFR', 'mb_frm'), ('CLRC', 'mb_clr'),
     ('SCNC', 'mb_scan'), ('WPRD', 'wprd')],
]
FIELDS = [field for group in FIELD_GROUPS for field in group]
NF = len(FIELDS)
NLINES = len(FIELD_GROUPS)
FLD_BITS = max(1, (NF - 1).bit_length())
# Each field uses 4 label bytes, one space and eight hex digits. Interior
# fields add one separating space; the last field in each group adds CRLF.
ROUND_BYTES = sum(14 * len(group) + 1 for group in FIELD_GROUPS)

TEMPLATE = r"""//=====================================================================
// uart_log_debug.v -- compact 1 Hz board log, 115200 8N1 (2026-10-28).
//
// Default output: @NF@ fields in @NLINES@ CRLF-terminated lines, @ROUND_BYTES@ bytes/round.
// The repeated banner and low-priority fields are disabled. All numbers
// remain eight hexadecimal digits; HZ1..HZ4 and RHZ remain Hz * 10.
//
@GROUP_HELP@
//
// ACT/QACT/CNFM: raw / qualified / confirmed counts. OBP1 packs four
// positions (each byte: bit6 valid, bits5:3 row, bits2:0 column).
// OBM1..4 are RAW peak >> 8, despite the historical names. PBLK/RHZ/PKMG
// identify the same strongest raw block in one completed window. P2HZ/P2MG
// give its strongest positive peak outside RHZ's own and adjacent bins.
// A zero second frequency means no positive eligible second peak exists.
// QBLK/QHZ/QMAG identify the strongest QUALIFIED candidate, before slot
// confirmation. QBLK=63 and QHZ=QMAG=0 mean no qualified candidate.
// QSTA: bit0 qualified candidate exists; bit1 raw PBLK is qualified;
// [7:4] exact candidate selected mask; [11:8] exact CONFIRMED mask;
// [15:12] same-bin nearby representative mask; [19:16] occupied slots;
// bit20 window veto; [24:21] frequency-change pending; other bits zero.
// In each four-bit mask, bit0 is slot1.
// Selected/occupied includes pending slots, so selection is not confirmation.
// RVER=00020009 added independent two-window frequency-change confirmation
// for published matched targets, and11-bit/2048 state capacity.
// RVER=0002000A extends the active chain to27 bins,2.0..15.0Hz in
// 0.5Hz steps;64-frame windows and existing thresholds/confirmation remain.
// CLRC/SCNC are1296 (0x510); maximum Hz10 is150 (0x96).
// Read-only diagnostics from00020007 remain; common motion stays disabled.
// First acquisition: two matched windows both >=512 confirm; otherwise
// three qualified matched windows. A changed bin in a confirmed matched
// slot additionally needs two identical new-bin windows. Pending slots
// publish zero position/frequency/magnitude, without holding stale values.
// Strength is per slot, not global PKMG; STK0 remains the track streak.
// Candidate admission and the 64-frame window remain unchanged.
//
// Disabled fields are listed beside the snapshot assignments below;
// their input ports remain compatible with the existing top-level.
// Snapshot all enabled measurements once at round start, preserving
// frequency/position/energy coherence while the UART serializes them.
// The existing ready -> one-cycle valid -> ready-low -> ready-high
// handshake is retained to prevent duplicate or missing UART bytes.
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
    input wire [31:0] tap_px_per_frame, // 抽头每帧像素数，应为230400
    input wire [31:0] tap_lines, // 抽头每帧行数，应为360
    input wire [31:0] it_px, // 上一帧差分像素数，应为230400
    input wire [31:0] it_lines, // 上一帧差分行数，应为360
    input wire [31:0] vsum, // 抽头每帧灰度和
    input wire [31:0] mb_frm, // 刚完成窗口的帧数，应为64
    input wire [31:0] mb_active, // 原始峰值raw>>8大于64的块数，突出度筛选前，0到48
    input wire [31:0] mb_obj_hz10, // 已确认目标1频率乘10，无效为0
    input wire [31:0] mb_agc_ref, // AGC参考对数
    input wire [31:0] mb_best_blk, // 本窗口全局原始峰值块，块号=row乘8加col
    input wire [31:0] mb_streak, // 四个独立目标槽连续匹配窗口数，每槽3bit
    input wire [31:0] mb_clr, // 状态清零写次数，应为1296即0x510
    input wire [31:0] mb_mag, // 本窗口全局原始峰值raw>>8，与PBLK对应
    input wire [31:0] fx_bx, // LK诊断固定块bx
    input wire [31:0] fx_en, // LK诊断固定块能量
    input wire [31:0] b2, // 本窗口PBLK的4Hz频点能量raw>>8，bin4
    input wire [31:0] b4, // 本窗口PBLK的6Hz频点能量raw>>8，bin8
    input wire [31:0] b8, // 本窗口PBLK的10Hz频点能量raw>>8，bin16
    input wire [31:0] b12, // 本窗口PBLK的8Hz频点能量raw>>8，bin12
    input wire [31:0] tonal_map_lo, // 原始峰值与突出度合格块位图低32位
    input wire [31:0] tonal_map_hi, // 原始峰值与突出度合格块位图高16位
    input wire [31:0] obj_pos, // 四个网格框，每字节bit6有效、bit5至3行、bit2至0列
    input wire [31:0] fx_pn, // PBLK原始峰值raw>>8，保留旧字段名，等于PKMG
    input wire [31:0] obj_pn0, // 已确认目标1原始峰值raw>>8，与OBP1同槽位
    input wire [31:0] obj_pn1, // 已确认目标2原始峰值raw>>8，与OBP1同槽位
    input wire [31:0] obj_pn2, // 已确认目标3原始峰值raw>>8，与OBP1同槽位
    input wire [31:0] obj_pn3, // 已确认目标4原始峰值raw>>8，与OBP1同槽位
    input wire [31:0] chal_blk, // 本窗口最强合格块号，无合格块为63
    input wire [31:0] qact, // 原始峰值大于64且突出度通过的块数，确认前，0到48
    input wire [31:0] wprd, // 窗口周期，单位为50MHz时钟拍
    input wire [31:0] tap_ovf, // 抽头异常计数，应为0
    input wire [31:0] it_err, // 上一帧缓存异常计数，应为0
    input wire [31:0] mb_scan, // 刚完成窗口的频点扫描计数
    input wire [31:0] mb_win, // 已完成窗口数，8bit回绕
    input wire [31:0] raw_bin, // 本窗口PBLK的原始峰值bin，0到26
    input wire [31:0] raw_hz, // 本窗口原始峰值Hz10，未合格也报告
    input wire [31:0] raw_aexp, // PBLK纹理指数，仅诊断
    input wire [31:0] confirmed, // 独立确认的目标数，0到4
    input wire [31:0] tn_status, // bit0原始最强块合格，bit1存在已确认目标
    input wire [31:0] motion_info, // 四处分散参考的二维共同运动窗口诊断，CMOT
    input wire [31:0] diag_second_hz, // PBLK非相邻次峰频率乘10，无正能量为0
    input wire [31:0] diag_second_mag, // 同块非相邻次峰raw能量右移8位
    input wire [31:0] diag_qual_hz, // 最强合格候选频率乘10，无候选为0
    input wire [31:0] diag_qual_mag, // 最强合格候选raw能量右移8位
    input wire [31:0] diag_qual_status, // QSTA，同窗候选入槽/确认/邻近代表掩码
    output wire        tx                   // 串口输出 -> O_uart_tx -> H1
);


    localparam integer NF = @NF@;
    localparam integer FLD_LAST = NF - 1;

    reg [31:0] tick;
    wire tick_1s = (tick == (CLK_HZ - 1));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tick <= (CLK_HZ - 1);
        else tick <= tick_1s ? 32'd0 : tick + 32'd1;
    end

    reg [31:0] run_sec;
    reg [@FLD_MSB@:0] fld;
    reg [3:0] pos;

    function [7:0] hx;
        input [3:0] n;
        begin
            if (n < 4'd10) hx = 8'h30 + {4'd0,n};
            else hx = 8'h41 + {4'd0,n} - 8'd10;
        end
    endfunction

    function [7:0] lbl;
        input [@FLD_MSB@:0] f;
        input [1:0] p;
        reg [31:0] s;
        begin
            case (f)
@LABEL_CASES@
            default: s = "????";
            endcase
            case (p)
            2'd0: lbl = s[31:24];
            2'd1: lbl = s[23:16];
            2'd2: lbl = s[15:8];
            default: lbl = s[7:0];
            endcase
        end
    endfunction

    // Keep each group on one line; no blank line or repeated banner.
    wire line_end = @LINE_END@;
    wire field_done = line_end ? (pos == 4'd14) : (pos == 4'd13);

    localparam ST_TICK = 2'd0, ST_LOAD = 2'd1, ST_BUSY = 2'd2;
    reg [1:0] st_r;
    reg tx_valid;
    reg [7:0] tx_data;
    wire tx_ready;
    reg seen_low;

    wire snap_ld = (st_r == ST_TICK) && tick_1s;
    reg [31:0] snap [0:NF-1];
    always @(posedge clk) begin
        if (snap_ld) begin
@SNAP_CASES@
            // Disabled low-priority / redundant fields (ports retained):
            // VOFP=tap_px_per_frame; VOFL=tap_lines;
            // ITPX=it_px; ITLN=it_lines; VSUM=vsum;
            // FXBX=fx_bx; FXEN=fx_en; TON1=tonal_map_lo; TON2=tonal_map_hi;
            // FBPN=fx_pn (duplicates PKMG); TNST=tn_status.
            // F04=b2; F06=b4; F08=b12; F10=b8; RBIN=raw_bin; AEXP=raw_aexp;
            // AGCR=mb_agc_ref; CMOT=motion_info (disabled0). CHLK is now QBLK.
        end
    end

    wire [31:0] v = snap[fld];
    reg [3:0] nib;
    always @(*) begin
        case (pos)
        4'd5: nib = v[31:28];
        4'd6: nib = v[27:24];
        4'd7: nib = v[23:20];
        4'd8: nib = v[19:16];
        4'd9: nib = v[15:12];
        4'd10: nib = v[11:8];
        4'd11: nib = v[7:4];
        default: nib = v[3:0];
        endcase
    end

    reg [7:0] cur;
    always @(*) begin
        if (pos < 4'd4) cur = lbl(fld,pos[1:0]);
        else if (pos == 4'd4) cur = 8'h20;
        else if (pos < 4'd13) cur = hx(nib);
        else if (pos == 4'd13) cur = line_end ? 8'h0D : 8'h20;
        else cur = 8'h0A;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_r <= ST_TICK;
            fld <= 0;
            pos <= 0;
            run_sec <= 32'd0;
            tx_valid <= 1'b0;
            tx_data <= 8'd0;
            seen_low <= 1'b0;
        end
        else case (st_r)
        ST_TICK: begin
            tx_valid <= 1'b0;
            if (tick_1s) begin
                fld <= 0;
                pos <= 0;
                st_r <= ST_LOAD;
            end
        end
        ST_LOAD: begin
            if (tx_ready) begin
                tx_data <= cur;
                tx_valid <= 1'b1;
                seen_low <= 1'b0;
                st_r <= ST_BUSY;
            end
        end
        ST_BUSY: begin
            tx_valid <= 1'b0;
            if (!tx_ready) seen_low <= 1'b1;
            else if (seen_low) begin
                if (!field_done) begin
                    pos <= pos + 1'b1;
                    st_r <= ST_LOAD;
                end
                else if (fld != FLD_LAST) begin
                    pos <= 0;
                    fld <= fld + 1'b1;
                    st_r <= ST_LOAD;
                end
                else begin
                    run_sec <= run_sec + 32'd1;
                    st_r <= ST_TICK;
                end
            end
        end
        default: st_r <= ST_TICK;
        endcase
    end

    // Existing transmitter, unchanged. CLK_FRE is expressed in MHz.
    uart_tx #(
        .CLK_FRE (CLK_HZ / 1000000),
        .BAUD_RATE (BAUD)
    ) u_uart_tx (
        .clk (clk), .rst_n (rst_n),
        .tx_data (tx_data), .tx_data_valid (tx_valid),
        .tx_data_ready (tx_ready), .tx_pin (tx)
    );
endmodule
"""


def line_end_expression():
    ends = []
    count = 0
    for group in FIELD_GROUPS:
        count += len(group)
        ends.append(count - 1)
    terms = [f"(fld == {FLD_BITS}'d{end})" for end in ends]
    chunks = [terms[i:i + 2] for i in range(0, len(terms), 2)]
    # Avoid a final line containing a lone comparison.
    if len(chunks) > 1 and len(chunks[-1]) == 1:
        chunks[-2].extend(chunks.pop())
    return ' ||\n                    '.join(' || '.join(chunk) for chunk in chunks)


def build():
    """Return complete UTF-8-ready Verilog with deterministic CRLF endings."""
    if not FIELDS or any(not 1 <= len(group) <= 5 for group in FIELD_GROUPS):
        raise ValueError('Each log line must contain one to five fields')
    labels = [label for label, _expr in FIELDS]
    if any(len(label) != 4 for label in labels) or len(set(labels)) != NF:
        raise ValueError('Field labels must be unique and exactly four characters')
    substitutions = {
        '@NF@': str(NF), '@NLINES@': str(NLINES),
        '@ROUND_BYTES@': str(ROUND_BYTES), '@FLD_MSB@': str(FLD_BITS - 1),
        '@GROUP_HELP@': '\n'.join('//   ' + ' '.join(label + ' xxxxxxxx'
                                  for label, _expr in group) for group in FIELD_GROUPS),
        '@LABEL_CASES@': '\n'.join(f'            {FLD_BITS}\'d{i}: s = "{label}";'
                                   for i, (label, _expr) in enumerate(FIELDS)),
        '@LINE_END@': line_end_expression(),
        '@SNAP_CASES@': '\n'.join(f'            snap[{i:2}] <= {expr};'
                                  for i, (_label, expr) in enumerate(FIELDS)),
    }
    data = TEMPLATE
    for marker, value in substitutions.items():
        data = data.replace(marker, value)
    return data.replace('\r\n', '\n').replace('\n', '\r\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true',
                        help='Compare generated content with installed RTL without rewriting')
    args = parser.parse_args()
    data = build()
    if args.check:
        if OUT.read_text(encoding='utf-8-sig') != data.replace('\r\n', '\n'):
            raise SystemExit(f'Generated content differs: {OUT}')
        print(f'CHECK_OK {OUT}')
    else:
        OUT.write_bytes(data.encode('utf-8'))
        print(f'wrote {OUT} ({len(data.encode("utf-8"))} bytes)')
    print(f'fields={NF}, lines={NLINES}, round={ROUND_BYTES} bytes, '
          f'{ROUND_BYTES * 10 * 1000 / 115200:.1f} ms at 115200 baud')


if __name__ == '__main__':
    main()
