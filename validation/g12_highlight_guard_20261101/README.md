# 保护亮端的N1/N2候选证据

> **历史记录，不作为当前版本操作说明**：本文保留当时实验、测量及计划；其中“当前/已烧录/下一步”、算法开关、资源和本机路径仅适用于文内历史版本。当前五拨码最终版以[README](../../README.md)及[算法说明](../../CURRENT_ALGORITHMS.md)为准。


生产源码`6dcd758`，分支`image-highlight-guard-20261101`。2026-11-01 00:20:41完成JTAG SRAM下载，默认E900/G12/N1；KEY4为N1→N2→L0→L1。画质仍等待用户比较。

- `numeric.json`：独立峰值目标、原L1逐位保持、高光逐位等于输入、UI/AE/模式检查。
- `pipeline.json`：实际顶层抽取，两完整720p帧及16片段，总视频延迟不变。
- `osd.json`：未改OSD生产源码，按SHA引用上一轮已完成验证；顶层接线由本轮流水另测。
- `cdc.json`、`timing_qualification.json`：本轮提取真实代码的CDC检查，原始−0.006ns仅首级同步器；不声称全局时序签核。
- `preservation.json`：261项生产输入，相对860d4ac仅候选LUT与默认档位改变。
- `build_manifest.json`、`programming.json`：真实资源、时序、bit SHA和双成功下载日志判据。
- `bitstreams.json`：新旧bit源码及SHA；二进制保存在_build，不入Git。
- `curve_design.json`、`feedback.json`：设计节点及用户反馈原图SHA；不把不同构图做逐像素画质比较。

完整产物、工具脚本、冻结源码、原图与TD日志：`D:/FPGA/codex/_build/20261029project/g12-highlight-guard-20261101/`。

可复现的真实RTL验证脚本：`tools/test_natural_lift.py --output <_build目录>`、`tools/test_highlight_pipeline.py --output <_build目录>`；`tools/generate_guarded_lift.py`仅再生成N档系数，默认不写入RTL，`--write`才修改。
