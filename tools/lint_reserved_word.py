# -*- coding: utf-8 -*-
"""
lint_reserved_word.py —— 禁止用 Verilog 保留字当信号名

为什么需要：
    vib_osd_marker.v 里写了 `wire edge = ...`，而 **edge 是 Verilog-2000
    的保留字**（posedge/negedge 用的就是它），TD 直接报
        ERROR: Verilog 2000 keyword 'edge' used in incorrect context
    连带 `frm`（依赖 edge）也被判未声明。一次编译就白费了。

检查内容：
    提取 wire/reg/input/output/inout/integer 声明里的**标识符**，
    若与保留字表冲突则报警。
    注意：`signed` / `unsigned` 是修饰符，出现在类型位置，不算标识符。
"""
import io
import os
import re
import sys

ROOT = (r'D:\workplace\lab_ex1_mipi_hdmi_SC520 (2)\lab_ex1_mipi_hdmi_SC520'
        r'\lab_ex1_mipi_hdmi\user_source\hdl_source')

RESERVED = set("""
always and assign automatic begin buf bufif0 bufif1 case casex casez cell cmos
config deassign default defparam design disable edge else end endcase endconfig
endfunction endgenerate endmodule endprimitive endspecify endtable endtask event
for force forever fork function generate genvar highz0 highz1 if ifnone incdir
include initial inout input instance integer join large liblist library
localparam macromodule medium module nand negedge nmos nor noshowcancelled not
notif0 notif1 or output parameter pmos posedge primitive pull0 pull1 pulldown
pullup pulsestyle_onevent pulsestyle_ondetect rcmos real realtime reg release
repeat rnmos rpmos rtran rtranif0 rtranif1 scalared showcancelled signed small
specify specparam strong0 strong1 supply0 supply1 table task time tran tranif0
tranif1 tri tri0 tri1 triand trior trireg unsigned use uwire vectored wait wand
weak0 weak1 while wire wor xnor xor
""".split())

DECL = re.compile(r'^\s*(?:input|output|inout)\s+(?:wire|reg|logic)?\s*'
                  r'(?:signed|unsigned)?\s*(?:\[[^\]]*\]\s*)?([^;,)]+)'
                  r'|^\s*(?:wire|reg|integer)\s+(?:signed|unsigned)?\s*'
                  r'(?:\[[^\]]*\]\s*)?([^;]+)', re.M)


def strip_comments(t):
    t = re.sub(r'/\*.*?\*/', ' ', t, flags=re.S)
    return re.sub(r'//[^\n]*', '', t)


def scan(path):
    raw = io.open(path, 'rb').read().decode('utf-8', errors='replace')
    t = strip_comments(raw)
    bad = []
    for lineno, line in enumerate(t.splitlines(), 1):
        s = line.strip()
        if not re.match(r'^(input|output|inout|wire|reg|integer)\b', s):
            continue
        m = DECL.match(line + '\n')
        if not m:
            continue
        body = m.group(1) or m.group(2) or ''
        for part in body.split(','):
            part = re.sub(r'\[[^\]]*\]', ' ', part)      # 去掉位宽
            part = re.sub(r'=(.*)$', ' ', part)          # 去掉初值
            ids = re.findall(r'[A-Za-z_]\w*', part)
            # 去掉类型修饰符（它们是关键字但用法合法）
            ids = [i for i in ids if i not in ('signed', 'unsigned', 'wire',
                                               'reg', 'integer', 'logic')]
            for nm in ids:
                if nm in RESERVED:
                    bad.append((lineno, nm, line.strip()))
    return bad


def main():
    files = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        for fn in filenames:
            if fn.endswith('.v'):
                files.append(os.path.join(dirpath, fn))
    mine = [f for f in files if ('vibration' in f
                                 or os.path.basename(f).startswith('vib_')
                                 or os.path.basename(f) == 'design_top_wrapper.v'
                                 or os.path.basename(f) == 'uart_log_debug.v')]

    total = 0
    for f in sorted(mine):
        for lineno, nm, line in scan(f):
            print('  %s:%d  保留字 %s -> %s'
                  % (os.path.basename(f), lineno, nm, line))
            total += 1

    print()
    if total:
        print('结论: **%d 处用保留字当信号名**，TD 会报 '
              '"keyword ... used in incorrect context"' % total)
        return 1
    print('结论: 未发现用保留字当信号名 [OK]')
    return 0


if __name__ == '__main__':
    sys.exit(main())
