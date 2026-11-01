# Final_Project · 最终版

安路 HX1P35A 开发板（PH1P35MDG324，-3）与 SC520CS 摄像头的图像处理、微振动识别及 HDMI 整合工程。发布分支为 `main`，日期 2026-11-01。

本版已完成完整 TD 编译和 JTAG SRAM 烧录。用户提供的最新画面中，之前的密集绿色竖条已消失，摄像头画面、状态面板和 Logo 可正常显示。该反馈用于确认显示恢复；本阶段没有进行完整的振动测频精度验收。

当前源码在上述已上板基线上增加同帧关联的 `LAT xxx.x MS` 延迟显示，并缩小 LAT 和左下算法状态面板。测量口径、紧凑布局及本机检查见 [延迟显示说明](LATENCY_DISPLAY.md) 和 [紧凑 OSD 验证](validation/compact_osd_20261101/README.md)。下文 Bit 哈希及资源表保留的是历史已上板基线；当前源码需重新构建，不能用旧 Bit 验收 LAT。自动曝光尚未接入，SW5 仍选择两组固定曝光/增益。

## 工程基线

- 摄像头、基础图像处理、图像增强、视频缓存与 HDMI：沿用 `20261029project`。
- 微振动识别：接入 `backup-vibration-20261030` 的实际 RTL，640×360 抽头、8×6 分块、64 帧窗口、2～15 Hz/0.5 Hz 频点链路。
- HDMI 优先；ISP 抽头为被动监听。保留振动 HDMI 标记和 FPGA UART 诊断。
- 为避免 DSP 紧张引起图像模块自动合并，仅给 `vib_bbox_grid` 添加 `dsp_style="no"` 资源属性，不改算法公式、位宽或流水节拍。原图像 DSP 保持独立。

## 获取与操作

```powershell
git clone --branch main https://gitee.com/wang-zhanheng/sc520-vibration-detection.git
cd sc520-vibration-detection
```

| 输入 | 功能 |
|---|---|
| KEY1 | 回到原图／增强彩色模式 |
| KEY2 | 切换灰度、二值化、Sobel 模式 |
| KEY3 | 微振动算法开关，上电默认关闭 |
| SW1 | AWB 白平衡 |
| SW2 | Gamma＋固定 N1 |
| SW3 | 水平 Color Shading |
| SW4 | 去马赛克／RAW Bayer 样本灰度 |
| SW5 | E900/G12 与旧参考曝光增益切换 |

开关方向以 OSD 的 ON/OFF 为准。SW4 关闭时 AWB/CSC/N1 自动旁路；曝光切换等待 EXP 结束 WAIT。KEY4 没有旧参数菜单，SW6 不使用。详见[队友指南](TEAM_GUIDE.md)和[五拨码说明](FIVE_SWITCH_DEMO_20261101.md)。

## 编译与下载

先看[编译烧录说明](BUILD_AND_PROGRAM.md)。必须完整执行 `td_project/patch/build_all.ps1` 的 A→B→C，保留加密 HDMI 核的 12 处数据库补丁及当前 34 组独立 CDC 检查。

历史已上板基线 Bit：`td_project/camera_to_dsi_display.bit`，1,789,539 字节。SHA256：

```text
A2CA15E1BC1A57199D6171230E50BCB8DF6F2C4F75635CF387B6BB1AB753B4E1
```

Git 保存源码和验证摘要；Bit、数据库及完整工具报告保留本地，克隆后需自行构建或取得上述已验证 Bit。日期等 Bit 元数据会使重新构建的 SHA256 改变，应核验新构建来源后再下载。JTAG SRAM 配置掉电丢失。

| 历史已上板基线物理资源 | 已用／总量 |
|---|---|
| LUT6 | 18,362 / 21,216 |
| Slice | 19,163 / 21,216，90.32% |
| FF | 16,778 / 42,432 |
| ERAM | 66 / 108 |
| DSP | 40 / 40 |
| PLL / MCU | 3 / 6；1 / 1 |

SWNS +0.121 ns、HWNS +0.020 ns，STNS/HTNS 均为 0。MCU 仅被动接入，未加载应用固件；UART 诊断由 FPGA 实现。

[验证档案及用户画面](validation/green_lines_dsp_20261101/README.md) · [整合决定与待研究事项](INTEGRATION_NOTES.md) · [算法](CURRENT_ALGORITHMS.md) · [资源](RESOURCE_USAGE.md) · [文档索引](DOCUMENTATION_INDEX.md)
