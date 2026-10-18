# -*- coding: utf-8 -*-
"""导出生成器里当前启用的字段顺序"""
import io
import re

t = io.open('gen_uart_log2.py', 'rb').read().decode('utf-8')
m = re.search(r'^FIELDS\s*=\s*\[(.*?)^\]', t, re.S | re.M)
out = []
for line in m.group(0).splitlines():
    mm = re.match(r'\s*\(\s*"([^"]*)"', line)
    if mm:
        out.append(mm.group(1).strip())
with io.open('_on.txt', 'wb') as f:
    f.write(('\n'.join('%2d  %s' % (i, x) for i, x in enumerate(out))).encode('utf-8'))
print(len(out))
