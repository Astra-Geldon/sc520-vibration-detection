# 最终版文档索引

当前交付基线为codex/fusion-exposure-linked-lift:d1fe233初赛final，适用于图像＋微振动整合最终版。本索引列出现行说明；validation/下按日期命名的目录保留历史实验和复现证据。

## 使用入口

| 文档 | 用途 |
|---|---|
| [README](README.md) | 版本、目录、操作、bit 路径和资源总览 |
| [TEAM_GUIDE](TEAM_GUIDE.md) | 队友快速上手和常用操作 |
| [FIVE_SWITCH_DEMO](FIVE_SWITCH_DEMO_20261101.md) | 五拨码、按键和 OSD 状态语义 |
| [AUTO_EXPOSURE](AUTO_EXPOSURE.md) | K4自动曝光、冻结/恢复、资源估计与局部验证 |
| [CURRENT_ALGORITHMS](CURRENT_ALGORITHMS.md) | 当前图像链路、算法参数和功能边界 |
| [RESOURCE_USAGE](RESOURCE_USAGE.md) | LUT、Slice、FF、ERAM、DSP、PLL、MCU 占用及比较口径 |
| [RESOURCE_OPTIMIZATION](RESOURCE_OPTIMIZATION.md) | 当前资源热点、已完成清理和后续压缩方案 |
| [BUILD_AND_PROGRAM](BUILD_AND_PROGRAM.md) | 编译、bit 归档和自行烧录方法 |
| [MCU_USAGE](MCU_USAGE.md) | 当前 MCU 硬核连接和后续扩展路线 |
| [MCU_LESSONS](MCU_LESSONS.md) | MCU/FPGA 协作、时钟、CDC、I²C 和资源经验 |
| [INTEGRATION_NOTES](INTEGRATION_NOTES.md) | 两工程整合边界、DSP 竖条修复与后续研究事项 |
| `td_project/camera_to_dsi_display_phy.area`、`patched_final_timing.rpt` | 当前资源和时序报告 |
| `tools/test_*.py`、`validation/` | 局部验证脚本和按日期保存的历史证据 |

## 阅读顺序

第一次接触工程：先读 [README](README.md) 和 [TEAM_GUIDE](TEAM_GUIDE.md)。

需要理解画面处理：读 [CURRENT_ALGORITHMS](CURRENT_ALGORITHMS.md) 和 [FIVE_SWITCH_DEMO](FIVE_SWITCH_DEMO_20261101.md)。

需要编译或烧录：读 [BUILD_AND_PROGRAM](BUILD_AND_PROGRAM.md)，再核对 [RESOURCE_USAGE](RESOURCE_USAGE.md)。

需要继续开发 MCU：先读 [MCU_USAGE](MCU_USAGE.md)，再读 [MCU_LESSONS](MCU_LESSONS.md)。

当前版本的完整历史可以通过 Git 查看；不再把旧候选、旧资源报告和旧板测记录混在最终工程目录中。
