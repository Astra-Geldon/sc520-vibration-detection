# 裁剪前高光压缩：验证与编译记录

> **历史记录，不作为当前版本操作说明**：本文保留当时实验、测量及计划；其中“当前/已烧录/下一步”、算法开关、资源和本机路径仅适用于文内历史版本。当前五拨码最终版以[README](../../README.md)及[算法说明](../../CURRENT_ALGORITHMS.md)为准。


生产源码：`fe3fec7`，分支`image-highlight-shoulder-20261031`。
用户需求与菜单说明见根目录`HIGHLIGHT_COMMON_SHOULDER_20261031.md`。

已通过数学核对、核心RTL两个参数分支的1,070,624组独立对照、完整TD A→B→C及报告中的setup/hold检查。完整流水34帧、5,834,789周期、5,775,360次DDR读取一致，八个生产输入哈希匹配冻结源。2026-10-31 19:19:52 JTAG SRAM烧录成功。用户随后确认P压光有效但偏红，不接受这个代价，画质验收未通过。源码/bit不变，原因及后续方向见根目录`HIGHLIGHT_PINK_REVIEW_20261031.md`。

| 文件 | 内容 |
|---|---|
| `source_inputs.json` | 260份冻结输入SHA、源码提交与实际编译快照路径 |
| `build.json` | LUT6/Slice/FF/ERAM/DSP、时序、bit哈希和验收状态 |
| `kernel.json` | 内部峰值及预计算宽峰值两分支，对独立有理数oracle比对 |
| `math.json` | 肩部系数的独立数学、位宽、单调性和参考等价核对 |
| `pipeline.json`、`pipeline_completion.json` | 实际顶层宽RGB/峰值/元数据寄存、tone/OSD/mixer与参考链对照，以及源哈希核对 |
| `programming.json`、`delivery.json` | 成功下载、bit哈希、资源和交付状态；偏红反馈记录在delivery与build中 |
| `prior_timing_failures.json` | 前两次未达标构建，均未烧录 |
| `pink_screenshot_metrics.json` | 八图SHA、OSD、同曝光ROI与统计边界 |
| `pink_integer_mechanism.json` | RGB9/RGB8颜色基准、生产公式及直接替换反例 |
| `pink_repair_audit.md` | 独立复核：亮度与颜色不能靠直接换输入同时保持 |

最终布局为10012 LUT6、11175 Slice、9565 FF、43 ERAM、34 DSP；SWNS/HWNS为+0.161/+0.020ns，STNS/HTNS均为0。原工程完整板级时序覆盖限制保留，本记录不宣称完整板级时序签核。

核心验证可从工程根目录运行`python tools/test_highlight_shoulder.py`，流水验证为`python tools/test_highlight_pipeline.py`。生成的仿真文件与日志默认放在`D:/FPGA/codex/_build/20261029project/highlight-common-shoulder-20261031/`下的`kernel_checks/`、`pipeline_checks/`，不进入源码目录。完整TD快照、bit和原始日志放在`compile-v3/`，成功下载日志为`burn-v1/`。

两个旧构建只用于追溯时序修正，不能作为通过镜像下载。当前候选在mixer原有首级寄存同时捕获宽RGB、9位峰值、mode/sel等元数据，寄存后查表并应用共同系数；总像素延迟、DDR读取请求、原img_proc与mixer结构保持。
