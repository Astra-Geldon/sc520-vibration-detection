# C3保亮色度降噪：本地编译证据

> **历史记录，不作为当前版本操作说明**：本文保留当时实验、测量及计划；其中“当前/已烧录/下一步”、算法开关、资源和本机路径仅适用于文内历史版本。当前五拨码最终版以[README](../../README.md)及[算法说明](../../CURRENT_ALGORITHMS.md)为准。


源码提交：`1dfa1d78673a75d798ed1ef29bc1af36f2a25820`。分支：`image-c3-denoise-study-20261031`。

这批证据属于断电条件下的离线验证和完整TD编译，**没有烧录、没有上板画质验收**。默认原图3（曝光900）＋C3＋D0，KEY4循环D0/D1/D2/D3，OSD显示`C=3 D=n`。使用方法和最终资源见 [专项说明](../../C3_CHROMA_DENOISE_20261031.md)。

- `build_summary.json`：bit SHA、实际资源和时序、未上板状态、其他证据的SHA。
- `source_manifest.json`：353个冻结源码文件的SHA、Git来源、TD工程路径重定位记录。
- `core_stream_summary.json`、`core_simulation.txt`、`stream_simulation.txt`：独立数值参考、四个完整720p帧、固定点亮度保持、同步/状态及窗口坐标检查。
- `pipeline_summary.json`、`pipeline_simulation.txt`、`denoise_label_simulation.txt`：真实顶层接线、旧C3拓扑对照、DDR读请求、OSD/Logo和KEY4验证。
- `preservation.json`：225个未改变的已有生产HDL/IP文件SHA。

完整构建数据库、bit和TD报告在 `D:/FPGA/codex/_build/20261029project/c3-chroma-denoise-20261031/compile-v1`，不会提交松散编译缓存。仿真使用同步NOREG RAM行为模型；最终物理实现使用器件ERAM。

本轮完整A→B→C包括12个HDMI选择器网表补丁；SWNS/HWNS为+0.140/+0.020ns，总负裕量为0。原有完整板级时序签核限制仍保留，不能以此替代明早的实际视频观察。
