# Final_Project 最终版：编译与烧录

适用基于d1fe233初赛final的当前低LUT构建，包含行缓存优化并保留UART诊断。工具TD6.2.168116，器件PH1P35MDG324、-3。2026-11-04已完成A→B→C、Bit生成和40组物理CDC审计，当前Bit已通过JTAG芯片校验和下载；资源及实验边界见[资源压缩研究](RESOURCE_COMPRESSION_RESEARCH.md)。

## 已验证的 Bit

本机输出：`td_project/camera_to_dsi_display.bit`，大小1,789,539字节，SHA256：

```text
F5D0D2DCF000B2A638A1849B0EE77761494BDD377536BBF9F46B650D6F4CE8BD
```

Bit 被 Git 忽略，远端保存源码、验证 JSON 和用户截图。不要用历史五拨码图像单工程的 Bit 代替本版。

连接电源、USB/JTAG 和 HDMI，在工程根目录运行：

```powershell
Get-FileHash .\td_project\camera_to_dsi_display.bit -Algorithm SHA256
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\program_final.ps1 -Bit '.\td_project\camera_to_dsi_display.bit' -ExpectedSha256 'F5D0D2DCF000B2A638A1849B0EE77761494BDD377536BBF9F46B650D6F4CE8BD' -TdExe 'F:\Anlogic\bin\td_commands_prompt.exe' -OutputRoot "$env:TEMP\sc520-programming" -Spd 7 -Cable 0
```

脚本默认哈希属于历史基线，烧录当前版本必须像上面一样显式传入`-ExpectedSha256`。自编译Bit的哈希可能因日期元数据不同而变化，需先核验构建记录，再传相应哈希；`OutputRoot`需为本机可写的纯ASCII路径。

脚本将 Bit 暂存到纯 ASCII 路径、清理残留 hwserver，并通过本地 `127.0.0.1:5555` 和 `-usr_args "-f 12 -i 0"` 执行 JTAG SRAM 下载。成功需同时满足退出码 0、`PRG-2014 : Chip validation success: PH1P35MDG324` 和 `finish command "download -bit..."`。已知 `USR-8011 invalid option -f 12 -i 0` 单行不代表下载失败，要核对上述全部成功条件。

JTAG SRAM 掉电失效；此流程没有写 Flash 或加载 MCU 固件。

## 完整重建

在当前工程根目录运行，脚本会先归档旧构建输出，避免旧 Bit 或日志冒充成功：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\td_project\patch\build_all.ps1 -TdExe 'F:\Anlogic\bin\td_commands_prompt.exe'
```

`.al` 的文件引用为相对路径；其首部 Project `Path` 仍是本机元数据。克隆到其他目录后，仅将该字段调整为本机 `td_project` 绝对路径。该厂商文件含非标准 XML 属性，不要用通用 XML 库整体重写。其他 HDL/IP/约束和相对引用应保持原样。

A 阶段综合并导出数据库；B 阶段修复加密 HDMI 核的 12 个计数器选择；C 阶段从补丁数据库继续布局布线、最终时序、Bit 生成并独立审查 CDC。不要用 GUI Run、旧 `flow_build.tcl` 或跳过阶段替代。

| 检查 | 成功标志／文件 |
|---|---|
| 综合 | `pA.log`：`PHASE_A_DONE ERR=0`、当前网表独立CDC寄存器审计`groups=40` |
| HDMI 补丁 | `pB.log`：`PATCH_FINISHED`、`VERIFIED_COUNTER_SELECTORS12` |
| 补丁保留 | `pC.log`：`CHECK valid_2d=2 valid_3d=14` |
| DSP | bbox DSP=0，总 DSP≤40，`No need to merge 9x9 Dsps.` |
| 布线 | 无新增物理无驱动网／跳过布线警告，`eco open net = 0` |
| 时序／CDC | `DEMO_PRODUCTION_TIMING_PASS`、`DEMO_CDC_PHYSICAL_PASS groups=40`、`PHASE_D_DONE` |
| Bit生成 | Bitgen、资源报告和时序报告完成，`PHASE_C_DONE ERR=0` |

核对`camera_to_dsi_display_phy.area`资源和`patched_final_timing.rpt`的setup/hold后再烧录。当前Bit已包含自动曝光、Tone LUT、联动补亮及延时显示；A/B/C和40组独立物理CDC审计均完成。烧录时必须使用本节最新SHA256，不能把历史Bit当作当前实现。测量口径见[延时显示说明](LATENCY_DISPLAY.md)。

旧 `verify_diag.py` 面向关闭 HDMI 的历史诊断版本；`check_all_inst.py` 不能识别带初值的端口，具体不适用项已记录在本版 `static_checks.json`，不要为通过旧脚本关闭 HDMI 或改写已验证逻辑。
