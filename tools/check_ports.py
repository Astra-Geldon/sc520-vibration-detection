# -*- coding: utf-8 -*-
"""
双向端口比对：顶层例化的端口名集合必须与模块定义的端口名集合完全一致。

为什么需要它：改字段/改模块端口后忘了同步另一侧，是最容易漏的一类错误。
之前 LKPA/LKPB、LKAE/LKAF、删 LKBA~LKBE 都出过同一问题。
（本检查只看"端口名集合"，位宽由 check_all_inst / check_divider_inst 负责）
"""
import io
import os
import re
import sys

H = (r'D:\workplace\lab_ex1_mipi_hdmi_SC520 (2)\lab_ex1_mipi_hdmi_SC520'
     r'\lab_ex1_mipi_hdmi\user_source\hdl_source')
TOP = os.path.join(H, 'design_top_wrapper.v')

# 需要检查的 模块名 -> 定义文件
PAIRS = [
    ('uart_log_debug',    os.path.join(H, 'uart_log_debug.v')),
    ('vib_lk_grid',       os.path.join(H, 'vib_lk_grid.v')),
    ('vib_lk_solve',      os.path.join(H, 'vib_lk_grid.v')),
    ('vib_prev_frame_ddr', os.path.join(H, 'vib_prev_frame_ddr.v')),
    ('vib_gauss3x3',      os.path.join(H, 'vib_gauss3x3.v')),
]


def strip_comments(t):
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', t)


def module_ports(path, modname):
    if not os.path.isfile(path):
        return None
    t = strip_comments(io.open(path, 'rb').read().decode('utf-8', errors='replace'))
    m = re.search(r'\bmodule\s+%s\b(.*?)\bendmodule\b' % re.escape(modname), t, re.S)
    if not m:
        return None
    body = m.group(1)
    ports = set()
    # 按 input/output/inout 关键字的位置切段：每段从关键字后到下一个关键字为止。
    # 不用固定窗口长度，避免把标识符截断成垃圾 token。
    kws = list(re.finditer(r'\b(?:input|output|inout)\b', body))
    for i, mm in enumerate(kws):
        end = kws[i + 1].start() if i + 1 < len(kws) else len(body)
        seg = body[mm.end():end]
        seg = re.split(r'[;)]', seg, 1)[0]
        for part in seg.split(','):
            part = re.sub(r'\[[^\]]*\]', ' ', part)
            part = re.sub(r'\b(signed|unsigned|wire|reg|logic)\b', ' ', part)
            ids = re.findall(r'[A-Za-z_]\w*', part)
            # 单字符标识符是 ANSI 头部里的位宽/宏残留（本工程没有单字符端口）
            if ids and len(ids[-1]) >= 2:
                ports.add(ids[-1])
    return ports or None


top = strip_comments(io.open(TOP, 'rb').read().decode('utf-8', errors='replace'))
bad = 0

for mod, defpath in PAIRS:
    insts = re.findall(r'\b%s\b\s*(?:#\s*\([^;]*?\)\s*)?(\w+)\s*\((.*?)\);' % re.escape(mod), top, re.S)
    if not insts:
        print('  --   %-20s 顶层未例化' % mod)
        continue
    want = module_ports(defpath, mod)
    if want is None:
        print('  ??   %-20s 找不到模块定义（%s）' % (mod, os.path.basename(defpath)))
        continue
    for instname, body in insts:
        allc = re.findall(r'\.(\w+)\s*\(', body)
        dup = sorted(set(nm for nm in allc if allc.count(nm) > 1))
        got = set(allc)
        miss = want - got
        extra = got - want
        if not miss and not extra and not dup:
            print('  OK   %-20s (%-24s) %d 端口全匹配' % (mod, instname, len(want)))
        elif dup and not miss and not extra:
            bad += 1
            print('  FAIL %-20s (%-24s)' % (mod, instname))
            print('         **端口被重复连接: %s**' % ', '.join(dup))
        else:
            bad += 1
            print('  FAIL %-20s (%-24s)' % (mod, instname))
            if miss:
                print('         缺少连接: %s' % ', '.join(sorted(miss)))
            if extra:
                print('         **多余连接（模块里没这个端口）: %s**'
                      % ', '.join(sorted(extra)))

print()
print('结论: ' + ('双向端口全部一致 [OK]' if bad == 0 else '**%d 个例化有端口不一致**' % bad))
sys.exit(0 if bad == 0 else 1)
