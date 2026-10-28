# SC520 振动链接入第一步（2026-10-28）

> 历史记录：此第一步版本经用户上板未能识别3/8/10Hz。当前代码已经修复后处理，实际配置与日志字段以 [VIBRATION_RECOVERY_20261028.md](VIBRATION_RECOVERY_20261028.md) 为准；下文PN门限、排名确认和“尚未编译”只描述修复前状态。

修改目录：`D:\workplace\anlogic\sc520-vibration-detection-fix-hdmi-tx-valid`。

本步已接入源文件、顶层连线和 UART 诊断，仅完成静态检查与定点算术模型验证。按用户要求，未启动 TD 编译或烧录；资源、时序、HDMI 与实际识别效果需由本次新构建和上板日志确认。

## 接入链与参数

ISP 只读抽头 → 640×360 灰度 → Gaussian → DDR 上一帧/帧差 → 6行×8列梯度统计 → 48块共享 Goertzel → 峰搜/目标确认 → 最多4个网格框及 UART。

- 图像处理、按键、颜色校正、ISP、PLL、GCLK 和约束沿用队友版。
- 现有 `vib_video_tap.v`、`vib_gauss3x3.v`、`vib_prev_frame_ddr.v`、`vib_ddr_arb.v` 与振动参考版一致，直接复用。
- `VIB_FRAME_DIFF_ON`、`VIB_STAGE2_LK_ON`、`VIB_STAGE2_GZ_ON` 已启用；旧 `VIB_ON` 保持关闭，避免同时运行两条检测链。
- `NFRM=64`、`NBIN=17`、`BIN_MIN=0`、`TONE_RATIO=6`；`MAG_SH=8`、`PN_SH=2`、`PN_FLOOR=12`。
- 两个频率出口统一为 `Hz10=20+bin×5`，有效编码为20～100；无有效目标时输出0。
- multi/peak 两表统一为队友旧 `vib_goertzel.v` 中的正确表：`round(32768*cos(2*pi*f/59.5))`。59.5Hz是当前采样率假设，需用上板日志核对。

## 工程路径

打开：`td_project\camera_to_dsi_display.al`。

新增五模块由 `design_top_wrapper.v` 的相对 `include` 引入，不要重复添加为独立 Design Files：

1. `vibration/vib_lk_grid_multi.v`
2. `vibration/vib_eram_dp.v`
3. `vibration/vib_gz_multi.v`
4. `vibration/vib_gz_peak.v`
5. `vibration/vib_osd_marker.v`（替换原单框版本）

`.al` 的项目目录已是当前 anlogic 目录，无需额外改路径。

## 由用户启动编译

在 PowerShell 中执行：

```powershell
Set-Location -LiteralPath 'D:\workplace\anlogic\sc520-vibration-detection-fix-hdmi-tx-valid'
.\td_project\patch\build_all.ps1 -TdExe 'D:\Anlogic\TD6.2.1\bin\td_commands_prompt.exe'
```

脚本与三个阶段现在从所选 TD 安装目录定位 `arch/ph1_35p.db`，不再固定使用 F 盘；器件速级保持3。默认完整执行 A→B→C，不使用 SkipA/SkipB。

构建前，脚本将本次会覆盖的旧日志、数据库、bit和报告移入 `td_project/build_history/时间戳/`，本步没有启动这个过程。构建后核对：

- `pA.log`：`PHASE_A_DONE ERR=0`；
- `pB.log`：`VERIFIED_COUNTER_SELECTORS12`、`PATCH_FINISHED`；
- `pC.log`：`CHECK valid_2d=2 valid_3d=14`、`PHASE_C_DONE ERR=0`；
- `camera_to_dsi_display_phy.area`、`camera_to_dsi_display_phy.ts`、`patched_final_timing.rpt`；
- 新生成的 `camera_to_dsi_display.bit` 时间与 SHA256。

用户提供的图像基线为 SWNS +0.128ns、HWNS +0.020ns、约9100 LUT/9300 REG/10300 Slice、43 ERAM、31 DSP。它是图像版本的实测对照，不是接入后资源或时序的承诺。参考振动链使用剩余约9个DSP，需重点检查本次完整报告。

## 静态检查

```powershell
python .\tools\check_all_inst.py
python .\tools\check_vibration_stage1.py
```

后者读取实际 multi/peak 系数和编码表达式，验证816个状态地址、全部17个频点映射、612组幅度/相位/噪声组合及48块独立算术模型。未使用 HDL 仿真器；不覆盖 ERAM 时序、控制状态机、CDC 或目标确认逻辑。

`uart_log_debug.v` 由 `tools/gen_uart_log2.py` 生成，修改字段后可重生成。当前共38个字段，字段号6bit；每轮打印对所有变动字段统一快照。

## 用户上板顺序

依次测试静止、3Hz、8Hz、10Hz，每组至少30秒；等首个完整测频/确认窗口更新后再判读。保存未裁剪的完整 UART 文本，并记录框所在网格。

| 检查项 | 预期 |
|---|---|
| VOFP / ITPX | `00038400`（230400） |
| VOFL / ITLN | `00000168`（360） |
| VTAP / ITER | `00000000` |
| MBFR | `00000040`（64） |
| CLRC / SCNC | `00000330`（816，分别为清零次数和频点扫描次数） |
| WINC | 完成每个窗口后递增，8bit回绕 |
| 3Hz | 对应目标 HZ 字段为 `0000001E` |
| 8Hz | 对应目标 HZ 字段为 `00000050` |
| 10Hz | 对应目标 HZ 字段为 `00000064` |

静止期关注 HZ1～HZ4、OBP1、STK0 是否归零。`ACT` 是原始能量过门的音调块数，`QACT` 是突出度与归一化能量过门的合格块数，均不等同于已确认目标数。

`OBP1` 打包四个目标位置，最低字节为目标1；每字节 bit6=有效，bit5:3=row（0～5），bit2:0=col（0～7）。显示每格160×120，分析每格80×60。

`WPRD` 是相邻窗口结果发布间隔的50MHz时钟数；忽略含启动过程的首个值，后续可用 `fs≈64*50000000/WPRD` 估算实际有效采样率。`FXBX/FXEN` 是 LK 诊断固定块，`PBLK/PKMG/FBPN/F04/F06/F10/F08` 是峰搜跟踪块，二者可能不同。

## 下一步边界

本步接入保留了参考版的后处理：按能量排名关联、取前四后相邻去重、最强目标确认控制整体输出。这三项已知问题尚待第二步分别修正，因此当前不能据模型检查宣称多目标稳定性已验收。原画框坐标计数和多位总线同步也暂沿用参考版。

先用本步的静止、3/8/10Hz日志确认链路运行、编码和频点，再进行目标独立确认/补选，最后调整阈值。
