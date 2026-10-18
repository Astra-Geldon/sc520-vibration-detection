# -*- coding: utf-8 -*-
"""编译前总检查：结构 / 例化 / wire 过程赋值 / 日志字段顺序"""
import io
import os
import re

H = (r'D:\workplace\lab_ex1_mipi_hdmi_SC520 (2)\lab_ex1_mipi_hdmi_SC520'
     r'\lab_ex1_mipi_hdmi\user_source\hdl_source')


def nc(t):
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', t)


def struct(f):
    p = os.path.join(H, f)
    c = nc(io.open(p, 'rb').read().decode('utf-8'))
    pr = []
    for a, b in [('begin', 'end'), ('function', 'endfunction')]:
        na = len(re.findall(r'\b%s\b' % a, c))
        nb = len(re.findall(r'\b%s\b' % b, c))
        if na != nb:
            pr.append('%s/%s=%d/%d' % (a, b, na, nb))
    if len(re.findall(r'^\s*module\s+\w+', c, re.M)) != len(re.findall(r'\bendmodule\b', c)):
        pr.append('module')
    a1 = len(re.findall(r'\bcase\b', c))
    b1 = len(re.findall(r'\bendcase\b', c))
    if a1 != b1:
        pr.append('case=%d/%d' % (a1, b1))
    for o, cl in [('(', ')'), ('{', '}'), ('[', ']')]:
        if c.count(o) != c.count(cl):
            pr.append('%s%s=%d/%d' % (o, cl, c.count(o), c.count(cl)))
    print(('  FAIL ' if pr else '  OK   ') + f + ('  ' + str(pr) if pr else ''))


print('=== 结构平衡 ===')
for f in ['uart_log_debug.v', 'design_top_wrapper.v', 'vib_lk_grid.v']:
    struct(f)

u = nc(io.open(os.path.join(H, 'uart_log_debug.v'), 'rb').read().decode('utf-8'))
print()
print('  fld 纯计数(防 FSM 崩溃):',
      'OK' if re.search(r'fld\s*<=\s*fld \+ 1', u) else '**异常**')
nf = re.search(r"NF\s*=\s*(\d+)", u).group(1)
print('  NF =', nf)

print()
print('=== 日志字段顺序 ===')
pairs = re.findall(r"\d+'d(\d+)\s*:\s*s\s*=\s*\"([A-Z0-9]+)\"", u)
for n, l in sorted((int(a), b) for a, b in pairs):
    print('   %2d  %s' % (n, l))
print('   共 %d 个' % len(pairs))

top = nc(io.open(os.path.join(H, 'design_top_wrapper.v'), 'rb').read().decode('utf-8'))
print()
print('=== 顶层接线 ===')
for port in ['lk_dbg_r0', 'lk_dbg_r1', 'lk_dbg_r2', 'lk_dbg_r3', 'lk_dbg_r4', 'lk_dbg_dix']:
    a = len(re.findall(r'\.st_dbg_%s\s*\(' % port.replace('lk_dbg_', ''), top))
    b = len(re.findall(r'\.%s\s*\(' % port, top))
    print('  %-12s LK侧=%d 串口侧=%d %s' % (port, a, b, 'OK' if a == 1 and b == 1 else '**检查**'))
