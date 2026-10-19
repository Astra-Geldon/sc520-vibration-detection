# -*- coding: utf-8 -*-
"""
功能断言检查（端口连接性由 check_ports.py 负责，这里不重复）。

只验证"改过的关键逻辑确实在源码里"，防止脚本静默失败导致改动没落地。
"""
import io
import os
import re
import sys

H = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
     'user_source', 'hdl_source')
LK = os.path.join(H, 'vib_lk_grid.v')
TOP = os.path.join(H, 'design_top_wrapper.v')

lk = io.open(LK, 'rb').read().decode('utf-8')
top = io.open(TOP, 'rb').read().decode('utf-8')

fails = 0


def chk(name, ok, detail=''):
    global fails
    if ok:
        print('  OK   ' + name)
    else:
        fails += 1
        print('  FAIL ' + name + ('   ' + detail if detail else ''))


print('=== 显示通路关闭 ===')
chk('VIB_NO_DISPLAY 已定义', '`define VIB_NO_DISPLAY' in top)
chk('video_out 被 ifndef 包住',
    re.search(r'`ifndef VIB_NO_DISPLAY\s*\n\s*video_out u_video_out', top) is not None)
# 注意：不能要求 hdmi_mixer 紧跟 `ifndef —— img_proc 是插在它们之间的（img_proc.v）。
# 这里只断言 hdmi_mixer / hdmi_tx 确实落在最后一个 `ifndef VIB_NO_DISPLAY 块内。
_disp = top[top.rfind('`ifndef VIB_NO_DISPLAY'):].split('`else')[0]
chk('hdmi_mixer/hdmi_tx 被 ifndef 包住',
    re.search(r'\bhdmi_mixer\b', _disp) is not None and
    re.search(r'\bhdmi_tx u_hdmi_tx\b', _disp) is not None)
chk('video_out 关闭时输出接地',
    "assign S_video_out_rd_busy = 1'b0;" in top and
    "assign S_vo_ddr_rd_en      = 1'b0;" in top and
    "assign S_vo_ddr_rd_addr    = 25'd0;" in top)
chk('HDMI 关闭时 TMDS 输出接地',
    "assign O_tmds_ch0_p        = 1'b0;" in top and
    "assign O_tmds_clk_p        = 1'b0;" in top)

print()
print('=== 厂商除法器 ===')
chk('串行除法器 vib_div_serial 已例化（8 端口齐全）',
    re.search(r'\bvib_div_serial\b', lk) is not None and
    all(('.' + p) in lk for p in
        ['clk', 'rst_n', 'start', 'numer', 'denom', 'quot', 'rem', 'done']))
chk('除数器用低有效复位 rst_n',
    re.search(r'\.rst_n\s*\(\s*rst_n\s*\)', lk) is not None)
chk('厂商 divider 已不再例化',
    re.search(r'\bdivider\s+u_div\s*\(', lk) is None)
chk('累加器入口预缩放为两档自适应 (>>6 / >>12, 阈值 2^19)',
    ('s_axx >>> 6' in lk and 's_bx  >>> 6' in lk and
     's_axx >>> 12' in lk and 's_bx  >>> 12' in lk and
     'weak_q' in lk and "32'sd524288" in lk))
chk('被除数 = |nu|<<9（48 位饱和）',
    'nu_abs_q << 9' in lk and 'nu_abs_q[63:39]' in lk)
chk('除数 = det[31:0]', 'den32    = det[31:0]' in lk)
chk('商不需要还原移位',
    'div_quot[31:0]' in lk and 'div_quot[37:6]' not in lk)
chk('MIN_GRAD 用未缩放的 grad_full', 'grad_full >= MIN_GRAD' in lk)
chk('精度门限 det>=1024（signed 比较，负值自然为假）',
    'det > 64\'sd1023' in lk)
chk('旧手写除法器已移除',
    'num_u_ld' not in lk and 'quot_next' not in lk and 'rshift' not in lk)

print()
print('=== 诊断探针 ===')
chk('st_dbg_sel 有实际赋值',
    re.search(r'st_dbg_sel\s*<=\s*\{\s*wr_sel', lk) is not None)
chk('LKPA/LKPB 有采样',
    re.search(r'st_dbg_pa\s*<=\s*bP1', lk) is not None and
    re.search(r'st_dbg_pb\s*<=\s*bP1', lk) is not None)
chk('行 checksum 存在', 'line_chk' in lk)
chk('8 块能量压缩输出存在',
    re.search(r'st_dbg_ae\s*<=\s*\{ae3', lk) is not None)

print()
print('=== DDR 自检已移除 ===')
chk('vib_ddr_selftest 未例化',
    not re.search(r'^\s*vib_ddr_selftest\s+u_', top, re.M))
chk('S_dt_active 恒 0', "wire S_dt_active = 1'b0;" in top)

print()
print('结论: ' + ('全部通过 [OK]' if fails == 0 else '**%d 项失败**' % fails))
sys.exit(0 if fails == 0 else 1)
