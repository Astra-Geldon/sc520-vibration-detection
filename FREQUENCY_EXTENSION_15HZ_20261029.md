# RVER 0002000A：扩展到 15 Hz

本轮以已上板验证的 `RVER=00020009` 为基线，把活动的 48 块多目标链从 21 个频点扩展为 27 个频点，范围变为 2.0～15.0 Hz，步长仍为 0.5 Hz。64 帧窗口、能量门限、突出度、四槽选目标、连续确认、换频等待和一致性停用均保持不变。

## 频点与地址

- `Hz10 = 20 + bin × 5`，`bin=0..26`，最高编码 `150`（15.0 Hz）。
- 新增系数：12.5 Hz `8132`、13.0 Hz `6446`、13.5 Hz `4741`、14.0 Hz `3023`、14.5 Hz `1297`、15.0 Hz `-433`。
- 状态数为 `48 × 27 = 1296 = 0x510`，已有 11 位地址和 2048 深度 ERAM 足够，最高地址为 1295。
- UART 版号为 `0002000A`；`CLRC`、`SCNC` 预期为 `00000510`；频率输出不应超过 `00000096`。

## 修改范围

- `user_source/hdl_source/vibration/vib_gz_multi.v`：活动递推引擎、系数表和清空计数。
- `user_source/hdl_source/vibration/vib_gz_peak.v`：活动扫描器、系数表和 27 点扫描。
- `user_source/hdl_source/design_top_wrapper.v`：两个活动模块例化改为 27 点。
- `user_source/hdl_source/vibration/vib_osd_marker.v`：补充 12.5～15.0 Hz 的框内文字映射。
- `user_source/hdl_source/uart_log_debug.v` 与 `tools/gen_uart_log2.py`：版号和状态计数说明同步。
- 旧的 `vib_goertzel.v`、`vib_gz_store.v` 17 点对照支路保持不变。

## 已完成的本地检查

`tools/check_vibration_extension_15hz.py` 已验证 27 个纯频率和 8 个含噪样例均映射到对应 bin，并检查 1296 个状态地址连续覆盖。端口、例化、多驱动、过程赋值、重复声明、诊断链和 UART 生成器检查通过。当前环境没有 TD/iverilog，因此没有替代完整 A→B→C 编译。

## 上板前后重点

扩展后每个块的扫描拍数增加约 28.6%，不增加 Goertzel 乘法器，但可能改变 LUT、Slice、ERAM、DSP 映射和时序余量。请在 TD 中完整执行 `td_project/patch/build_all.ps1` 的 A→B→C 流程，以 `phy_1` 报告为准。

烧录后先核对 `RVER=0002000A`、`MBFR=00000040`、`CLRC=SCNC=00000510`，再单独测试 12.5、13、14、15 Hz，最后测试 3/8/11.5/12 Hz 混合四目标和换频。观察 `HZ1..HZ4` 是否稳定在目标值，且不出现大于 `00000096` 的编码；确认换频等待仍只清空变化中的槽位。
