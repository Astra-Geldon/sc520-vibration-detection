# SC520 MIPI → HDMI 振动频率检测系统

全国大学生嵌入式芯片与系统设计竞赛 2026 · FPGA 赛道 · 安路科技
**选题二：基于安路 PH1P35 的实时数字图像处理系统**

---

## 1. 项目概述

在安路 `PH1P35MDG324`（-3 速级）上实现：

```
MIPI 摄像头 SC520CS ──► CSI-2 接收 ──► ISP（去马赛克/白平衡/伽马）
                                            │
                                            ├──► DDR2 帧缓存 ──► HDMI 1280×720@60 输出
                                            │
                                            └──► 振动频率检测（Lucas-Kanade + Goertzel）
                                                      │
                                                      └──► UART 日志
```

**核心算法**：用 LK 光流逐帧估计"帧差图"的运动，对一个纹理最强的图像块做
17 点 Goertzel 频谱分析，输出该物体的振动主频（2.0~10.0 Hz，分辨率 0.5 Hz）。

实测：3.0 / 5.0 / 8.0 / 10.0 Hz 均能正确识别，横竖屏手机方向无关。

---

## 2. 目录结构

```
user_source/
  hdl_source/
    design_top_wrapper.v        顶层：时钟/复位/DDR 仲裁/各模块连线
    vib_lk_grid.v               LK 光流 + 8×6 分块累加 + 纹理选块 + 求解
    uart_log_debug.v            串口日志（由 tools/gen_uart_log2.py 生成，勿手改）
    vibration/
      vib_video_tap.v           视频抽头：2×2 平均 → 640×360 灰度
      vib_gauss3x3.v            3×3 高斯平滑
      vib_prev_frame_ddr.v      帧差 It（读上一帧，与当前帧相减）
      vib_div_serial.v          48/32 串行除法器
      vib_goertzel.v            17 点 Goertzel（128 帧窗口）
      vib_gz_store.v            频率结果存储（存 RAM 推断试验）
      vib_osd_marker.v          屏幕标记（固定块外框）
    isp/                        ISP 流水线（厂商参考设计 + 本项目修改）
    ph1p35_ddr/                 DDR2 控制器（厂商 IP）
    uics520_cfg/                SC520CS 寄存器配置（厂商参考设计）
  constraints_source/
    pin.adc                     引脚约束
  ip_source/                    IP 核（PLL / DDR / FIFO 等）

tools/                          开发与验证脚本（本项目编写）
  gen_uart_log2.py              从字段表生成 uart_log_debug.v
  check_ports.py                例化端口与模块定义一致性检查
  check_all_inst.py             全部例化的端口检查
  lint_duplicate_decl.py        重复声明检查
  lint_proc_assign.py           在 always 块里赋值的信号又被 assign 检查
  lint_multidriver.py           多驱动检查
  lint_signed_select.py         有符号向量 part-select 检查
  lint_reserved_word.py         Verilog 保留字误用检查
  verify_all.py                 顶层连线 vs 串口字段交叉验证
  verify_diag.py                诊断字段路径验证
  model_goertzel.py             Goertzel 位精确 Python 模型
  check_goertzel_rtl.py         RTL vs 模型比对
  model_serial_div.py           串行除法器位精确模型
  check_div_rtl.py              除法器 RTL vs 模型比对

VIBRATION_PORT_PLAN.md          振动模块移植计划
```

---

## 3. 编译方法

1. 用 **Anlogic TD 6.2.1** 打开 `td_project/camera_to_dsi_display.al`
2. 综合 → 布局布线 → 生成比特流
3. 烧录 `td_project/*_Runs/phy_1/*.bit`

**不要在 TD 里改 `settings.cfg` 的 `set speed 3`** —— 那是器件速级，改成 4 会时序失败。

每次编译后**先看两个指标**：
- `SWNS > 0`
- `NUM_FEPS == 0`

比特流生成成功不等于设计能跑。

---

## 4. 编译开关

| 宏 | 位置 | 默认 | 作用 |
|---|---|---|---|
| `VIB_ON` | `design_top_wrapper.v` 第 61 行 | **关闭** | 打开整条振动检测链路 |
| `AWB_BYPASS` | `isp/isp_top.v` 第 2 行 | **关闭** | 旁路 FPGA 白平衡（仅用于颜色对比实验，**不要长期打开**）|

关闭 `VIB_ON` 时释放约 12,400 个 slice，只保留视频通路和串口日志。

---

## 5. 串口日志

115200 8N1，每秒一行。当前字段：

| 字段 | 含义 |
|---|---|
| `SEC` | 上电后的秒数 |
| `VSUM` | 抽头每帧 Σ灰度（230,400 像素的累加和，可用来判断画面亮度）|

打开 `VIB_ON` 后还有 LK / Goertzel 相关的诊断字段。

**字段表在 `tools/gen_uart_log2.py` 里改，然后重新运行生成器** —— 不要手改 `uart_log_debug.v`。
标签必须**恰好 4 个字符**，否则生成器报错。

---

## 6. 已知限制

- **画面偏暗**：传感器在室内只输出约 43/255。曝光已设为最大值（1991）+
  16 倍模拟增益。要真正变亮需要自动曝光 / HDR，靠伽马只能提亮但会引入灰雾。
- **振动检测需要块内有纹理**：纯色物体内部没有梯度，测不到。
  纹理选块用 `Σ min(ix², iy²)`，只在一维纹理的块会因 `det` 门限被拒绝。
- **20 Hz 以上**：Nyquist 为 29.75 Hz，理论上可测，但曝光模糊会使幅度衰减。
- **全屏 48 块检测**：存储推断（ERAM）问题尚未解决，属于后续工作。

---

## 7. 版权说明

`user_source/hdl_source/` 下的 `isp/`、`ph1p35_ddr/`、`uics520_cfg/`、
`uiisp_beta/` 等目录来自**米尔联科（MiLianKe）** 的参考设计，文件头明确标注
`All rights reserved` / `only used for learning`。

**因此本仓库必须保持私有**，不得公开发布。
`vibration/`、`vib_lk_grid.v`、`tools/` 下的脚本为本项目原创。
