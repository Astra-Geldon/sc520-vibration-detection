# -*- coding: utf-8 -*-
"""检查：同一文件里是否有对同一 net/reg 的重复声明（我刚犯过的错）"""
import io
import os
import re
from collections import defaultdict

H = (r'D:\workplace\lab_ex1_mipi_hdmi_SC520 (2)\lab_ex1_mipi_hdmi_SC520'
     r'\lab_ex1_mipi_hdmi\user_source\hdl_source')

FILES = ['vib_lk_grid.v', 'vib_prev_frame_ddr.v', 'vib_gauss3x3.v',
         'design_top_wrapper.v', 'uart_log_debug.v',
         r'vibration\vib_video_tap.v', r'vibration\vib_ddr_arb.v',
         r'vibration\vib_ddr_selftest.v', 'clk_pixel_meter.v']


def strip_comments(t):
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', t)


def check(p):
    t = strip_comments(io.open(p, 'rb').read().decode('utf-8', errors='replace'))
    probs = {}
    for m in re.finditer(r'^\s*module\s+(\w+)(.*?)^\s*endmodule', t, re.S | re.M):
        mod, body = m.group(1), m.group(2)
        seen = defaultdict(list)
        for st in body.split(';'):
            s = ' '.join(st.split())
            if not re.match(r'^(input|output|wire|reg)\b', s):
                continue
            head = re.match(r'^((?:input|output|wire|reg)\s+(?:reg\s+|wire\s+)?'
                            r'(?:signed\s+)?(?:\[[^\]]*\])?)\s*(.*)$', s)
            if not head:
                continue
            for nm in re.findall(r'[A-Za-z_]\w*',
                                 re.sub(r'\[[^\]]*\]', ' ', head.group(2).split('=')[0])):
                seen[nm].append(s[:60])
        for nm, decls in seen.items():
            if len(decls) > 1:
                probs['%s.%s' % (mod, nm)] = len(decls)
    return probs


def main():
    total = 0
    for f in FILES:
        p = os.path.join(H, f)
        if not os.path.isfile(p):
            continue
        bad = check(p)
        if bad:
            print('  FAIL %-26s 重复声明: %s' % (f, ', '.join(sorted(bad))))
            total += len(bad)
        else:
            print('  OK   %s' % f)
    print()
    print('结论: ' + ('未发现重复声明' if total == 0 else '**%d 处重复声明**' % total))
    return 0 if total == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main())
