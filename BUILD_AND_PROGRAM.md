# Final_Project 最终版：编译与烧录

适用 `main` 的图像＋微振动整合工程。工具 TD 6.2.168116，本机安装 `D:\Anlogic\TD6.2.1`，器件 PH1P35MDG324、-3。2026-11-01 15:56:33（北京时间）已完成本版下载，用户随后提供的画面中绿色竖条已消失。

## 已验证的 Bit

本机输出：`td_project/camera_to_dsi_display.bit`。独立归档：`validation/green_lines_dsp_20261101/Final_Project_bbox_lut_20261101.bit`。两个文件均为 1,789,539 字节，SHA256：

```text
A2CA15E1BC1A57199D6171230E50BCB8DF6F2C4F75635CF387B6BB1AB753B4E1
```

Bit 被 Git 忽略，远端保存源码、验证 JSON 和用户截图。不要用历史五拨码图像单工程的 Bit 代替本版。

连接电源、USB/JTAG 和 HDMI，在工程根目录运行：

```powershell
Get-FileHash .\td_project\camera_to_dsi_display.bit -Algorithm SHA256
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\program_final.ps1 -Bit '.\td_project\camera_to_dsi_display.bit' -ExpectedSha256 'A2CA15E1BC1A57199D6171230E50BCB8DF6F2C4F75635CF387B6BB1AB753B4E1' -TdExe 'D:\Anlogic\TD6.2.1\bin\td_commands_prompt.exe' -Spd 7 -Cable 0
```

发布时已将脚本默认哈希更新为本版；显式传参便于核对。自编译 Bit 的哈希可能因日期元数据不同而变化，需先核验构建记录，再传相应 `-ExpectedSha256`。

脚本将 Bit 暂存到纯 ASCII 路径、清理残留 hwserver，并通过本地 `127.0.0.1:5555` 和 `-usr_args "-f 12 -i 0"` 执行 JTAG SRAM 下载。成功需同时满足退出码 0、`PRG-2014 : Chip validation success: PH1P35MDG324` 和 `finish command "download -bit..."`。已知 `USR-8011 invalid option -f 12 -i 0` 单行不代表下载失败，要核对上述全部成功条件。

JTAG SRAM 掉电失效；此流程没有写 Flash 或加载 MCU 固件。

## 完整重建

在当前工程根目录运行，脚本会先归档旧构建输出，避免旧 Bit 或日志冒充成功：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\td_project\patch\build_all.ps1 -TdExe 'D:\Anlogic\TD6.2.1\bin\td_commands_prompt.exe'
```

`.al` 的文件引用为相对路径；其首部 Project `Path` 仍是本机元数据。克隆到其他目录后，仅将该字段调整为本机 `td_project` 绝对路径。该厂商文件含非标准 XML 属性，不要用通用 XML 库整体重写。其他 HDL/IP/约束和相对引用应保持原样。

A 阶段综合并导出数据库；B 阶段修复加密 HDMI 核的 12 个计数器选择；C 阶段从补丁数据库继续布局布线、最终时序、Bit 生成并独立审查 CDC。不要用 GUI Run、旧 `flow_build.tcl` 或跳过阶段替代。

| 检查 | 成功标志／文件 |
|---|---|
| 综合 | `pA.log`：`PHASE_A_DONE ERR=0`、`DEMO_CDC_REGISTERS_PASS groups=25` |
| HDMI 补丁 | `pB.log`：`PATCH_FINISHED`、`VERIFIED_COUNTER_SELECTORS12` |
| 补丁保留 | `pC.log`：`CHECK valid_2d=2 valid_3d=14` |
| DSP | bbox DSP=0，总 DSP≤40，`No need to merge 9x9 Dsps.` |
| 布线 | 无新增物理无驱动网／跳过布线警告，`eco open net = 0` |
| 时序／CDC | `DEMO_PRODUCTION_TIMING_PASS`、`DEMO_CDC_PHYSICAL_PASS groups=25`、`PHASE_D_DONE` |
| 完成 | `PHASE_C_DONE ERR=0`，新 Bit 时间戳和 SHA256 |

核对 `camera_to_dsi_display_phy.area` 资源和 `patched_final_timing.rpt` 的 setup/hold 后再烧录。本版最终资源与验证情况见[资源说明](RESOURCE_USAGE.md)及[修复档案](validation/green_lines_dsp_20261101/README.md)。

旧 `verify_diag.py` 面向关闭 HDMI 的历史诊断版本；`check_all_inst.py` 不能识别带初值的端口，具体不适用项已记录在本版 `static_checks.json`，不要为通过旧脚本关闭 HDMI 或改写已验证逻辑。
