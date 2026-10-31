# 最终版编译、bit归档与自行烧录

适用五拨码最终版。日常恢复画面直接使用已归档bit，只有修改RTL/IP/约束才需要重编译。此文档整理没有改变生产源码 `85c7f7d`，无需重烧验证文字修改。

## 直接使用本机最终bit

```text
D:\FPGA\codex\_build\20261029project\final-20261101\SC520_final_five_switch_20261101.bit
```

大小：1,789,539字节。SHA-256：

```text
4d3e193aa914d10deed1493e32bebb461fea994d957756b77819ecc7fe7ebcdb
```

它是02:51:30已下载bit的同内容副本，原始档案仍在 `D:/FPGA/codex/_build/20261029project/five-switch-demo-20261101/bitstreams/五拨码画质演示版_85c7f7d.bit`。快照提交 `5abdac4` 名为“最终版”；后续只更新文档，生产文件内容与该bit对应输入相同。

先接好电源、USB/JTAG和HDMI。从仓库根目录运行：

```powershell
Get-FileHash 'D:\FPGA\codex\_build\20261029project\final-20261101\SC520_final_five_switch_20261101.bit' -Algorithm SHA256
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\program_final.ps1 -Bit 'D:\FPGA\codex\_build\20261029project\final-20261101\SC520_final_five_switch_20261101.bit' -TdExe 'D:\Anlogic\TD6.2.1\bin\td_commands_prompt.exe'
```

新增辅助脚本默认核对上述SHA、将bit暂存到ASCII路径，日志和Tcl统一写入 `_build/20261029project/manual-programming/` 的独立子目录，并要求器件校验、download完成和退出码同时成功。脚本为本次交接新增，完成语法/文件检查；没有因此再次操作板卡。本轮实际烧录证据来自 [programming.json](validation/five_switch_demo_20261101/programming.json)。

TD安装位置不同时修改 `-TdExe`；JTAG序号不同时可传 `-Cable`，本机实际使用0，速度7。不要同时运行占用FTDI的OpenOCD。JTAG SRAM下载掉电即失，不是写Flash。

使用TD图形烧录器时选择上述同一bit、核对器件PH1P35MDG324，执行JTAG SRAM下载；下载后按KEY1回彩色，以左下面板设置六项ON。

## 需要重新编译时：先复制提交到_build

要求Windows、Git、TD6.2.168116，器件PH1P35MDG324、-3。避免把编译产物放到源码或工作区根目录。先提交源码，再从仓库根目录创建独立构建快照：

```powershell
$buildRoot = 'D:\FPGA\codex\_build\20261029project\rebuild-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Path $buildRoot | Out-Null
git rev-parse HEAD | Set-Content -Encoding ascii (Join-Path $buildRoot 'source_commit.txt')
$sourceZip = Join-Path $buildRoot 'source.zip'
git archive --format=zip --output $sourceZip HEAD user_source td_project
if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
Expand-Archive -LiteralPath (Join-Path $buildRoot 'source.zip') -DestinationPath (Join-Path $buildRoot 'source')
$tdDir = Join-Path $buildRoot 'source\td_project'
$alPath = Join-Path $tdDir 'camera_to_dsi_display.al'
[xml]$projectXml = Get-Content -LiteralPath $alPath -Raw -Encoding UTF8
$projectXml.Project.Path = $tdDir.Replace('\','/')
$projectXml.Save($alPath)
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tdDir 'patch\build_all.ps1') -TdExe 'D:\Anlogic\TD6.2.1\bin\td_commands_prompt.exe'
if ($LASTEXITCODE -ne 0) { throw 'TD build failed' }
```

`git archive`只包含已提交文件，未提交/忽略文件不会进入快照。工程AL根路径需规范化为快照目录，其他生产输入保持不变。

完整流程是：A综合并冻结数据库→B修复加密HDMI核的12个计数器选择→C优化/布局/布线/生产时序检查/bitgen，再启动独立TD进程审查已布线CDC。不得跳过B，也不要用旧 `flow_build.tcl` 或直接GUI Run替代。

| 检查点 | 日志/文件 |
|---|---|
| 综合成功 | `pA.log`：PHASE_A_DONE ERR=0、DEMO_CDC_REGISTERS_PASS groups=25 |
| 加密核补丁 | `pB.log`：PATCH_FINISHED、VERIFIED_COUNTER_SELECTORS12 |
| 完整生产时钟 | `pC.log`：DEMO_PRODUCTION_TIMING_PASS |
| 25组物理延迟 | `pC.log`：DEMO_CDC_PHYSICAL_PASS groups=25、PHASE_D_DONE |
| 全部构建完成 | `pC.log`：PHASE_C_DONE ERR=0 |
| 布局资源 | `camera_to_dsi_display_phy.area` |
| 内部时序 | `patched_final_timing.rpt`：SWNS/HWNS非负，STNS/HTNS为0 |
| 新bit | `camera_to_dsi_display.bit`，记录大小、SHA和源码提交 |

这些文件都在 `$tdDir`。比较资源要同时列LUT/Slice/FF/ERAM/DSP/PLL/MCU，DSP预算不超过31。bit存在或chip validation单项成功都不能代替完整验收。

重新生成bit后日期元数据可能改变SHA，不能要求它与已发布bit哈希一致。若烧录自编译版本，可在确认来源后给 `program_final.ps1` 传对应 `-ExpectedSha256`；不要静默替换最终归档bit。

## 验证与故障定位

当前测试脚本在 `tools/test_five_switch_*.py` 和旧命名的 `test_six_switch_isp.py/test_six_switch_osd.py`，后两者实际已检查五拨码链路。它们需要Python和Icarus Verilog；输出目录传入 `_build`。已执行的具体结果及源码hash见 [validation/five_switch_demo_20261101](validation/five_switch_demo_20261101/verification.json)，无需为文字修改重复长仿真。

先确认下载完成，再观察实际画面。采集卡锁定需要数秒；确认选择UGREEN，而非电脑摄像头。RAW或灰度开关状态、无光场景和被占用的采集设备也会改变观察。EXP停在WAIT需要检查传感器配置链，不能把WAIT改成ON掩盖失败。

工程当前不依赖MCU固件启动，也不输出旧UART诊断。历史冷启动、ACK和资源数据只对相应版本有效。[当前资源](RESOURCE_USAGE.md) · [MCU现状](MCU_USAGE.md)。
