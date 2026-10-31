# A-original-reuse + Logo 发布说明

> **历史记录，不作为当前版本操作说明**：本文保留当时实验、测量及计划；其中“当前/已烧录/下一步”、算法开关、资源和本机路径仅适用于文内历史版本。当前五拨码最终版以[README](README.md)及[算法说明](CURRENT_ALGORITHMS.md)为准。


## 版本定位

- 分支：`A-original-reuse`
- 提交：`ee675b6 A版启用安路科技Logo`
- 器件：安路 `PH1P35MDG324`，-3 速级
- 图像链：复用原工程的 SC520CS 配置、MIPI CSI、ISP、DDR、图像处理和 HDMI 链路
- MCU：已加入硬核实例，但当前只做被动时钟/复位接入，详见 [MCU_USAGE.md](MCU_USAGE.md)
- B 版自建图像链：不属于本版本，不要从 B 分支复制源码或 bit

## Logo

Logo 由 `user_source/hdl_source/osd_overlay.v` 和 `user_source/hdl_source/osd_logo_rom.v` 实现。顶层文件 `user_source/hdl_source/design_top_wrapper.v` 的 OSD 实例使用：

```verilog
.LOGO_EN (1)
```

显示窗口为 128×80，左上坐标为 `(1136,16)`，适用于 1280×720 输出。Logo 像素采用透明、安路深蓝和安路红三种状态，不改变视频同步。

## 构建与烧录证据

本版本使用 TD 6.2.168116 完成完整 A→B→C 流程，B 阶段 HDMI 网表修补通过：

- `PATCH_FINISHED`
- `VERIFIED_COUNTER_SELECTORS12`
- `valid_2d=2 valid_3d=14`
- `SWNS=+0.138ns`
- `HWNS=+0.020ns`
- `STNS=0`、`HTNS=0`

烧录返回 `PRG-2014 : Chip validation success: PH1P35MDG324`。

对应 bitstream 的 SHA-256 为：

```text
251C00C1523D4820E48BD48BA6F5BCEA6EBFB524E06E12E2F9B75EB1A0517A1B
```

本机归档路径：

```text
D:\FPGA\codex\_build\20261029project\A-original-reuse-logo-20261030\camera_to_dsi_display.bit
```

构建和烧录：

```powershell
.\td_project\patch\build_all.ps1 -TdExe 'D:\Anlogic\TD6.2.1\bin\td_commands_prompt.exe'
.\tools\burn.ps1 -Bit 'td_project\camera_to_dsi_display.bit'
```

每次烧录前检查 bit 的生成时间和 SHA-256。JTAG 配置掉电丢失，重新上电后需要重新烧录。

## 资源占用

数据来自最终布局后的 `camera_to_dsi_display_phy.area`：

| 资源 | 用量 | 总量 | 占用率 |
|---|---:|---:|---:|
| LUT6 | 9,329 | 21,216 | 43.97% |
| 寄存器/FF | 9,332 | 42,432 | 21.99% |
| Slice | 10,410 | 21,216 | 49.07% |
| ERAM20K | 43 | 108 | 39.81% |
| DSP | 31 | 40 | 77.50% |
| PLL | 3 | 6 | 50.00% |
| MCU | 1 | 1 | 100.00% |

与无 MCU 原版基线（LUT6 9,434、FF 9,383、Slice 10,547、ERAM20K 43、DSP 31、PLL 3）相比，A 版分别减少 105 LUT6、51 FF、137 Slice；ERAM、DSP 和 PLL 不变，新增 1 个 MCU 硬核资源。启用 Logo 相对于 A 版未启用 Logo 的构建增加约 213 LUT6、5 FF、200 Slice。

## 当前功能边界

- A 版实时摄像头画面已在板上确认持续更新；带 Logo bit 已完成烧录，Logo 外观由接手者按本说明现场核对。
- 原图、灰度、二值化、Sobel、颜色校正档位和 OSD 仍由原 FPGA 图像链完成。
- 当前 MCU 没有接管摄像头 I²C、ISP、DDR、HDMI 或图像模式控制。
- MCU 真正参与控制前，必须按 [MCU_USAGE.md](MCU_USAGE.md) 增加 APB/GPIO/UART 接口并重新做资源、时序和板上验证。
