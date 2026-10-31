# 几乎成功版证据

> **历史记录，不作为当前版本操作说明**：本文保留当时实验、测量及计划；其中“当前/已烧录/下一步”、算法开关、资源和本机路径仅适用于文内历史版本。当前五拨码最终版以[README](../../README.md)及[算法说明](../../CURRENT_ALGORITHMS.md)为准。


生产源码`442677e`，分支`image-almost-success-fixed-20261101`。2026-11-01 00:45:36完成JTAG SRAM下载，固定E900/G12/N1。画质待用户确认。

- `numeric.json`：固定N1与b8407f8全部系数及98688组RGB精确相同，43104组高光逐位旁路。
- `pipeline.json`：真实顶层抽取，两完整720p帧及4模式片段，2334720次读取、总视频延迟不变。
- `sensor.json`：ID读取、165条初始化写及8条分组写和握手周期对照；仅删除6次验收读回。
- `ui_osd.json`：正常按键去抖/模式和算法名、Logo对照；测试文字区域明确删除。
- `preservation.json`、`core_ports.json`：必要PLL/MCU/摄像头/ISP/DDR/HDMI接线和上电时序保持。
- `build_manifest.json`、`programming.json`：布局资源、真实正时序、SHA与双下载成功判据；未写Flash。
- `resource_comparison.json`：本轮、截图版和A＋Logo三份实际报告的路径、SHA及资源变化。
- `cleanup_sources.json`、`feedback.json`：工程列表清理范围及用户选定截图SHA。
- `bitstreams.json`：新旧bit源码/SHA；二进制放在_build，不入Git。

完整产物：`D:/FPGA/codex/_build/20261029project/almost-success-fixed-20261101/`。发布bit别名为`bitstreams/几乎成功版.bit`。

当前验证入口为`tools/test_fixed_sensor.py`、`tools/test_fixed_ui_osd.py`、`tools/test_fixed_n1_pipeline.py`，均用`--output <_build目录>`。旧实验版本从b8407f8及其历史分支找回；其旧验证工具需要对应历史RTL，不能用于当前固定接口。
