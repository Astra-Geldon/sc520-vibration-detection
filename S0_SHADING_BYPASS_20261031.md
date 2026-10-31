# S0 空间阴影校正旁路对照

工作区：`D:/FPGA/codex/20261029project`  
分支：`image-s0-shading-bypass-20261031`

## 本轮改动

本轮只在 `user_source/hdl_source/design_top_wrapper.v` 注释掉 ``SHADING_ON``，旁路 `color_shading.v`。厂商 AWB、`img_proc`、H1/C3、D 降噪、OSD/Logo、DDR 和 HDMI 时序均未改动。该版本用于确认现有颜色阴影表是否造成了空间偏色，不能作为最终发布版本。

## 完整编译

在 `_build/20261029project/s0-shading-bypass-20261031/compile-v1/source` 冻结副本中执行完整 A→B→C：

- A：`PHASE_A_DONE ERR=0`
- B：`PATCH_FINISHED`、`VERIFIED_COUNTER_SELECTORS12`
- C：`PHASE_C_DONE ERR=0`、`CHECK valid_2d=2 valid_3d=14`
- 时序：`SWNS=+0.145 ns`、`HWNS=+0.020 ns`、`STNS=0`、`HTNS=0`
- bit SHA-256：`7FAB80DB751EE10A7F01E1A783D3F1C4B72E7ABF9965E896E6BEFB4B5A63F9CA`

资源：LUT6 `10927/21216`、Slice `12075/21216`、FF `10163/42432`、ERAM20K `52/108`、DSP `26/40`、PLL `3/6`、MCU `1/1`。

相对 E1 编译记录，旁路减少 LUT6 119、Slice 105、DSP 8；ERAM、PLL 和 MCU 不变。DSP 下降只说明颜色阴影乘法路径已被移除，不代表画质更好。

## 产物与待验证项

bit 和日志位于：

`D:/FPGA/codex/_build/20261029project/s0-shading-bypass-20261031/compile-v1/`

当前尚未烧录，`board_visual_validation=pending`。上板后必须固定同一场景、同一曝光和同一 AWB 状态，与当前开启 shading 的版本对比中心/四角颜色、亮度和视频稳定性。若旁路明显改善空间偏色，进入 S1 重新生成 10×1 Q8 表；若旁路无变化，应回查更早的 sensor/ISP/光学路径。
