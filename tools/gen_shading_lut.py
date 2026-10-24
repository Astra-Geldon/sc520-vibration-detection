#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_shading_lut.py —— 从抓帧标定颜色阴影（color shading）增益表，并生成
                     user_source/hdl_source/color_shading_lut.v

注意：这个脚本保留给历史10x1表格式。当前2段×10列的多场景归一化
候选表请使用同目录的gen_shading_lut_multiscene.py，避免生成格式不匹配的RTL。

背景
    实测画面偏色是空间不均匀的：左侧 G-R ≈ -10（偏品红）、中央 ≈ +21（偏绿）、
    右侧 ≈ -5。跨 2 小时抓的 4 帧该分布相关系数 0.993~0.998，说明是镜头/传感器
    固定的 color shading（微透镜斜入射效应），全局 AWB/CCM 修不了。

★ 为什么输出 10 项 1D 表（而不是 10x6 的 2D 表）

    10x6 的每块一个常数增益，块与块之间是**硬跳变**（相邻块差最多 33%），
    块边界（每 128 像素 / 128 行）会形成可见的竖条和横条 —— 这就是
    "背景复杂后出现绿色条带、越复杂越明显"的根因。

    实测（摄像头画面注入连续 shading，块边界 G-R 跳变）：
        10x6 硬跳变        -> 竖 14.11、横 10.69      （条带明显）
        10x6 + 双线性插值  -> 竖  0.48、横  0.48      （好，但 11 个乘法，
                                                       实测 SWNS -10.9ns 跑不动）
        10x1 + 水平插值    -> 竖  0.48、横  0.44      （只要 2 个乘法，时序 OK）

    把 6 行按列**垂直平均**成 1D 之后，垂直方向不再分块 -> 横条自然消失；
    代价是垂直方向有 ±4% 的缓慢渐变误差（残差 1.87），肉眼不可见。

原理
    gain_r[列] = 该列 G 均值 / 该列 R 均值     （先按 128 行分 6 段求均值，再对 6 段平均）
    gain_b[列] = 该列 G 均值 / 该列 B 均值
    R' = R * gain_r,  B' = B * gain_b,  G 直通
    -> 列内三通道相等，但整体亮度不变（G 不做任何改动）。

用法
    # 用最近一次抓帧标定（推荐：对着均匀白墙/白纸拍一张，效果最好）
    python tools/gen_shading_lut.py

    # 指定图片
    python tools/gen_shading_lut.py --image docs/captures/xxx/grab_*.png

    # 只算增益不写文件
    python tools/gen_shading_lut.py --dry-run

    # 看看按 6 行分开的原始 2D 数据（诊断用）
    python tools/gen_shading_lut.py --show-2d

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
GRID_X, GRID_Y = 10, 6          # 标定采样用 10 列 x 6 行，输出时垂直平均成 10x1
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
    files = []
    for p in (os.path.join(ROOT, "docs", "captures", "*", "*.png"),
              os.path.join(ROOT, "docs", "captures", "*.png")):
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
    """返回 (gain_r_1d, gain_b_1d, GR2d, GB2d)，QD 定点。"""
    a = np.asarray(Image.open(img_path).convert("RGB")).astype(np.float64)
    H, W = a.shape[:2]

    GR2d = np.full((GRID_Y, GRID_X), float(Q8_ONE))
    GB2d = np.full((GRID_Y, GRID_X), float(Q8_ONE))

    for i in range(GRID_Y):
        for j in range(GRID_X):
            ys, ye = i * 128, min((i + 1) * 128, H)
            xs, xe = j * 128, min((j + 1) * 128, W)
            blk = a[ys:ye, xs:xe]
            m = osd_mask(ys, ye, xs, xe)
            if m.sum() < 200:           # 有效像素太少（被 OSD 大面积覆盖），保持 1.0
                continue
            r, g, b = (blk[..., 0][m].mean(), blk[..., 1][m].mean(),
                       blk[..., 2][m].mean())
            GR2d[i, j] = np.clip(g / max(r, 1.0) * Q8_ONE, GAIN_MIN, GAIN_MAX)
            GB2d[i, j] = np.clip(g / max(b, 1.0) * Q8_ONE, GAIN_MIN, GAIN_MAX)

    # ★ 垂直平均成 1D（这就是消除横条的关键）
    gain_r = np.round(GR2d.mean(axis=0)).astype(int)
    gain_b = np.round(GB2d.mean(axis=0)).astype(int)
    return gain_r, gain_b, GR2d, GB2d


