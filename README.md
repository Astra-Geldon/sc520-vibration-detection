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
  gen_osd_assets.py             生成 OSD 的 Logo ROM + 汉字点阵 ROM（可复现）
  burn.ps1                      一键烧录（判定 PRG-2014，纯 ASCII 避免 PS5.1 解析问题）
  capture.ps1                   暖机感知抓帧（区分"设备被占用"与"真没信号"，自动跳过黑帧）

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
| `IMG_MODE_KEY` | `design_top_wrapper.v` 第 81 行 | **打开** | 允许板载按键运行期切换图像处理模式；注释掉则退回编译期固定 `IMG_MODE` |
| `OSD_ON` | `design_top_wrapper.v` 第 93 行 | **打开** | OSD 叠加（右上角安路 Logo + 左上角算法名）；注释掉则 mixer 直接吃 `img_proc` 输出 |
| `AWB_BYPASS` | `isp/isp_top.v` 第 2 行 | **关闭** | 旁路 FPGA 白平衡（仅用于颜色对比实验，**不要长期打开**）|

关闭 `VIB_ON` 时释放约 12,400 个 slice，只保留视频通路和串口日志。

---

## 5. 图像处理模式切换（板载按键）

**基础要求 2.3(2)**：在显示通路上插入基础图像处理，并可在运行期切换。

### 5.1 按键

板载 4 个轻触按键（按下 = 低电平，内部上拉）。**按一下就锁定，不需要一直按住。**

| 按键 | FPGA 引脚 | 功能 |
|---|---|---|
| KEY1 | D5 | **原图**（像素 1:1 直通，等于不插本模块）|
| KEY2 | A9 | **基础算法组循环**：灰度 → 二值化 → 边缘(Sobel) → 灰度 …<br>（当前是原图或扩展算法时，按下先进入灰度）|
| KEY3 | B9 | **扩展算法组循环**：以后新加的算法<br>⚠ 目前扩展组为空（`EXT_N = 0`），**按下没有任何效果** |
| KEY4 | C7 | 保留，暂不使用 |

上电默认 **原图**（`localparam IMG_MODE = 0`）。

**给以后加算法的接口**：`img_mode_sel.v` 顶部有两个参数

```verilog
parameter integer EXT_BASE = 4,   // 第一个"扩展算法"的模式码
parameter integer EXT_N    = 0    // 扩展算法个数（现在还没加，所以是 0）
```

加了一个新算法后，把 `EXT_N` 改成 1，KEY3 立刻就能循环到它，**不用改任何按键逻辑**。

| 模式码 | 算法 | OSD 标签 | 延迟 |
|---|---|---|---|
| 0 | 原图（直通） | 原图 | 0 |
| 1 | 灰度 `(R+2G+B)>>2` | 灰度 | 0 |
| 2 | 二值化（自适应阈值） | 二值化 | 0 |
| 3 | **Sobel 边缘检测**（3×3） | 边缘 | **1 行 + 2 像素** |

### 5.2 实现

```
video_out.O_vdieo_data ──► img_proc ──► hdmi_mixer.I_video_rd_data
                              ▲
                      img_mode_sel（10ms 去抖 + 按下锁存）
                              ▲
                        I_key[3:0] = D5/A9/B9/C7
```

- `img_proc.v`：各模式的逻辑**同时存在**，输出是纯组合 mux。模式 0/1/2 **零拍延迟** ——
  这样 `hdmi_mixer` 内部 2 级数据/DE 对齐的假定依然成立，mixer / vtc / hdmi_tx 一行都不用改。
- **模式 3（Sobel）例外**：3×3 邻域必须缓存前两行，输出比输入晚 **1 行 + 2 像素**，
  画面整体下移 1 行（720 行里的 1 行，肉眼不可见）。前 2 行行缓存未填满时强制输出黑。
  彻底消除需改 mixer（`rd_en` 与"绘制选择"拆开 + 1650 bit 移位寄存器，约 +2,500 slice），
  方案见 `docs/算法添加方法.md` §1。
- 二值化的帧累加器**始终运行**，切到二值化时阈值已经是上一帧真实均值，
  不会出现"切换后第一帧按复位值 48 判"的突变。
- `img_mode_sel.v`：独立模块，只用 `I_key`，不碰 ISP / AWB / 振动 / HDMI 核。

### 5.3 资源

| 项 | 用量 | 全片 |
|---|---|---|
| slice | **10,176** | 21,216（**47.96%**）|
| 寄存器 | 9,281 | 42,432（21.87%）|
| LUT6 | 9,021 | 21,216（42.52%）|
| ERAM | 43 | 108（39.81%）|
| DSP | 20 | 40（50.00%）|
| **PLL** | **3** | 6（**50.00%**）|
| 时序 | SWNS **+0.112 ns** / HWNS **+0.020 ns** | 无违例 |

> **AWB 架构改造（2026-10-24）**：厂商 `awb.v` 原本用两个 50 级流水线除法器
> （`divider` IP）逐像素算增益，占 `u_awb` 的 90%。改成**行末锁存 + 48 拍串行除法**
> 后，`u_awb` 从 1,919 lut / 2,292 ripple / 6,098 seq 降到
> **436 lut / 172 ripple / 783 seq**，**整片 slice 从 14,819 降到 10,176（省 4,643）**。
> 数据延迟链 `signal_delay(50 拍)` 未改，所以下游时序完全不变；
> 白平衡效果实测一致（RGB 三通道差 4.6 → 4.5），对比度反而更好（std 22.5 → 26.2）。

