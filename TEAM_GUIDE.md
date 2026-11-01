# 队友上手指南 · 整合最终版

分支 `main`，日期 2026-11-01。摄像头、基础处理、图像增强和 HDMI 沿用 `20261029project`；微振动沿用 `backup-vibration-20261030` 实际 RTL。

1. 按 [README](README.md) 获取工程，连接 SC520CS、开发板电源、USB/JTAG 和 HDMI。
2. 按[编译烧录说明](BUILD_AND_PROGRAM.md)核对并下载本版 Bit；没有本机 Bit 时先完整构建。
3. KEY1 回彩色，SW1～SW5 控制图像功能，方向以左下 OSD 为准。KEY2 切换灰度、二值化、Sobel。
4. KEY3 控制微振动算法，上电默认关闭。开启后输出振动结果标记；关闭后旁路标记及振动 DDR 请求。UART 诊断保留。

SW2 同时控制 Gamma/N1；SW4 关闭时 AWB/CSC/N1 自动旁路；SW5 切换曝光增益，需等待 EXP 退出 WAIT。KEY4 无旧参数菜单，SW6 不使用。细节见[五拨码说明](FIVE_SWITCH_DEMO_20261101.md)。

本版用户画面已确认原来的绿色竖条消失，完整振动测频精度不在本次验收范围。请勿把早期图像单工程的 Bit、31 DSP 资源报告或“微振动未启用”说明套用到当前版本。

HDMI 使用既有加密核补丁，改 RTL 后必须完整 A→B→C；不直接 GUI Run。bbox 的 `dsp_style="no"` 属性用于避免 DSP 压力导致主图像模块被自动合并，应保留。

[当前算法](CURRENT_ALGORITHMS.md) · [资源](RESOURCE_USAGE.md) · [整合决定与待研究事项](INTEGRATION_NOTES.md) · [MCU 状态](MCU_USAGE.md) · [验证档案](validation/green_lines_dsp_20261101/README.md)
