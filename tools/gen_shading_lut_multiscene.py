#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从多张RAW_PASS中性场景图生成归一化的2段×10列空间校正表。

当前硬件的AWB负责整体色温，color_shading只应描述传感器的空间形状。
因此本工具对每个场景先减去该场景的全局中值，再跨场景取中值，避免把
某一盏灯的整体颜色写进固定LUT。输出格式与当前color_shading_lut.v兼容。

示例：
  python tools/gen_shading_lut_multiscene.py \
      --image docs/captures/raw_pass/grab_190905_01.png \
      --image docs/captures/raw_pass_human/raw_room.png \
      --image docs/captures/raw_pass_human/raw_desk.png \
      --output docs/artifacts/color_shading_lut_multiscene.v

输入图会统一映射到1280×720，这是color_shading坐标计数器对应的有效画面尺寸。
工具只生成候选文件，不自动覆盖RTL中的color_shading_lut.v。
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image

WIDTH = 1280
HEIGHT = 720
GRID_X = 10
GRID_Y = 2
Q8_ONE = 256.0
GAIN_MIN = 128
GAIN_MAX = 511

# OSD相对于有效画面左上角的区域：(y0,y1,x0,x1)。
OSD_RECTS = (
    (16, 96, 1136, 1264),
    (16, 52, 16, 112),
)


def load_frame(path: Path) -> np.ndarray:
    """读取图像并统一为硬件有效区的RGB浮点数组。"""
    with Image.open(path) as image:
        image = image.convert("RGB")
        if image.size != (WIDTH, HEIGHT):
            image = image.resize((WIDTH, HEIGHT), Image.Resampling.BILINEAR)
        return np.asarray(image, dtype=np.float64)


def valid_mask(block: np.ndarray, y0: int, x0: int) -> np.ndarray:
    """保留中高亮、未过曝、局部平坦的像素，并排除OSD。"""
    r, g, b = (block[..., 0], block[..., 1], block[..., 2])
    mask = (g >= 25.0) & (g <= 235.0) & (np.max(block, axis=2) < 245.0)

    # 用相邻像素差排除桌边、人物和文字。传感器固定色偏不会被这一项排除。
    dx = np.abs(np.diff(block, axis=1)).max(axis=2)
    dy = np.abs(np.diff(block, axis=0)).max(axis=2)
    grad = np.zeros(g.shape, dtype=np.float64)
    grad[:, 1:] = np.maximum(grad[:, 1:], dx)
    grad[1:, :] = np.maximum(grad[1:, :], dy)
    mask &= grad <= 5.0

    for oy0, oy1, ox0, ox1 in OSD_RECTS:
        ly0 = max(0, oy0 - y0)
        ly1 = min(block.shape[0], oy1 - y0)
        lx0 = max(0, ox0 - x0)
        lx1 = min(block.shape[1], ox1 - x0)
        if ly1 > ly0 and lx1 > lx0:
            mask[ly0:ly1, lx0:lx1] = False
    return mask


