#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_osd_assets.py -- 生成 OSD 用的两份点阵 ROM

  1) osd_logo_rom.v   安路 Logo，128x80，2bit/像素，640 条 case 的 LUT ROM
  2) osd_font_rom.v   16x16 汉字点阵，每个字 16 行，case ROM

用法（在 0 Project 目录下）：
    python tools/gen_osd_assets.py

★ 新增算法文字：只改下面的 CHARS（**只能往后追加，不能重排**），然后重跑本脚本，
  再按 docs/算法添加方法.md 第 2 步在 osd_overlay.v 里登记起始字形序号。

依赖：Pillow；Windows 自带宋体（simsun.ttc）。
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------- 配置
HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)                       # 0 Project
OUT = os.path.join(PROJ, "user_source", "hdl_source")

# Logo 源图：厂商资料里的 640x480 官方 ANLOGIC Logo
LOGO_SRC = os.path.join(
    os.path.dirname(PROJ),
    "0 准备", "HX1P35A_Contest_202606", "5_软件工具及驱动",
    "lab_ex_2025_7_12_nosoft", "HX4S20C_lab_ex", "lab_ex_3_tf_sdram_vga",
    "图片", "logo.bmp",
)

LOGO_W, LOGO_H = 128, 80          # OSD 上显示的 Logo 尺寸
WPD = 16                          # 每个 32bit word 装几个像素（2bit/px）

# ★ 字形表：顺序编号，只能追加
CHARS = "原图灰度二值化边缘"

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\simsun.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
    r"C:\Windows\Fonts\msyh.ttc",
]
GLYPH_PX = 15                     # 字号（16x16 单元格，留 1px 边）
GLYPH_TH = 110                    # 二值化阈值


def gen_logo():
    if not os.path.exists(LOGO_SRC):
        print("!! 找不到 Logo 源图：", LOGO_SRC)
        print("   跳过 Logo 生成（osd_logo_rom.v 保持原样）")
        return False

    im = Image.open(LOGO_SRC).convert("RGB")
    a = np.asarray(im).astype(np.int32)
    # 自动裁掉白边
    mask = ~((a[..., 0] > 235) & (a[..., 1] > 235) & (a[..., 2] > 235))
    ys, xs = np.where(mask)
    crop = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

    c = np.asarray(crop.resize((LOGO_W, LOGO_H), Image.LANCZOS)).astype(np.int32)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    px = np.zeros((LOGO_H, LOGO_W), dtype=np.uint8)
    px[(r < 110) & (g < 110) & (b > 60)] = 1        # 深蓝
    px[(r > 140) & (g < 120) & (b < 120)] = 2       # 红

    words_per_row = LOGO_W // WPD
    L = []
    L.append("//=====================================================================")
    L.append("//  osd_logo_rom.v  ——  ANLOGIC 安路 Logo 点阵 ROM（自动生成，勿手改）")
    L.append("//")
    L.append("//  生成脚本：tools/gen_osd_assets.py")
    L.append("//  尺寸    ：%d x %d，2 bit/像素  0=透明 1=深蓝(1B3A66) 2=红(E8382F)" % (LOGO_W, LOGO_H))
    L.append("//  存储    ：每 32 bit word 装 %d 个像素，每行 %d 个 word" % (WPD, words_per_row))
    L.append("//  地址    ：{ row[6:0], word[2:0] } = 10 bit")
    L.append("//")
    L.append("//  ★ 不用 EG_LOGIC_BRAM：纯 Verilog 工程里它是黑盒（需要 TD 的 IP 生成器")
    L.append("//    元数据）。这里用 LUT ROM，约 300 个 LUT，零依赖。")
    L.append("//=====================================================================")
    L.append("module osd_logo_rom (")
    L.append("    input  wire [9:0]  I_addr,")
    L.append("    output reg  [31:0] O_word")
    L.append(");")
    L.append("    always @(*) begin")
    L.append("        case (I_addr)")
    for y in range(LOGO_H):
        for w in range(words_per_row):
            v = 0
            for k in range(WPD):
                v |= (int(px[y, w * WPD + k]) & 3) << (2 * (WPD - 1 - k))
            L.append("            10'd%d : O_word = 32'h%08X;" % (y * words_per_row + w, v))
    L.append("            default: O_word = 32'h00000000;")
    L.append("        endcase")
    L.append("    end")
    L.append("endmodule")
    path = os.path.join(OUT, "osd_logo_rom.v")
    with open(path, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print("已生成 %s  (%d 条 case, 深蓝 %d 像素, 红 %d 像素)"
          % (path, LOGO_H * words_per_row, (px == 1).sum(), (px == 2).sum()))
    return True


def gen_font():
    font = None
    for cand in FONT_CANDIDATES:
        if os.path.exists(cand):
            try:
                font = ImageFont.truetype(cand, GLYPH_PX)
                print("字体:", cand)
                break
            except Exception as exc:      # noqa: BLE001
                print("跳过", cand, exc)
    if font is None:
        print("!! 没找到中文 TrueType 字体，跳过字体生成")
        return False

    glyphs = []
    for ch in CHARS:
        img = Image.new("L", (16, 16), 0)
        d = ImageDraw.Draw(img)
        box = d.textbbox((0, 0), ch, font=font)
        w, h = box[2] - box[0], box[3] - box[1]
        d.text(((16 - w) // 2 - box[0], (16 - h) // 2 - box[1]), ch, fill=255, font=font)
        bits = np.asarray(img) > GLYPH_TH
        rows = []
        for yy in range(16):
            v = 0
            for xx in range(16):
                if bits[yy, xx]:
                    v |= 1 << (15 - xx)
            rows.append(v)
        glyphs.append(rows)

    L = []
    L.append("//=====================================================================")
    L.append("//  osd_font_rom.v  ——  16x16 汉字点阵 ROM（自动生成，勿手改）")
    L.append("//")
    L.append("//  生成脚本：tools/gen_osd_assets.py")
    L.append("//  字符表  ：%s" % CHARS)
    L.append("//  地址    ：{字形序号[3:0], 行号[3:0]}，每行 16 bit（bit15 = 最左像素）")
    L.append("//")
    L.append("//  ★ 新增算法文字：在 CHARS 里**追加**汉字 -> 重跑生成脚本 -> 重新编译")
    L.append("//=====================================================================")
    L.append("module osd_font_rom (")
    L.append("    input  wire [7:0]  I_addr,")
    L.append("    output reg  [15:0] O_row")
    L.append(");")
    L.append("    always @(*) begin")
    L.append("        case (I_addr)")
    for gi, rows in enumerate(glyphs):
        for ri, v in enumerate(rows):
            L.append("            8'd%d : O_row = 16'h%04X;   // %s 第 %d 行"
                     % (gi * 16 + ri, v, CHARS[gi], ri))
    L.append("            default: O_row = 16'h0000;")
    L.append("        endcase")
    L.append("    end")
    L.append("endmodule")
    path = os.path.join(OUT, "osd_font_rom.v")
    with open(path, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print("已生成 %s  (%d 个字)" % (path, len(glyphs)))
    return True


def main():
    ok_logo = gen_logo()
    ok_font = gen_font()
    if not (ok_logo and ok_font):
        print("\n部分资源未生成，请检查上面的提示。")
        return 1
    print("\n完成。记得重新编译：td_project\\patch\\build_all.ps1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
