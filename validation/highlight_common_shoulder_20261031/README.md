# 裁剪前高光压缩：验证与编译记录

生产源码：`fe3fec7`，分支`image-highlight-shoulder-20261031`。
用户需求与菜单说明见根目录`HIGHLIGHT_COMMON_SHOULDER_20261031.md`。

当前已通过数学核对、核心RTL两个参数分支的1,070,624组独立对照、完整TD A→B→C及报告中的setup/hold检查。完整视频流水回归仍在进行，尚未烧录当前候选，也没有画质验收结论。

| 文件 | 内容 |
|---|---|
| `source_inputs.json` | 260份冻结输入SHA、源码提交与实际编译快照路径 |
| `build.json` | LUT6/Slice/FF/ERAM/DSP、时序、bit哈希和验收状态 |
| `kernel.json` | 内部峰值及预计算宽峰值两分支，对独立有理数oracle比对 |
| `math.json` | 肩部系数的独立数学、位宽、单调性和参考等价核对 |
| `prior_timing_failures.json` | 前两次未达标构建，均未烧录 |

最终布局为10012 LUT6、11175 Slice、9565 FF、43 ERAM、34 DSP；SWNS/HWNS为+0.161/+0.020ns，STNS/HTNS均为0。原工程完整板级时序覆盖限制保留，本记录不宣称完整板级时序签核。

核心验证可从工程根目录运行`python tools/test_highlight_shoulder.py`。生成的仿真文件与日志默认放在`D:/FPGA/codex/_build/20261029project/highlight-common-shoulder-20261031/kernel_checks/`，不进入源码目录。完整TD快照、bit和原始日志均放在同一阶段目录的`compile-v3/`。

两个旧构建只用于追溯时序修正，不能作为通过镜像下载。当前候选在mixer原有首级寄存同时捕获宽RGB、9位峰值、mode/sel等元数据，寄存后查表并应用共同系数；总像素延迟、DDR读取请求、原img_proc与mixer结构保持。