def write_verilog(gain_r, gain_b, img_path):
    rel = os.path.relpath(img_path, ROOT).replace("\\", "/")
    L = []
    L.append("//=====================================================================")
    L.append("//  color_shading_lut.v  ——  颜色阴影校正增益表（1D 水平表，自动生成）")
    L.append("//")
    L.append("//  生成工具: 0 Project/tools/gen_shading_lut.py")
    L.append("//  源图:     %s" % rel)
    L.append("//  网格:     10 列 x 1 行（标定时按 128 行分 6 段统计，再垂直平均）")
    L.append("//  索引:     blk_x = x[10:7] (0..9)")
    L.append("//  格式:     Q8 定点，256 = 1.0x；只调 R/B，G 直通（保持亮度）")
    L.append("//")
    L.append("//  ★ 为什么从 10x6 改成 10x1")
    L.append("//    10x6 的分块增益是硬跳变的，块边界（每 128 像素 / 128 行）会形成")
    L.append("//    可见的竖条和横条。实测（摄像头画面注入连续 shading）：")
    L.append("//      10x6 硬跳变      -> 竖边界 G-R 跳变 14.11、横 10.69")
    L.append("//      10x6 双线性插值  -> 竖 0.48、横 0.48（但 11 个乘法串行，")
    L.append("//                          实测 SWNS -10.9ns，75 MHz 跑不动）")
    L.append("//      10x1 + 水平插值  -> 竖 0.48、横 0.44（只要 2 个插值乘法）")
    L.append("//    垂直方向改成不分块后，横条自然消失；残差 1.87 是缓慢渐变，肉眼不可见。")
    L.append("//=====================================================================")
    L.append("module color_shading_lut (")
    L.append("    input  wire [3:0] I_blk,")
    L.append("    output reg  [8:0] O_gain_r,")
    L.append("    output reg  [8:0] O_gain_b")
    L.append(");")
    L.append("    always @(*) begin")
    L.append("        case (I_blk)")
    for i in range(GRID_X):
        L.append("            4'd%d: begin O_gain_r = 9'd%d; O_gain_b = 9'd%d; end"
                 % (i, gain_r[i], gain_b[i]))
    L.append("            default: begin O_gain_r = 9'd256; O_gain_b = 9'd256; end")
    L.append("        endcase")
    L.append("    end")
    L.append("endmodule")
    with open(OUT_V, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")
    return len(L)


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description="标定 color shading 增益表（10x1 水平表）")
    ap.add_argument("--image", help="抓帧 PNG 路径（默认用最近一次抓帧）")
    ap.add_argument("--dry-run", action="store_true", help="只打印增益，不写文件")
    ap.add_argument("--show-2d", action="store_true", help="额外打印按 6 行分开的 2D 数据")
    args = ap.parse_args()

    img = args.image or latest_capture()
    if not os.path.isabs(img):
        img = os.path.join(ROOT, img)
    if not os.path.exists(img):
        sys.exit("图片不存在: %s" % img)

    print("源图: %s" % img)
    gain_r, gain_b, GR2d, GB2d = calibrate(img)

    if args.show_2d:
        print("\n=== 2D 原始数据（10 列 x 6 行，R/B）===")
        for i in range(GRID_Y):
            print("  y%d  " % i + " ".join("%3d/%3d" % (GR2d[i, j], GB2d[i, j])
                                           for j in range(GRID_X)))
        print("  (上面这些行会被垂直平均成下面这张 1D 表)")

    print("\n=== 1D 表（10 列，垂直平均）===")
    print("  列   : " + " ".join("%4d" % j for j in range(GRID_X)))
    print("  R增益: " + " ".join("%4d" % v for v in gain_r))
    print("  B增益: " + " ".join("%4d" % v for v in gain_b))
    print("  R范围 %.2fx ~ %.2fx    B范围 %.2fx ~ %.2fx"
          % (gain_r.min() / 256, gain_r.max() / 256,
             gain_b.min() / 256, gain_b.max() / 256))

    # 相邻列跳变量（决定插值后的残留台阶）
    dr = np.abs(np.diff(gain_r)) / 256 * 100
    db = np.abs(np.diff(gain_b)) / 256 * 100
    print("  相邻列最大跳变: R %.1f%%  B %.1f%%  （插值后线性过渡，不再是硬边）"
          % (dr.max(), db.max()))

    if args.dry_run:
        print("\n--dry-run：未写文件")
        return

    n = write_verilog(gain_r, gain_b, img)
    print("\n已生成 %s（%d 行）" % (os.path.relpath(OUT_V, ROOT), n))
    print("下一步：重新编译（build_all.ps1）")


if __name__ == "__main__":
    main()
