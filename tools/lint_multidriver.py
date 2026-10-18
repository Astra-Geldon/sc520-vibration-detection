# -*- coding: utf-8 -*-
"""
检查：同一个信号是否在多个 always 块里被赋值（TD 报
  "net 'x' is constantly driven from multiple places"）。

这类错误通常是补丁插错了 always 块造成的，很隐蔽。
"""
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


def always_spans(t):
    """返回每个 always 块的 (起, 止) 字符区间"""
    spans = []
    for m in re.finditer(r'\balways\s*@\s*\([^)]*\)', t):
        start = m.end()
        # 找块尾：直到配对的 end（无 begin 时取到下一条 ';'）
        rest = t[start:]
        if not re.match(r'\s*begin\b', rest):
            semi = rest.find(';')
            spans.append((start, start + (semi if semi >= 0 else len(rest))))
            continue
        depth = 0
        end = len(t)
        for mm in re.finditer(r'\b(begin|end)\b', rest):
            if mm.group(1) == 'begin':
                depth += 1
            else:
                depth -= 1
                if depth == 0:
                    end = start + mm.end()
                    break
        spans.append((start, end))
    return spans


def check(p):
    t = strip_comments(io.open(p, 'rb').read().decode('utf-8', errors='replace'))
    # ★ 必须按 module 分域：不同模块里的同名局部变量不算多驱动
    allbad = {}
    nblk_total = 0
    for mm in re.finditer(r'^\s*module\s+(\w+)(.*?)^\s*endmodule',
                          t, re.S | re.M):
        mod, body = mm.group(1), mm.group(2)
        spans = always_spans(body)
        nblk_total += len(spans)
        drivers = defaultdict(set)
        for bi, (a, b) in enumerate(spans):
            seg = body[a:b]
            for m2 in re.finditer(r'\b([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*<=', seg):
                drivers[m2.group(1)].add(bi)
        for k, v in drivers.items():
            if len(v) > 1:
                allbad['%s.%s' % (mod, k)] = v
    return allbad, nblk_total


def main():
    total = 0
    for f in FILES:
        p = os.path.join(H, f)
        if not os.path.isfile(p):
            continue
        bad, nblk = check(p)
        if bad:
            print('  FAIL %-26s %d 个 always 块, 多驱动: %s'
                  % (f, nblk, ', '.join(sorted(bad))))
            total += len(bad)
        else:
            print('  OK   %-26s (%d 个 always 块)' % (f, nblk))
    print()
    print('结论: ' + ('未发现多驱动' if total == 0 else '**%d 个信号多驱动**' % total))
    return 0 if total == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main())
