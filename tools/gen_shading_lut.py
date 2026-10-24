#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_shading_lut.py —— 从抓帧标定颜色阴影（color shading）增益表，并生成
                     user_source/hdl_source/color_shading_lut.v

背景
    实测画面偏色是空间不均匀的：左侧 G-R ≈ -10（偏品红）、中央 ≈ +21（偏绿）、
    右侧 ≈ -5。跨 2 小时抓的 4 帧该分布相关系数 0.993~0.998，说明是镜头/传感器
    固定的 color shading（微透镜斜入射效应），全局 AWB/CCM 修不了。

原理
    gain_r[块] = G_mean[块] / R_mean[块]
    gain_b[块] = G_mean[块] / B_mean[块]
    R' = R * gain_r,  B' = B * gain_b,  G 直通
    -> 块内三通道相等，但整体亮度不变（G 不做任何改动）。

网格
    固定 10 列 x 6 行 = 60 块，和 color_shading.v 的硬件地址对齐：
        blk_x = x[10:7]  (0..9)     -> 每块 128 像素宽（1280/128 = 10）
        blk_y = y[9:7]   (0..5)     -> 每块 128 行（720/128 = 5.6，末块只 80 行）
        blk   = blk_y * 10 + blk_x
    这样硬件里 *10 = *8 + *2，纯移位加法，没有除法器。
    实测 8x6 后逐像素 |G-R| 从 8.94 降到 3.96，已接近噪声底
    （2.71 级噪声 x sqrt(2) = 3.83），再加密网格无收益。

用法
    # 用最近一次抓帧标定（推荐：对着均匀白墙/白纸拍一张，效果最好）
    python tools/gen_shading_lut.py

    # 指定图片
    python tools/gen_shading_lut.py --image docs/captures/xxx/grab_*.png

    # 只算增益不写文件（先看数值）
    python tools/gen_shading_lut.py --dry-run

