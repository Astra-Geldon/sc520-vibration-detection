# 近白高光颜色保护：验证与交付记录

生产源码`a7a12be`，分支`image-highlight-white-protect-20261031`。实现和菜单见根目录`HIGHLIGHT_WHITE_PROTECTION_20261031.md`。

| 文件 | 内容 |
|---|---|
| `source_inputs.json` | 冻结输入SHA与生产源码提交 |
| `build.json` | 完整A→B→C、最终资源/时序、bit SHA和各项验证摘要 |
| `legacy_kernel.json` | 原肩部两参数分支的1,070,624组回归 |
| `white_kernel.json` | 新增保护820,769组独立整数oracle对照、原峰值/近似Y误差 |
| `menu.json` | 11档循环、复位/去抖/长按及20,328个实际OSD字模像素 |
| `pipeline.json` | 实际顶层46帧像素/同步/DDR请求回归 |
| `boundary_examples.json` | W3/W1/W2分层门槛的输出色阶反例 |
| `programming.json` | JTAG SRAM下载与bit SHA，不含Flash写入 |

核心复现：`python tools/test_highlight_white.py`；流水复现：`python tools/test_highlight_pipeline.py`。脚本默认产物写入本机`D:/FPGA/codex/_build/20261029project/highlight-white-protection-20261031/`，Git不包含bit或工具日志。

当前候选保留原肩部曲线与修正前峰值，W0～W3仅改变近白削顶风险像素的额外色度。源码`highlight_white_prepare.v`没有新乘法、寄存或存储。最终布局10197 LUT6、11350 Slice、9561 FF、43 ERAM、34 DSP；SWNS/HWNS +0.105/+0.020ns，STNS/HTNS为0。继承的外部时序覆盖限制保留，功能/时序通过不替代用户画质验收。

强档存在分层门槛可能形成色阶的已知边界，正常较暗区域逐位旁路；实际偏粉是否改善、浅色实物是否保真以及移动视频仍须用户比较。大体积原始证据、冻结输入、bit和烧录日志保留在对应`_build`目录。
