# MCU 使用与扩展指南

本文针对 `A-original-reuse` 分支。当前工程已经把安路 MCU 硬核放进 FPGA 工程，但它仍是被动接入版本，便于队友先编译、烧录和继续扩展。

## 当前 MCU 做了什么

顶层实例位于 `user_source/hdl_source/design_top_wrapper.v` 的 `u_mcu_passive`。当前连接关系如下：

| 接口 | 当前连接 | 含义 |
|---|---|---|
| `core_clk`、`timer_clk` | `S_100m_clk` | MCU 核心和定时器使用 100 MHz |
| `apb_clk` | `I_sys_clk` | 保留 APB 时钟入口 |
| `core_reset`、`por_reset`、`apb_rst` | `~S_pll_lock` | PLL 未锁定时保持复位 |
| GPIO0/1 输入 | `I_button[0/1]` | 只读输入，MCU 输出方向和输出值未接入 FPGA 控制 |
| GPIO2～7 输入 | `0` | 安全固定值 |
| UART RX | `1'b1` | 空闲电平 |
| UART TX | 悬空 | 当前不作为板级输出 |
| JTAG | 固定为 0，TDO 悬空 | 当前未开放 MCU 调试链路 |
| I²C | 输入固定为 1，输出悬空 | MCU 不拥有摄像头 I²C |
| QSPI | 未使用 | 未连接外部 Flash |
| AHB | 输出悬空，读回常量/ready | 当前没有 AHB 从设备 |
| APB | 输出悬空，`prdata=0`、`pready=1`、`pslverr=0` | 当前没有 APB 外设 |

因此，当前 MCU 的作用是验证硬核能与原工程一起综合、布局、布线和生成 bitstream。它没有运行本项目固件，也没有改变图像数据路径。

## 摄像头 I²C 的所有权

摄像头 SDA/SCL 仍由原工程的 `uicfgcs520` 控制：

```text
S_24m_clk → uicfgcs520 → O_cam_scl / IO_cam_sda
```

不要把 MCU 的 I²C 输出直接并到 `IO_cam_sda` 或 `O_cam_scl`。如果以后需要让 MCU 配置摄像头，必须先设计明确的总线所有权切换、三态控制、复位默认值和 ACK 交接，再移除 FPGA 控制器的对应驱动；两个主设备同时驱动会造成 I²C ACK、传感器初始化和画面黑屏问题。

## MCU 文件位置

- `user_source/ip_source/MCU/MCU.v`：工程使用的 MCU 顶层封装
- `user_source/ip_source/MCU/MCU_f9f874759a41.v`：TD 生成的 MCU 实例封装
- `user_source/ip_source/MCU/Design.xml`：IP 定义
- `user_source/ip_source/MCU/DesignConfiguration.xml`：IP 配置
- `user_source/ip_source/MCU/.params_MCU.txt`、`.ports_MCU.txt`：生成参数和端口记录
- `user_source/hdl_source/design_top_wrapper.v`：当前工程的实例化和 tie-off
- `user_source/hdl_source/ps_wrapper.v`：通用 MCU/APB/GPIO 包装器，当前 A 版没有例化

`MCU.v` 和 `MCU_f9f874759a41.v` 是 TD 生成文件。除非重新生成 IP，否则不要手改其中的端口、参数或加密原语。

## 后续接入 FPGA 控制寄存器

推荐先做一个很小的 APB 从设备，把 MCU 控制限制在低速配置寄存器：

1. 在 `design_top_wrapper.v` 保留 MCU 的 `apb_clk` 和 `apb_rst`。
2. 将 MCU 的 `paddr/psel/penable/pwrite/pwdata/pstrobe/pprot` 接到一个 APB 从设备。
3. 从设备返回 `prdata/pready/pslverr`；无访问时 `pready` 可保持 1，错误访问才置 `pslverr`。
4. 对跨到像素、24 MHz、DDR 或 MIPI 时钟域的控制位使用双触发器或握手同步；不要把 APB 寄存器直接接到视频时钟域。
5. 先接一个只读版本寄存器和一个低风险控制位，再逐步接入图像参数。
6. 每次改变 MCU/APB 连线都重新执行完整 A→B→C 构建，重新核对资源、时序、I²C 初始化和 HDMI 画面。

推荐的第一组寄存器是：版本号（只读）、构建号（只读）、图像模式请求、颜色校正档位请求和提交/忙标志。图像模式仍应在视频域安全地锁存，不能让 APB 写周期直接驱动 `img_proc` 的组合选择。

## GPIO、UART 和 JTAG 扩展

- GPIO 适合低速按键、状态灯和单比特请求；输出必须经过同步和默认安全值。
- UART 适合日志或命令行，但要明确使用哪一个 UART、板级引脚和波特率；不要把 MCU UART 与当前 FPGA 调试 UART 无约束地并接。
- JTAG 必须在顶层引出并核对板卡连接方式后再启用。当前 A 版将 JTAG 输入固定为 0，因此不能据此判断 MCU 调试链路可用。

## 构建、烧录和验收

在仓库根目录执行完整构建：

```powershell
.\td_project\patch\build_all.ps1 -TdExe 'D:\Anlogic\TD6.2.1\bin\td_commands_prompt.exe'
```

必须看到：

- `PHASE_A_DONE ERR=0`
- `PATCH_FINISHED`
- `VERIFIED_COUNTER_SELECTORS12`
- `PHASE_C_DONE ERR=0`
- `CHECK valid_2d=2 valid_3d=14`
- `SWNS/HWNS > 0`，`STNS/HTNS = 0`

烧录时使用与本次源码匹配的 bitstream：

```powershell
.\tools\burn.ps1 -Bit 'td_project\camera_to_dsi_display.bit'
```

烧录成功必须看到 `PRG-2014 : Chip validation success: PH1P35MDG324`。随后依次检查摄像头 I²C 初始化、HDMI 持续画面、Logo 和任何新增的 MCU 寄存器读写；只看到 bitgen 成功不能替代板上验收。

## 常见误区

- MCU 硬核存在，不等于 MCU 已经控制图像链。
- `ps_wrapper.v` 存在，不等于它已经在 A 版顶层例化。
- GPIO 输入接到按键，不等于按键模式切换已经由 MCU 完成；当前模式选择仍是 FPGA 逻辑。
- I²C 输入固定为高电平是 tie-off，不是摄像头总线连接。
- 不要跳过 HDMI 数据库补丁阶段，也不要用旧 bitstream 代替本次源码构建的 bitstream。
