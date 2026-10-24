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
| KEY4 | C7 | 颜色校正强度循环：0（关闭）→1（k=0.5）→2（k=0.75）→3（k=1.0）→0 |

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

### 5.3 最新资源占用（2026-10-25曝光修复版）

以下数据来自本次成功构建后的`td_project/camera_to_dsi_display_phy.area`，器件为
`PH1P35MDG324`。百分比按安路TD报告中的器件总资源计算。

|资源类型|已用|器件总数|占用率|剩余|
|---|---:|---:|---:|---:|
|IO（输入6/输出32/双向25）|63|160|39.38%|97|
|LUT6|9,457|21,216|44.57%|11,759|
|寄存器|9,371|42,432|22.08%|33,061|
|Slice|10,612|21,216|50.02%|10,604|
|F7MUX|134|10,608|1.26%|10,474|
|F8MUX|67|5,304|1.26%|5,237|
|ERAM20K|43|108|39.81%|65|
|DSP|31|40|77.50%|9|
|DDR Byte|6|12|50.00%|6|
|MIPI RX|1|2|50.00%|1|
|MIPI TX|0|2|0.00%|2|
|PAD|22|160|13.75%|138|
|PLL|3|6|50.00%|3|
|GCLK|9|32|28.12%|23|
|LCLK|0|12|0.00%|12|
|SCLK|22|48|45.83%|26|
|MLCLK|2|6|33.33%|4|
|IOCLK|4|18|22.22%|14|

时序报告为`SWNS=+0.158ns`、`STNS=0`、`HWNS=+0.020ns`、`HTNS=0`，没有时序违例。

Slice内部构成为：逻辑Slice9,532个（其中含LUT7,100个、加法器1,277个、纯寄存器
1,155个），RAM相关Slice1,080个（其中`dram lut`1,064个、移位LUT16个）。
ERAM中为43个`ERAM20K`、0个`FIFO20K`。
报告中的`feedthrough`为2,207（TD未提供该项器件总容量，因此不换算占用率），`pad reg`为0。

#### DSP占用明细

当前DSP是最紧张的资源，已用31个、只剩9个。层次资源报告中的DSP分配如下：

|模块|DSP数量|占总DSP|作用|
|---|---:|---:|---|
|`u_gamma`（`axis_gamma_rgb96`）|12|30.00%|RGB三通道Gamma查表插值乘法流水|
|`u_awb`（`awb`）|11|27.50%|白平衡像素增益乘法与通道校正|
|`u_color_shading`（`color_shading`）|8|20.00%|颜色阴影/镜头shading的双通道空间校正|
|其他模块|0|0.00%|当前报告中未占用DSP|
|**合计**|**31**|**77.50%**|—|

因此后续增加图像算法时，不能按“还有40个DSP”估算，而应按**只剩9个DSP**估算；
优先使用移位、加法、LUT和已有时序资源。当前颜色增强链路本身就占用了全部31个DSP：
Gamma12个、AWB11个、color shading8个。`u_awb`还使用10个ERAM保存延迟数据，
`u_gamma`和`u_color_shading`分别使用12个和8个DSP。

其他关键模块资源：`u_img_proc`使用293个逻辑LUT、168个寄存器和512个`dram lut`；
其中512个`dram lut`是Sobel的两行缓存。`u_isp_top`合计使用23个DSP（由AWB11个和
Gamma12个组成），同时使用22个ERAM。

> **AWB架构改造（2026-10-24）**：厂商`awb.v`原本用两个50级流水线除法器
> （`divider`IP）逐像素算增益，占`u_awb`的90%。改成串行除法+48拍后，`u_awb`
> 的DSP降到11个，整片Slice和时序均回到可接受范围。除法器改为帧首
> `I_tuser`触发，使用上一帧完整统计，并加帧间平滑，避免逐行增益漂移。

> **时钟方案（2026-10-24简化）**：HDMI用主PLL直接输出75.000/375.000MHz，
> 刷新率60.606Hz。PLL占用为3/6，75MHz采集卡已实测可稳定锁定。

> **注意**：TD将Sobel的行缓存实现为LUTRAM而非ERAM，因此当前有1,064个`dram lut`，
> 包含Sobel行缓存等视频缓存。后续如果继续增加算法，应优先控制LUTRAM和DSP增长。

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
- 资源：`u_osd_overlay` 110 logic lut / 52 f7mux / 26 f8mux；其中两个字体ROM各占
  26 f7mux和13 f8mux，整片Slice已计入上面的10,612（50.02%）。

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
