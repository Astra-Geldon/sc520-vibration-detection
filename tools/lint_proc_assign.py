# -*- coding: utf-8 -*-
"""静态检查：always 块里是否对 wire 做了过程赋值（HDL-8007 那类错误）"""
import io
import os
import re

H = (r'D:\workplace\lab_ex1_mipi_hdmi_SC520 (2)\lab_ex1_mipi_hdmi_SC520'
     r'\lab_ex1_mipi_hdmi\user_source\hdl_source')

FILES = ['vib_lk_grid.v', 'vib_prev_frame_ddr.v', 'vib_gauss3x3.v',
         'design_top_wrapper.v', 'uart_log_debug.v',
         r'vibration\vib_video_tap.v', r'vibration\vib_ddr_arb.v',
         r'vibration\vib_ddr_selftest.v', 'clk_pixel_meter.v']


def strip_comments(t):
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', t)


def declarations(t):
    """按 ';' 切分语句，逐条判断是 reg 还是 wire，收集所有名字"""
    regs, wires = set(), set()
    for stmt in t.split(';'):
        s = ' '.join(stmt.split())
        if not re.match(r'^(wire|reg|input|output)\b', s):
            continue
        is_reg = re.search(r'\breg\b', s) is not None
        body = re.sub(r'\b(wire|reg|input|output|signed|unsigned|integer)\b', ' ', s)
        body = re.sub(r'\[[^\]]*\]', ' ', body)     # 位宽
        body = re.sub(r'=[^,]*', ' ', body)         # 初值
        for nm in re.findall(r'[A-Za-z_]\w*', body):
            (regs if is_reg else wires).add(nm)
    return regs, wires


def always_body(t, start):
    depth = 0
    for m in re.finditer(r'\b(begin|end)\b', t[start:]):
        if m.group(1) == 'begin':
            depth += 1
        elif depth == 0:
            return t[start:start + m.start()]
        else:
            depth -= 1
    return t[start:]


def check(p):
    t = strip_comments(io.open(p, 'rb').read().decode('utf-8', errors='replace'))
    regs, wires = declarations(t)
    bad = set()
    for m in re.finditer(r'\balways\s*@\s*\([^)]*\)', t):
        body = always_body(t, m.end())
        for mm in re.finditer(r'\b([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*<=', body):
            tgt = mm.group(1)
            if tgt in wires and tgt not in regs:
                bad.add(tgt)
    return bad


def main():
    total = 0
    for f in FILES:
        p = os.path.join(H, f)
        if not os.path.isfile(p):
            print('  --   %s (不存在，跳过)' % f)
            continue
        bad = check(p)
        if bad:
            print('  FAIL %-26s 过程赋值给 wire: %s' % (f, sorted(bad)))
            total += len(bad)
        else:
            print('  OK   %s' % f)
    print()
    print('结论: ' + ('未发现 HDL-8007 类错误'
                     if total == 0 else '**发现 %d 处问题**' % total))
    return 0 if total == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main())
