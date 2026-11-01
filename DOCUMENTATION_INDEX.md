# 最终版文档索引

当前工程分支为 `main`，适用于图像＋微振动整合最终版。本索引只列当前版本需要随工程保留的说明文件；历史实验记录已从工程目录清理，但仍可从 Git 历史提交 `e7d04e9` 之前的版本恢复。

## 使用入口

| 文档 | 用途 |
|---|---|
| [README](README.md) | 版本、目录、操作、bit 路径和资源总览 |
| [TEAM_GUIDE](TEAM_GUIDE.md) | 队友快速上手和常用操作 |
| [FIVE_SWITCH_DEMO](FIVE_SWITCH_DEMO_20261101.md) | 五拨码、按键和 OSD 状态语义 |
| [CURRENT_ALGORITHMS](CURRENT_ALGORITHMS.md) | 当前图像链路、算法参数和功能边界 |
| [RESOURCE_USAGE](RESOURCE_USAGE.md) | LUT、Slice、FF、ERAM、DSP、PLL、MCU 占用及比较口径 |
| [BUILD_AND_PROGRAM](BUILD_AND_PROGRAM.md) | 编译、bit 归档和自行烧录方法 |
| [MCU_USAGE](MCU_USAGE.md) | 当前 MCU 硬核连接和后续扩展路线 |
| [MCU_LESSONS](MCU_LESSONS.md) | MCU/FPGA 协作、时钟、CDC、I²C 和资源经验 |
| [INTEGRATION_NOTES](INTEGRATION_NOTES.md) | 两工程整合边界、DSP 竖条修复与后续研究事项 |
| `validation/green_lines_dsp_20261101/` | 当前构建、烧录、源码哈希和用户截图证据 |
| `validation/five_switch_demo_20261101/` | 整合前五拨码图像基线证据 |

## 阅读顺序

第一次接触工程：先读 [README](README.md) 和 [TEAM_GUIDE](TEAM_GUIDE.md)。

需要理解画面处理：读 [CURRENT_ALGORITHMS](CURRENT_ALGORITHMS.md) 和 [FIVE_SWITCH_DEMO](FIVE_SWITCH_DEMO_20261101.md)。

需要编译或烧录：读 [BUILD_AND_PROGRAM](BUILD_AND_PROGRAM.md)，再核对 [RESOURCE_USAGE](RESOURCE_USAGE.md)。

需要继续开发 MCU：先读 [MCU_USAGE](MCU_USAGE.md)，再读 [MCU_LESSONS](MCU_LESSONS.md)。

当前版本的完整历史可以通过 Git 查看；不再把旧候选、旧资源报告和旧板测记录混在最终工程目录中。
