#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""离线评估颜色抓帧的九宫格通道比例。

用法：
  python tools/evaluate_color_capture.py docs/captures/color_diag_k1/grab_xxx.png

默认把画面分成3行×5列，排除过暗、过曝、OSD和高梯度像素，输出每格
G/R、G/B，以及极差和绝对误差。它只用于比较不同k档或不同LUT，不把
一张含人物/灯管的图当成正式标定结果。
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

WIDTH = 1280
HEIGHT = 720
OSD_RECTS = ((16, 96, 1136, 1264), (16, 52, 16, 112))


def load(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        image = image.convert("RGB")
        if image.size != (WIDTH, HEIGHT):
            image = image.resize((WIDTH, HEIGHT), Image.Resampling.BILINEAR)
        return np.asarray(image, dtype=np.float64)


def cell_ratio(cell: np.ndarray, y0: int, x0: int) -> tuple[float, float, int]:
    mask = (cell[..., 1] >= 25.0) & (cell[..., 1] <= 235.0)
    mask &= np.max(cell, axis=2) < 245.0
    dx = np.abs(np.diff(cell, axis=1)).max(axis=2)
    dy = np.abs(np.diff(cell, axis=0)).max(axis=2)
    grad = np.zeros(mask.shape, dtype=np.float64)
    grad[:, 1:] = np.maximum(grad[:, 1:], dx)
    grad[1:, :] = np.maximum(grad[1:, :], dy)
    mask &= grad <= 4.0

    for oy0, oy1, ox0, ox1 in OSD_RECTS:
        ly0 = max(0, oy0 - y0)
        ly1 = min(cell.shape[0], oy1 - y0)
        lx0 = max(0, ox0 - x0)
        lx1 = min(cell.shape[1], ox1 - x0)
        if ly1 > ly0 and lx1 > lx0:
            mask[ly0:ly1, lx0:lx1] = False

    if mask.sum() < 100:
        return float("nan"), float("nan"), int(mask.sum())
    r = np.maximum(cell[..., 0][mask], 1.0)
    g = np.maximum(cell[..., 1][mask], 1.0)
    b = np.maximum(cell[..., 2][mask], 1.0)
    # 中值比简单均值更不容易被少量纹理或残余文字污染。
    return float(np.median(g / r)), float(np.median(g / b)), int(mask.sum())


def evaluate(path: Path, rows: int, cols: int) -> None:
    frame = load(path)
    gr = np.full((rows, cols), np.nan)
    gb = np.full((rows, cols), np.nan)
    counts = np.zeros((rows, cols), dtype=int)
    for row in range(rows):
        y0 = row * HEIGHT // rows
        y1 = (row + 1) * HEIGHT // rows
        for col in range(cols):
            x0 = col * WIDTH // cols
            x1 = (col + 1) * WIDTH // cols
            gr[row, col], gb[row, col], counts[row, col] = cell_ratio(frame[y0:y1, x0:x1], y0, x0)

    print(f"\n{path}")
    print("G/R:")
    for row in gr:
        print("  " + " ".join("  nan" if not np.isfinite(v) else f"{v:5.3f}" for v in row))
    print("G/B:")
    for row in gb:
        print("  " + " ".join("  nan" if not np.isfinite(v) else f"{v:5.3f}" for v in row))
    for name, values in (("G/R", gr), ("G/B", gb)):
        finite = values[np.isfinite(values)]
        if finite.size:
            print(f"{name}: 中位数={np.median(finite):.3f}, 极差={np.ptp(finite):.3f}, "
                  f"最大绝对误差={np.max(np.abs(finite - 1.0)):.3f}")
    print(f"有效样本数: 最小={counts.min()}, 中位数={int(np.median(counts))}")


def main() -> None:
    parser = argparse.ArgumentParser(description="评估颜色抓帧九宫格通道比例")
    parser.add_argument("image", nargs="+", type=Path)
    parser.add_argument("--rows", type=int, default=3)
    parser.add_argument("--cols", type=int, default=5)
    args = parser.parse_args()
    for path in args.image:
        if not path.exists():
            parser.error(f"图片不存在: {path}")
        evaluate(path, args.rows, args.cols)


if __name__ == "__main__":
    main()
