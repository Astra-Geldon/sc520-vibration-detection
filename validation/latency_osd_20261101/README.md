# 延时显示本机验证

目标工程：`D:\workplace\anlogic\sc520-vibration-detection-main`。仅实现延时计时和左上角 OSD；未运行 TD 或操作硬件。测量定义与构建命令见根目录 `LATENCY_DISPLAY.md`。

| 检查 | 结果 |
|---|---|
| 帧时间与同槽匹配 | Icarus `VIDEO_LATENCY_MONITOR_PASS samples=50` |
| OSD 像素/时序保持 | Icarus `LATENCY_OSD_PASS pixels=3686400 panel_pixels=26624` |
| TD 文件引用、顶层端口、原 DDR 控制逻辑比对 | `integration_checks.json` 通过 |
| SDC/Tcl 语法与集合计数 | 模拟 TD 命令运行通过，34 组；不代表真实时序通过 |
| 整工程 Icarus 兼容性 | 前后均有相同 36 项旧振动 RTL 声明顺序错误，见 `icarus_compatibility.json`；未更改这些模块 |
| TD 综合/资源/布线/时序、Bit、上板 | 未运行，等待用户完整 A→B→C |

复现局部测试（工程根目录，Python 3、Icarus、tclsh 需可用）：

```powershell
python tools/test_video_latency_monitor.py
python tools/test_video_latency_osd.py
python tools/check_video_latency_integration.py
```

OSD 和原逻辑比对需要本机 `before/` 原件备份；它未注册为 TD 源文件，并在 Git 忽略列表中。`before_sha256.json` 记录其他原件，`before/osd_overlay.sha256` 记录 OSD 原件。`sim_monitor/summary.json` 与 `integration_checks.json` 包含受测源码 SHA256；`after_sha256.json` 记录最终交付文件。

`changes.patch` 供本机审阅，只包含此次已有文件的修改。新增计时模块、测试与说明另列于 `after_sha256.json`。原工程基线资源详见 `LATENCY_DISPLAY.md`；不得把修改前报告当成此次源码的构建结果。