> **时钟方案（2026-10-24 简化）**：HDMI 用主 PLL 直接输出 **75.000 / 375.000 MHz**
> （clk4/clk5），刷新率 60.606 Hz。原来那套两级 `pll_hdmi_7425`
> （50→27→74.25/371.25）已删除，**PLL 占用从 5/6 降到 3/6**。
> 实测 75 MHz 采集卡可稳定锁定（连续 153 帧无黑帧）。

其中算法部分：`u_img_proc` 368 lut / 67 ripple / 158 seq / **768 dram lut**，
`u_osd_overlay` 54 lut / 26 f7mux / 13 f8mux，
`u_img_mode_sel` 42 lut / 40 ripple / 52 seq。

> ⚠ **768 个 `dram lut` 就是 Sobel 的 3 个行缓存**（3×2048×8 bit ÷ 64 bit/LUT）。
> 综合日志虽然报 `Inferred 17 RAMs`（+3），但 TD 把它们实现成了 LUTRAM 而不是 ERAM，
> 一度让 slice 从 66.21% 涨到 71.33%（+1,085）。想省回来需要改成单数组 + 真双口，见算法添加方法 §7.2。

### 5.4 板上验证（2026-10-23）

- **4 个按键全部实测正常**，四种模式均可切换
- 原图：mean ≈ 107 / uniq ≈ 27000（彩色画面，像素未被改动）
- 灰度：`mean|R−G| = mean|G−B| = 0.000`，三通道最大差 0，202 级灰阶
- 二值化：中间灰（32~224）**0.01%**，两级占比 99.28%
- **Sobel**：mean ≈ 9.5 / uniq ≈ 4,000，瓷砖接缝清晰成线、平坦区全黑；
  OSD 标签自动显示「边缘」（字模追加「边」「缘」后生效）

### 5.5 注意

`pin.adc` 里原有的 `I_button[0] = N2`、`I_button[1] = J14` 经开发板手册核对
**不是板载按键**（属历史遗留）。因此 `ae_set` 的曝光加减键实际上从未生效。
为避免影响既有逻辑，本功能没有复用它们，而是新增独立端口 `I_key[3:0]`。

### 5.6 OSD 叠加（基础要求 2.3(4)）

`osd_overlay.v` 插在 `img_proc` 与 `hdmi_mixer` 之间，叠加两样东西：

| 位置 | 内容 | 实现 |
|---|---|---|
| 右上角 (1136,16) | **ANLOGIC 安路 Logo**，128×80，深蓝 A + 红色条纹，白底透明 | `osd_logo_rom.v`：640 条 case 的 LUT ROM，每 32 bit 装 16 像素（2 bit/像素） |
| 左上角 (24,24) | **当前算法名**，16×16 汉字点阵，黑底白字 | `osd_font_rom.v`：7 个字形 × 16 行，case ROM |

- Logo 素材取自厂商资料 `0 准备/HX1P35A_Contest_202606/.../lab_ex_3_tf_sdram_vga/图片/logo.bmp`
  （640×480 的官方 Logo），离线裁剪、缩放到 128×80 并量化为 3 类（透明/深蓝/红）。
- 叠加仍是**纯组合 3 选 1**，数据零延迟，`hdmi_mixer` 的 2 级对齐不受影响。
- 文字随 `I_mode` 实时变化：`原图` / `灰度` / `二值化`。
- 资源：`u_osd_overlay` 56 lut / 39 seq / 13 f7mux，整片 slice 66.21%（+286）。

**扩展新算法**见 `docs/算法添加方法.md`（四步：加 img_proc 分支 → 登记字模起始序号 →
追加汉字 → 选按键；含零延迟约束、资源预算、常见坑）。

---

## 6. 串口日志

115200 8N1，每秒一行。当前字段：

| 字段 | 含义 |
|---|---|
| `SEC` | 上电后的秒数 |
| `VSUM` | 抽头每帧 Σ灰度（230,400 像素的累加和，可用来判断画面亮度）|

打开 `VIB_ON` 后还有 LK / Goertzel 相关的诊断字段。

**字段表在 `tools/gen_uart_log2.py` 里改，然后重新运行生成器** —— 不要手改 `uart_log_debug.v`。
标签必须**恰好 4 个字符**，否则生成器报错。

---

## 7. 已知限制

- **画面偏暗**：传感器在室内只输出约 43/255。曝光已设为最大值（1991）+
  16 倍模拟增益。要真正变亮需要自动曝光 / HDR，靠伽马只能提亮但会引入灰雾。
- **振动检测需要块内有纹理**：纯色物体内部没有梯度，测不到。
  纹理选块用 `Σ min(ix², iy²)`，只在一维纹理的块会因 `det` 门限被拒绝。
- **20 Hz 以上**：Nyquist 为 29.75 Hz，理论上可测，但曝光模糊会使幅度衰减。
- **全屏 48 块检测**：存储推断（ERAM）问题尚未解决，属于后续工作。

---

## 8. 版权说明

`user_source/hdl_source/` 下的 `isp/`、`ph1p35_ddr/`、`uics520_cfg/`、
`uiisp_beta/` 等目录来自**米尔联科（MiLianKe）** 的参考设计，文件头明确标注
`All rights reserved` / `only used for learning`。

**因此本仓库必须保持私有**，不得公开发布。
`vibration/`、`vib_lk_grid.v`、`tools/` 下的脚本为本项目原创。
