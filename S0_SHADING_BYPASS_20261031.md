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

已完成JTAG烧录。用户随后提供3张截图并反馈旁路后质感明显变差，旁路版不作为发布候选，原有表继续保留；烧录/反馈记录见 `validation/s0_shading_bypass_20261031/`。

图1的OSD实际为“原图0/H1/C0”，图2为“原图3/H1/C3”，图3为“原图3/C3/D3”，第三张不是原图0。三张图还有明显构图/旋转变化，不能从各自的局部JPEG频率统计量化归因于shading，不能据此判定LUT极性。LSC不直接去除随机噪声，但会改变后续H1/C3输入最大通道、保护掩码和补偿倍率，因此仍可改变整体质感。

已重新打开 `SHADING_ON` 并恢复关闭前的E1 bit，SHA256 `7E1E1F74341703F535C63499E5425B90F73C50F293BFC634EE82639EDE7613BD`；`user_source`已与 `a2e58a9` 基线逐文件核对一致。恢复下载日志在 `_build/20261029project/shading-on-restore-20261031/program-verified.log`，包含 `PRG-2014` 和 download 完成记录。原旁路bit和分支保留。恢复后画面是否回到之前观感仍待用户确认。

S1下一步先保持镜头/照明/曝光与C3/D0固定，从均匀平场验证现有表残差；只有候选在相同条件下优于现有开启版本才替换表值，不直接由这3张非平场截图生成LUT。
