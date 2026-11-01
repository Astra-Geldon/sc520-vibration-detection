# 紧凑 OSD 与字符预取验证

目标工程：`D:\workplace\anlogic\sc520-vibration-detection-main`。2026-11-01。

本轮唯一修改的生产 RTL 为 `user_source/hdl_source/osd_overlay.v`。LAT 计时模块、图像算法、振动算法、DDR 访问、顶层连接及约束均未修改。用户负责 TD 编译和烧录；本轮仅运行局部 Icarus 栅格仿真及静态检查。

## 显示变化

| 项目 | 修改前 | 当前默认 1280×720 |
|---|---|---|
| 英文字模实际笔画 | 10×14，2× 放大 | 5×7，原生大小 |
| 字符节距 | 16 | 8 |
| LAT 黑底 | 208×32 | 104×16，x=92..195、y=24..39 |
| LAT 文字起点 | (96,24) | (96,28) |
| 状态黑底 | 592×64 | 296×32，x=20..315、y=684..715 |
| 状态文字起点 | (24,656) | (24,688) |
| 状态列距/行距 | 192/32 | 96/16 |

状态仍为三列两行，标签顺序及开关映射不变：S1 AWB、S2 GAM、S3 CSC / S2 N1、S5 EXP、S4 DEM。绿色 ON、灰色 OFF、黄色 WAIT；WAIT 优先。中文模式名和安路 Logo 保持原尺寸。

## 优化机制

原实现从像素坐标组合地产生 ASCII、35 位字模、动态位索引，最后选择输出颜色；用户上一版报告中该路径为 12 级逻辑。

当前在字符开始前两拍（x mod 8 = 6）译码下一个字符，在前一拍（x mod 8 = 7）寄存其当前行的 5 位字模。当前像素只执行五个位的选择及颜色覆盖。两处文本起点均按 8 像素对齐，不依赖消隐长度。

约 20 位新增文字元数据寄存器，没有新增 DSP、ERAM、像素流水级或 DDR 请求。缩小黑底本身不等于硬件资源按面积缩减；布局布线影响仍需用户构建验证，不能预先宣称 Slice 已减少。

## 已完成检查

- `LATENCY_OSD_PASS pixels=3686400 panel_pixels=6656 status_pixels=37888`。
- 四个完整 720p 帧覆盖原图、灰度、二值化、边缘；LAT 覆盖所有十进制数字、小数点、单位和无效横杠。
- 六项状态覆盖全部 ON、全部 OFF、全部 WAIT 和混合状态；独立字模参考逐像素检查文字、边界及配色。
- LAT 帧内更新不撕裂、失效结果能替换已有值；两面板各自禁用、同时禁用和 OSD 完全旁路均检查通过。
- 新面板外与原模式名、Logo、原视频参考逐像素一致；无新增视频延迟。
- `LATENCY_INTEGRATION_PASS`：端口、文件登记、原 DDR 控制逻辑一致；Tcl 模拟命令检查 34 组 CDC 集合。该项不代表真实物理时序验收。

复现：工程根目录运行 `python tools/test_video_latency_osd.py`、`python tools/check_video_latency_integration.py`。历史 `tools/test_six_switch_osd.py` 针对大字体旧版，不用于本次尺寸验收。

`sim_osd/frame.png` 是生产 RTL 仿真输出的完整布局预览，背景和 LAT 210.9 MS 均为测试数据，不是硬件图像或实际测量值。`compact_panels_preview.png` 将实际两处裁剪图放大 2 倍，便于检查笔画。

`before/` 保存修改前文件，`before_sha256.json`、`after_sha256.json` 和 `changes.patch` 供本机审阅；仿真输出和原件备份未注册进 TD，且由 Git 忽略。助手未运行 TD 或操作硬件。

用户后续生成的紧凑 OSD GUI 物理报告：LUT6 18681、REG 17029、Slice 19329、DSP 40、ERAM 66，SWNS +0.012 ns、HWNS +0.020 ns，STNS/HTNS 为 0。对比大字体 LAT 版 Slice 19334，仅减少 5，未实现明显资源下降。`latest_td_report.json` 保存本机报告摘要；不据此宣称补丁、真实 CDC 审计或本版上板验收已完成。