def scene_log_ratios(frame: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """返回一张图的log(G/R)、log(G/B)网格及每格样本数。"""
    gr = np.full((GRID_Y, GRID_X), np.nan, dtype=np.float64)
    gb = np.full((GRID_Y, GRID_X), np.nan, dtype=np.float64)
    counts = np.zeros((GRID_Y, GRID_X), dtype=np.int64)

    for row in range(GRID_Y):
        y0 = row * HEIGHT // GRID_Y
        y1 = (row + 1) * HEIGHT // GRID_Y
        for col in range(GRID_X):
            x0 = col * WIDTH // GRID_X
            x1 = (col + 1) * WIDTH // GRID_X
            block = frame[y0:y1, x0:x1]
            mask = valid_mask(block, y0, x0)
            counts[row, col] = int(mask.sum())
            if counts[row, col] < 200:
                continue
            r = np.maximum(block[..., 0][mask], 1.0)
            g = np.maximum(block[..., 1][mask], 1.0)
            b = np.maximum(block[..., 2][mask], 1.0)
            gr[row, col] = np.median(np.log(g / r))
            gb[row, col] = np.median(np.log(g / b))
    return gr, gb, counts


def normalized_shape(log_grid: np.ndarray) -> np.ndarray:
    """去掉当前场景的全局色温，只保留空间形状。"""
    center = np.nanmedian(log_grid)
    return log_grid - center


def make_table(images: list[Path]) -> tuple[np.ndarray, np.ndarray, list[tuple[np.ndarray, np.ndarray, np.ndarray]]]:
    all_r = []
    all_b = []
    details = []
    for path in images:
        frame = load_frame(path)
        raw_r, raw_b, counts = scene_log_ratios(frame)
        if np.count_nonzero(np.isfinite(raw_r)) < GRID_X:
            raise ValueError(f"有效中性样本不足，无法标定: {path}")
        all_r.append(normalized_shape(raw_r))
        all_b.append(normalized_shape(raw_b))
        details.append((raw_r, raw_b, counts))

    # 对不同场景取中值，降低人物/桌面等局部内容污染。
    shape_r = np.nanmedian(np.stack(all_r), axis=0)
    shape_b = np.nanmedian(np.stack(all_b), axis=0)
    gain_r = np.clip(np.rint(Q8_ONE * np.exp(shape_r)), GAIN_MIN, GAIN_MAX).astype(int)
    gain_b = np.clip(np.rint(Q8_ONE * np.exp(shape_b)), GAIN_MIN, GAIN_MAX).astype(int)
    return gain_r, gain_b, details


def write_verilog(path: Path, gain_r: np.ndarray, gain_b: np.ndarray, images: list[Path]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "//=====================================================================",
        "// 多场景归一化颜色阴影表（候选文件，需板上验证后再替换RTL）",
        "// 每个场景先去除全局log(G/R)、log(G/B)中值，再跨场景取中值。",
        "// 256=1.0；只调R/B，整体白平衡由AWB负责。",
        "// 网格：上/下2段×10列；与color_shading.v的I_vsel接口一致。",
        "// 标定源：" + ", ".join(str(p).replace("\\", "/") for p in images),
        "//=====================================================================",
        "module color_shading_lut (",
        "    input  wire [3:0] I_blk,",
        "    input  wire       I_vsel,",
        "    output reg  [8:0] O_gain_r,",
        "    output reg  [8:0] O_gain_b",
        ");",
        "    always @(*) begin",
        "        case ({I_vsel, I_blk})",
    ]
    for row in range(GRID_Y):
        for col in range(GRID_X):
            index = row * GRID_X + col
            lines.append(
                f"            5'd{index}: begin O_gain_r = 9'd{gain_r[row, col]}; "
                f"O_gain_b = 9'd{gain_b[row, col]}; end"
            )
    lines += [
        "            default: begin O_gain_r = 9'd256; O_gain_b = 9'd256; end",
        "        endcase",
        "    end",
        "endmodule",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="生成多场景归一化2段×10列颜色阴影表")
    parser.add_argument("--image", action="append", required=True, help="RAW_PASS场景图，可重复")
    parser.add_argument("--output", default="docs/artifacts/color_shading_lut_multiscene.v")
    args = parser.parse_args()

    images = [Path(p) for p in args.image]
    missing = [str(p) for p in images if not p.exists()]
    if missing:
        parser.error("图片不存在: " + ", ".join(missing))
    if len(images) < 2:
        parser.error("至少提供两张不同场景图，避免单图过拟合")

    gain_r, gain_b, details = make_table(images)
    print("R增益:")
    print("  上: " + " ".join(f"{v:3d}" for v in gain_r[0]))
    print("  下: " + " ".join(f"{v:3d}" for v in gain_r[1]))
    print("B增益:")
    print("  上: " + " ".join(f"{v:3d}" for v in gain_b[0]))
    print("  下: " + " ".join(f"{v:3d}" for v in gain_b[1]))
    for path, (_, _, counts) in zip(images, details):
        print(f"{path}: 最小有效样本数={counts.min()}, 中位数={int(np.median(counts))}")

    output = Path(args.output)
    write_verilog(output, gain_r, gain_b, images)
    print(f"已写入候选表: {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