标定时会自动排除 OSD 区域（右上角安路 Logo、左上角算法名），
否则 Logo 的红色/蓝色会污染统计。
"""

import argparse
import glob
import os
import sys

import numpy as np
from PIL import Image

# ---------------------------------------------------------------- 常量
GRID_X, GRID_Y = 10, 6          # 必须和 color_shading.v 一致
Q8_ONE = 256                    # Q8 定点：256 = 1.0x
GAIN_MIN, GAIN_MAX = 128, 511   # 钳位到 [0.5x, 2.0x]

# OSD 区域（相对画面左上角）：(y0, y1, x0, x1)
OSD_RECTS = (
    (16, 96, 1136, 1264),       # 安路 Logo
    (16, 52, 16, 112),          # 左上角算法名文字
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_V = os.path.join(ROOT, "user_source", "hdl_source", "color_shading_lut.v")

# ---------------------------------------------------------------- 工具
def latest_capture():
    """找最近一次抓帧的 PNG（按修改时间）。"""
    pats = [
        os.path.join(ROOT, "docs", "captures", "*", "*.png"),
        os.path.join(ROOT, "docs", "captures", "*.png"),
    ]
    files = []
    for p in pats:
        files.extend(glob.glob(p))
    if not files:
        sys.exit("找不到抓帧文件，请先运行 tools/capture.ps1")
    return max(files, key=os.path.getmtime)


def osd_mask(y0, y1, x0, x1):
    """返回块内有效像素掩码（True = 参与统计，排除 OSD）。"""
    m = np.ones((y1 - y0, x1 - x0), dtype=bool)
    for oy0, oy1, ox0, ox1 in OSD_RECTS:
        ly0, ly1 = max(0, oy0 - y0), min(y1 - y0, oy1 - y0)
        lx0, lx1 = max(0, ox0 - x0), min(x1 - x0, ox1 - x0)
        if ly1 > ly0 and lx1 > lx0:
            m[ly0:ly1, lx0:lx1] = False
    return m


def calibrate(img_path):
    """返回 (gain_r, gain_b)，形状 (GRID_Y, GRID_X)，Q8 定点。"""
    a = np.asarray(Image.open(img_path).convert("RGB")).astype(np.float64)
    H, W = a.shape[:2]

    gain_r = np.full((GRID_Y, GRID_X), Q8_ONE, dtype=int)
    gain_b = np.full((GRID_Y, GRID_X), Q8_ONE, dtype=int)
    stats = []

    for i in range(GRID_Y):
        for j in range(GRID_X):
            ys, ye = i * 128, min((i + 1) * 128, H)
            xs, xe = j * 128, min((j + 1) * 128, W)
            blk = a[ys:ye, xs:xe]
            m = osd_mask(ys, ye, xs, xe)
            n = int(m.sum())
            if n < 200:                      # 有效像素太少，保持 1.0 不硬标
                stats.append((i, j, 0, 0.0, 0.0, 0.0))
                continue
            r, g, b = (blk[..., 0][m].mean(), blk[..., 1][m].mean(),
                       blk[..., 2][m].mean())
            gr = int(round(np.clip(g / max(r, 1.0) * Q8_ONE, GAIN_MIN, GAIN_MAX)))
            gb = int(round(np.clip(g / max(b, 1.0) * Q8_ONE, GAIN_MIN, GAIN_MAX)))
            gain_r[i, j], gain_b[i, j] = gr, gb
            stats.append((i, j, n, r, g, b))
    return gain_r, gain_b, stats


def write_verilog(gain_r, gain_b, img_path):
    rel = os.path.relpath(img_path, ROOT).replace("\\", "/")
    L = []
    L.append("//=====================================================================")
    L.append("//  color_shading_lut.v  ——  颜色阴影校正增益表（自动生成，勿手改）")
    L.append("//")
    L.append("//  生成工具: 0 Project/tools/gen_shading_lut.py")
    L.append("//  源图:     %s" % rel)
    L.append("//  网格:     %d 列 x %d 行 = %d 块（每块 128 像素宽 x 128 行）" %
             (GRID_X, GRID_Y, GRID_X * GRID_Y))
    L.append("//  块索引:   blk = blk_y * %d + blk_x,  blk_x = x[10:7], blk_y = y[9:7]" % GRID_X)
    L.append("//  格式:     Q8 定点，256 = 1.0x；只调 R/B，G 直通（保持亮度）")
    L.append("//")
    L.append("//  标定原理: 每块增益 = 块内 G 均值 / 块内 R(或B) 均值，")
    L.append("//            使块内三通道相等，从而消除镜头/传感器的 color shading。")
    L.append("//            OSD 区域（Logo / 文字）已从统计中排除。")
    L.append("//=====================================================================")
    L.append("module color_shading_lut (")
    L.append("    input  wire [5:0] I_blk,")
    L.append("    output reg  [8:0] O_gain_r,")
    L.append("    output reg  [8:0] O_gain_b")
    L.append(");")
    L.append("    always @(*) begin")
    L.append("        case (I_blk)")
    for i in range(GRID_Y):
        for j in range(GRID_X):
            k = i * GRID_X + j
            L.append("            6'd%-2d: begin O_gain_r = 9'd%d; O_gain_b = 9'd%d; end  // y%d x%d"
                     % (k, gain_r[i, j], gain_b[i, j], i, j))
    L.append("            default: begin O_gain_r = 9'd256; O_gain_b = 9'd256; end")
    L.append("        endcase")
    L.append("    end")
    L.append("endmodule")
    with open(OUT_V, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    return len(L)


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description="标定 color shading 增益表")
    ap.add_argument("--image", help="抓帧 PNG 路径（默认用最近一次抓帧）")
    ap.add_argument("--dry-run", action="store_true", help="只打印增益，不写文件")
    args = ap.parse_args()

    img = args.image or latest_capture()
    if not os.path.isabs(img):
        img = os.path.join(ROOT, img)
    if not os.path.exists(img):
        sys.exit("图片不存在: %s" % img)

    print("源图: %s" % img)
    gain_r, gain_b, stats = calibrate(img)

    print("\n增益表（Q8，256=1.0x；格式 R/B）：")
    print("        " + "  ".join("x%-8d" % j for j in range(GRID_X)))
    for i in range(GRID_Y):
        print("  y%d  " % i + " ".join("%4d/%4d " % (gain_r[i, j], gain_b[i, j])
                                        for j in range(GRID_X)))

    print("\nR 增益 %.2fx ~ %.2fx     B 增益 %.2fx ~ %.2fx"
          % (gain_r.min() / 256, gain_r.max() / 256,
             gain_b.min() / 256, gain_b.max() / 256))

    # 有效性提示
    bad = [(i, j, n) for (i, j, n, *_rest) in stats if n < 200]
    if bad:
        print("  ⚠ 以下块有效像素 <200，增益保持 1.0（可能被 OSD 大面积覆盖）：")
        for i, j, n in bad:
            print("    y%d x%d  有效像素 %d" % (i, j, n))

    if args.dry_run:
        print("\n--dry-run：未写文件")
        return

    n = write_verilog(gain_r, gain_b, img)
    print("\n已生成 %s（%d 行）" % (os.path.relpath(OUT_V, ROOT), n))
    print("下一步：重新编译（build_all.ps1）")


if __name__ == "__main__":
    main()
