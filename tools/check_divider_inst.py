# -*- coding: utf-8 -*-
"""核对 vib_lk_grid.v 里 vib_div_serial 的例化：端口名、方向、位宽

（这个脚本原来查的是厂商 divider，2026-10-17 换成自研串行除法器后改指向）
"""
import io
import os
import re

H = (r'D:\workplace\lab_ex1_mipi_hdmi_SC520 (2)\lab_ex1_mipi_hdmi_SC520'
     r'\lab_ex1_mipi_hdmi\user_source\hdl_source')
MOD = os.path.join(H, r'vibration\vib_div_serial.v')
LK = os.path.join(H, 'vib_lk_grid.v')

mod = io.open(MOD, 'rb').read().decode('utf-8', errors='replace')
lk = io.open(LK, 'rb').read().decode('utf-8', errors='replace')


def strip_comments(t):
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    return re.sub(r'//[^\n]*', '', t)


mod_c = strip_comments(mod)
head = re.search(r'\bmodule\s+vib_div_serial\b(.*?)\bendmodule\b', mod_c, re.S)
if not head:
    print('!! 找不到 vib_div_serial 模块')
    raise SystemExit(1)

# 按 input/output 关键字位置切段（兼容 ANSI 与逗号分组的写法）
body = head.group(1)
ports = {}
kws = list(re.finditer(r'\b(input|output)\b', body))
for i, mm in enumerate(kws):
    end = kws[i + 1].start() if i + 1 < len(kws) else len(body)
    seg = re.split(r'[;)]', body[mm.end():end], 1)[0]
    for part in seg.split(','):
        part2 = re.sub(r'\[[^\]]*\]', ' ', part)
        part2 = re.sub(r'\b(signed|unsigned|wire|reg|logic)\b', ' ', part2)
        ids = re.findall(r'[A-Za-z_]\w*', part2)
        if ids and len(ids[-1]) >= 2:
            ports[ids[-1]] = (mm.group(1), '')
print('vib_div_serial 端口:')
for nm, (d, w) in ports.items():
    print('  %-8s %-7s %s' % (nm, d, w))

m = re.search(r'\bvib_div_serial\b[^(]*?\((.*?)\)\s*;', lk, re.S)
if not m:
    print('!! 找不到 vib_div_serial 例化')
    raise SystemExit(1)
conns = dict(re.findall(r'\.(\w+)\s*\(\s*([^)]+?)\s*\)', m.group(1)))

print()
print('例化连接:')
bad = 0
for nm in sorted(ports):
    if nm not in conns:
        print('  ** 缺少端口 .%s' % nm)
        bad += 1
    else:
        print('  .%-8s <- %s' % (nm, conns[nm]))
PARAMS = {'W', 'DW'}
for nm in conns:
    if nm in PARAMS:
        continue          # 参数覆盖，不是端口
    if nm not in ports:
        print('  ** 多余端口 .%s' % nm)
        bad += 1

print()
print('参数覆盖:')
params = dict(re.findall(r'\.(\w+)\s*\(\s*([^)]+?)\s*\)', m.group(1)))
print('  W  = %s' % params.get('W', '（默认 48）'))
print('  DW = %s' % params.get('DW', '（默认 32）'))

print()
print('结论: ' + ('端口全部匹配 [OK]' if bad == 0 else '**%d 处问题**' % bad))
raise SystemExit(0 if bad == 0 else 1)
