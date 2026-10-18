# -*- coding: utf-8 -*-
"""
lint_signed_select.py —— 禁止对 signed 矢量做 part-select

为什么需要这条 lint：
    IEEE 1364-2001 规定 **part-select（a[i:j]）是无符号的**，即使 a 声明成
    signed。于是 `wire signed [63:0] mul = ...; mul[47:0] >>> 14` 会变成
    逻辑右移、`mul[47:0] * x` 会变成无符号乘法 —— 负数的符号位被当成数据位。

    这个坑已经咬了三次（每次 Python 模型都抓不到，因为 Python 用真符号整数）：
      · vib_div_serial   ：计数器先增后判，少跑一拍
      · vib_goertzel     ：cs1/p_cs12 的 part-select 丢符号
      · vib_lk_grid      ：acc_en[k][14:7] 存储器字再位选

    所以用静态检查挡住，而不是靠记性。

检查内容：
    扫描所有 .v 文件，找出形如 `信号名[高位:低位]` 的表达式，
    且该信号在同一文件里被声明为 signed，且不是声明语句本身。
"""
import io
import os
import re
import sys

ROOT = (r'D:\workplace\lab_ex1_mipi_hdmi_SC520 (2)\lab_ex1_mipi_hdmi_SC520'
        r'\lab_ex1_mipi_hdmi\user_source\hdl_source')


def strip_comments(t):
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    return re.sub(r'//[^\n]*', '', t)


def collect_signed(t):
    """收集本文件里声明为 signed 的信号名"""
    names = set()
    # wire/reg signed [..] a, b, c;
    for m in re.finditer(r'\b(?:wire|reg|output|input)\s+(?:wire\s+|reg\s+)?signed\s+'
                         r'(?:\[[^\]]*\]\s*)?([^;:]+);', t):
        body = m.group(1)
        for part in body.split(','):
            part = re.sub(r'\[[^\]]*\]', ' ', part)
            for nm in re.findall(r'[A-Za-z_]\w*', part):
                names.add(nm)
    return names


def scan(path):
    raw = io.open(path, 'rb').read().decode('utf-8', errors='replace')
    t = strip_comments(raw)
    signed = collect_signed(t)
    hits = []

    raw_lines = raw.splitlines()
    for lineno, line in enumerate(t.splitlines(), 1):
        s = line.strip()
        # LINT-OK 要查**原始行**（去注释之前）
        rawline = raw_lines[lineno-1] if lineno <= len(raw_lines) else ''
        # 跳过声明语句
        if re.match(r'^(wire|reg|input|output|localparam|parameter|integer|function|task)\b', s):
            continue
        if 'LINT-OK' in rawline:
            continue
        # 找 name[hi:lo]
        for m in re.finditer(r'([A-Za-z_]\w*)\s*\[\s*[^]:\]]+\s*:\s*[^]:\]]+\s*\]', line):
            nm = m.group(1)
            if nm in signed:
                hits.append((lineno, nm, line.strip()))
    return hits


def main():
    files = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        for fn in filenames:
            if fn.endswith('.v'):
                files.append(os.path.join(dirpath, fn))

    # 只查我写的文件（厂商 IP / ISP 目录跳过）
    mine = [f for f in files if ('vibration' in f
                                 or f.endswith('design_top_wrapper.v')
                                 or f.endswith('vib_lk_grid.v')
                                 or f.endswith('vib_gauss3x3.v')
                                 or f.endswith('vib_prev_frame_ddr.v')
                                 or f.endswith('uart_log_debug.v'))]

    total = 0
    for f in sorted(mine):
        hits = scan(f)
        if hits:
            print('  %s' % os.path.relpath(f, ROOT))
            for lineno, nm, line in hits[:10]:
                print('    %4d: signed 信号 %s 被 part-select -> %s' % (lineno, nm, line))
            total += len(hits)

    print()
    if total:
        print('结论: **发现 %d 处 signed part-select**，会丢符号，必须改成'
              '「声明成恰好需要的位宽再全名引用」' % total)
        return 1
    print('结论: 未发现 signed 矢量的 part-select [OK]')
    return 0


if __name__ == '__main__':
    sys.exit(main())
