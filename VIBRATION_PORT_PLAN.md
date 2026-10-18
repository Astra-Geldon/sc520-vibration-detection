# 振动识别算法移植规划

> 目标工程：`D:\workplace\lab_ex1_mipi_hdmi_SC520 (2)\lab_ex1_mipi_hdmi_SC520\lab_ex1_mipi_hdmi`
> 算法参考模型：`D:\workplace\py\PythonProject`（`multi_object` / `projection` 等方法）
> 本文档 = 实施步骤 + 设计决策 + 对拍方法。编译由你负责。

---

## 0. 本次调研确认的硬事实

这些是从工程和 Python 源码里读出来的，不是推测。后面所有决策都建立在这上面。

| # | 事实 | 出处 |
|---|---|---|
| F1 | ISP 输出 `S_ISP_O_tdata` = **128 bit = 4 像素 × RGB888**（32bit 槽位取低 24 位），下游解成 **1 像素/时钟** | `isp128_to_rgb_stream.v:12` |
| F2 | **ISP→video_in 这一级没有有效反压**：`S_ISP_O_tready` 在顶层只被声明、只接到 isp_top 的**输入**口，**没有任何驱动源**；`video_in` 只消费 tvalid/tdata | `design_top_wrapper.v:91,710`；`isp_top.v:9,36` |
| F3 | 视频链跑在 `S_csi_rx_clk`（MIPI RX byte 域，sdc 里叫 `MIPI_RX_BYTE_CLK`）；sdc 时钟通道 **2.415 ns → 414 MHz → 828 Mbps/lane** | `camera_to_dsi_display.sdc:2,11` |
| F4 | PLL：clk0=100M(`S_100m_clk`)、clk1=24M(`S_24m_clk`)、clk4=HDMI pixel、clk5=HDMI serial；**clk2/clk3 未用** | `design_top_wrapper.v:531-543` |
| F5 | 资源口径：TD 报告用 **LUT6=21216 / Slice=21216 / DFF=42432**；数据手册的 38184 是 **LUT4**，两者不能互除 | `config.py:34-38`；`fpga_estimate.py:5-8` |
| F6 | ERAM = **108 块 × 20 Kbit = 2160 Kbit**；基线已用 **40 块**，**实际只剩 68 块 ≈ 170 KB** | `config.py:37`；`fpga_estimate.py:68` |
| F7 | 基线占用：lab_ex1 9865/12358/13313（WNS 1408ps）、lab_ex2 10422/12926/13465（1163ps）、lab_ex3 12669/14852/13380（**WNS 仅 103 ps**） | `config.py:30-32` |
| F8 | Python 工程里**完全没有串口代码**（grep `uart\|serial\|baud` 零匹配）；输出是 OSD/CSV/MP4/stdout | 全库检索 |
| F9 | 串口日志通路**已经打通**（`uart_tx.v` + `uart_log_debug.v` + H1 引脚 + 已进 design files） | 本工程 `user_source/hdl_source/` |
| F10 | `hdmi_mixer` 的 `DEBUG_MODE` 1~4 只是**整屏填色**，没有字库、没有画框逻辑 | `hdmi_mixer.v:103-160` |

---

## 1. 设计约束（已由你确认）

- **摄像头 1280×720 不降**——sensor / MIPI / ISP 配置一律不动。
- **HDMI 显示 1280×720 不降**——`video_in`/DDR/`video_out`/`hdmi_mixer`/`hdmi_tx` 一律不动。
- **算法内部可以降采样**，可以只用 **8×6** 分块。
- **实际振幅相对较大**，因此降采样带来的灵敏度损失可以接受。
- 分阶段推进，每阶段可独立编译验证。

---

## 2. 关键架构决策

### 2.1 抽头位置：ISP 输出，纯被动只读（**安全性有硬依据**）

```
MIPI RX → csi_unpacket → raw10_unpacket → uial2axis → isp_top ─┬─→ video_in → DDR → video_out → hdmi_mixer → hdmi_tx   （显示通路，不动）
                                                               │
                                                               └─→ vib_* 算法通路（新增，只读监听）
```

选在 `S_ISP_O_*`（`S_csi_rx_clk` 域）抽头，理由：

1. **F2 决定了抽头绝对安全**：这一级根本没有有效反压（`S_ISP_O_tready` 悬空未驱动），所以算法模块**不可能**通过 ready 信号拖慢显示。反过来也意味着算法**必须**是纯流式、每 valid 拍吃掉一个像素，不能有 stall。
2. 拿到的是已经去马赛克 + AWB 之后的 RGB888，省掉 RAW10 解包和去马赛克。
3. `S_ISP_O_tuser` = 帧首、`S_ISP_O_tlast` = 行尾，帧/行同步齐备。

> ⚠️ 不要插在 `video_in` 之后或 DDR 之后——那需要改 DDR 仲裁，风险高一个数量级。

**接口约定（新增模块一律遵守）**：

```verilog
module vib_xxx (
    input  wire        clk,          // = S_csi_rx_clk
    input  wire        rst_n,        // = S_rst_n
    input  wire        in_valid,     // = S_ISP_O_tvalid
    input  wire [127:0] in_data,     // = S_ISP_O_tdata  (4×RGB888)
    input  wire        in_frame_start,// = S_ISP_O_tuser
    input  wire        in_line_end,  // = S_ISP_O_tlast
    ...
);
```
**没有 ready / 没有 tready 输出**——这是刻意的，不要加。

### 2.2 降采样倍率：受 ERAM 硬约束（**这是最关键的一个选择**）

帧差 `It = I(t) − I(t−1)` 需要存**上一帧灰度**。先看 ERAM 账（F6：只剩 68 块 × 20 Kbit = 170 KB）：

| 方案 | 算法分辨率 | 上一帧灰度 | 需要 ERAM20K | 装得下？ |
|---|---|---|---|---|
| DEC=2 | 640×360 | 230,400 B = 1,843,200 bit | **90 块** | ❌ 超过 68 |
| DEC=2 限高 ROI | 640×272 | 174,080 B = 1,392,640 bit | 68 块 | ⚠️ 刚好占满，不留余量 |
| **DEC=4** | **320×180** | **57,600 B = 460,800 bit** | **23 块** | ✅ 余 45 块 |
| DEC=4 | 320×180（双缓冲） | — | 46 块 | ✅ 余 22 块 |

**关键技巧：上一帧缓存不需要双缓冲。** 因为读和写都是同一光栅顺序，可以**就地读旧值、写新值**：

```verilog
// 同一个地址：先读上一帧的像素，再写入当前帧像素
prev_gray_rd = mem[addr];      // = I(t-1)
mem[addr]     = gray_now;      // 覆盖为 I(t)
It            = gray_now - prev_gray_rd;
```
一次遍历同时完成"取上一帧"和"存当前帧"，**只需 1 份缓存**，ERAM 直接减半。

**推荐：DEC=4 → 320×180**（第一版），理由：

- ERAM 只吃 23/68 块，给后面的块结果 RAM、历史 RAM、OSD 字库留足余量；
- 320×180 是 1280×720 的整除关系，4×4 盒式平均实现极省（见 2.2 的实现提示）；
- 48 个块的求解量、行缓存、DFF 全部只有 640×360 方案的 1/4；
- 你说振幅偏大 → 位移降到 1/4 仍应高于 0.75 px/帧 的门限。

**升级路径**：如果实测发现 320×180 下位移太小（见第 8 节决策表），再上 2×2 的 **640×272 限高 ROI**（68 块，占满 ERAM），或把上一帧搬进 DDR（需要在 `mc_to_user_interface` 加第三个主口，风险显著上升，放到最后）。

> 4×4 盒式平均的省资源实现：**横向 4 像素滑动累加**（1 个 10bit 加法器 + 移位）+ **纵向 4 行累加行**（320 × 12bit = 3840 bit，放分布式 RAM 或 1 块 ERAM），每 4 行整除一次输出。**不需要 4 条行缓存**。

### 2.3 分块：8×6 = 48 块

|  | DEC=4 / 320×180 | DEC=2 / 640×360 | 参考配置 1280×720 |
|---|---|---|---|
| 块尺寸 | 40×30 = 1200 px | **80×60 = 4800 px** | **80×60 = 4800 px** |
| 块数 | 48 | 48 | 192（16×12） |

**注意一个很漂亮的巧合**：`DEC=2 / 640×360 / 8×6` 的块尺寸是 80×60，**和默认参考配置 `1280×720 / 16×12` 的块尺寸完全一样**（都是 4800 px）。也就是说那一档下，`min_grad_sum`、`min_energy_abs`、`track_min_pixels`、`min_box_side` 这些**按块面积缩放的常数会自动落在和参考配置相同的值上**，只有块数从 192 降到 48。

而 `DEC=4 / 320×180 / 8×6` 的块是 40×30 = 1200 px，`area_ratio = 1200/2700 = 0.4444`，常数需要按此缩放（第 4 节有换算表）。

### 2.4 采样率：固定 30 fps（每 2 帧使能一次）

- 已提交的三份 golden CSV（`multi_single_result.csv` / `multi_two_result.csv` / `realistic_vibration_6hz_2px_result.csv`）**全部是 30 fps 生成的**（第一行框 `0,0,960,540`；`capture_camera_test.py:38` 也是 30）。
- `main.py:46` 的 `--vib-fps` 默认 `0.0` 是个 bug——它会算出 `vib_fs=60`，与 `config.py:339` 的 `fs=60.0` 一致但与所有 golden data 不一致。**规划里统一按 30 fps**。
- 你的 `VisionPipeline.py:36-37` 已经写明：*"振动通道抽帧到 30fps（vib_step=2）能把灵敏度拿回一半，计算量同时也减半。**FPGA 上就是每 2 帧使能一次。**"*

实现：在 `S_ISP_O_tuser` 处维护 1bit 帧奇偶，只在偶数帧使能算法通路。**注意**：不使能的那些帧里，`prev_gray` 缓存**不能更新**，否则 `It` 会变成单帧差而非双帧差。所以每隔 2 帧才做"就地读-改-写"。

### 2.5 算法路线：**先投影相关，后网格 LK**

这是和之前那份 AI 规划最大的分歧点。考虑到你说**振幅偏大**，最短路径不是直接上 192 块 LK + 聚类 + 跟踪，而是：

```
M2 单 ROI 投影 + 1D 相关  →  dx, dy（带符号、亚像素）
M3 Goertzel(dx, dy)       →  频率 + snr        ← 到这里就是一个可用的「振动识别器」
M4~M7 网格 LK + 聚类 + 跟踪 →  空间定位 + 多目标
```

理由：`vision_projection.py` + `vision_correlation.py` 这条路线的硬件代价大约是网格 LK 路线的 **1/5**，而且它没有"随机访问梯度平面"的问题，完全流式。Python 里两种方法都有，golden data 都能生成，对拍一样严格。

### 2.6 时钟域

- 算法全部跑在 **`S_csi_rx_clk`** 域（跟视频流同域，不用跨域）。
- 只有 UART 输出要跨到 `I_sys_clk`（50 MHz）：结果寄存器 + **打两拍同步**。
- **不要在算法里用 `I_sys_clk`**（那是 50 MHz 板级时钟，跟视频流无关）。

---

## 3. 分阶段实施步骤

> 每个 Milestone 都是"可独立编译 + 可独立验证"的。**不要跳阶段。**
> 新增 RTL 统一放 `user_source/hdl_source/vibration/`，并在 `camera_to_dsi_display.al` 的 `<Verilog>` 段落里注册（参考 `uart_tx.v` / `uart_log_debug.v` 的写法，`CompileOrder` 从 58 往后顺延）。

---

### M0 —— 串口日志通路 ✅ **已完成**

- **成果**：`uart_tx.v` + `uart_log_debug.v`，115200 8N1，引脚 H1，已注册进 design files。
- **作用**：后面所有阶段的调试眼睛。**先确认你编译后能看到 12 行状态打印再往下走。**

---

### M1 —— 视频抽头 + 灰度 + 降采样（不做任何算法）

**目标**：证明"能从 ISP 拿到正确的像素流并降采样到 320×180"。

**新增**：`vib/vib_video_tap.v`

- 128bit → 4×RGB888 反串化（照 `isp128_to_rgb_stream.v:12` 的槽位：`[23:0] [55:32] [87:64] [119:96]`，**4 拍出 4 像素**）；
- 灰度 `gray = (R + 2*G + B) >> 2`（照 `vision_basic.py:10-14`，纯移位加法）；
- 4×4 盒式平均 → 320×180（实现见 2.2 提示）；
- 输出：`px_valid`、`px_data[7:0]`、`line_end`、`frame_start`；
- 同时输出统计：`frame_cnt`、`px_cnt`（当前帧已输出像素数）。

**验证**：
1. UART 打印 `frame_cnt` 每秒 +30（30 fps 使能）；
2. `px_cnt` 每帧恒等于 **320×180 = 57600 = 0x0000E100**。**这条过了，说明像素流对齐正确**——这是最容易错也最难查的一步。

**资源预算**：LUT6 ≤ 800，DFF ≤ 800，ERAM 1 块，DSP 0。

---

### M2 —— 单 ROI 投影 + 1D 相关 → dx, dy

**目标**：得到带符号的亚像素位移 `dx, dy`（每帧一对）。

**新增**：`vib/vib_projection.v`、`vib/vib_corr1d.v`、`vib/vib_frame_store.v`

- `vib_frame_store.v`：320×180×8bit 上一帧缓存，**就地读-改-写**（2.2 节），放 ERAM（23 块）；只在使能帧更新；
- `vib_projection.v`：对 ROI 求**行投影**和**列投影**（`Σrow`、`Σcol`），各 320/180 个累加器；同时保留参考投影（上电后前 N 帧平均，或缓慢更新，对应 `ref_alpha=0.001`）；
- `vib_corr1d.v`：对投影做 1D 归一化相关，搜索半径取 ±16（`window_search_radius=32` 在降采样后按比例缩小），用**抛物线插值**取亚像素峰值（照 `vision_correlation.py:parabolic_subpixel`）。

**验证**：
- 把摄像头做**已知方向的匀速平移**，UART 打印 `DX/DY`，符号必须和运动方向一致、量级单调；
- 静止时 `DX/DY` 的噪声底应 < 0.5 px/帧；
- **与 Python 对拍**：用 `method="projection"` 在同样 320×180@30 下跑出 `golden_proj.csv`，逐帧比 `dx/dy`，误差应 < 0.1 px。

**资源预算**：LUT6 ≤ 1,500，DFF ≤ 2,000，ERAM 25 块，DSP 1~2。

---

### M3 —— Goertzel → 频率 + snr　🎯 **这一阶段结束就是一个可用的振动识别器**

**目标**：输出振动频率。

**新增**：`vib/vib_goertzel.v`

- 输入：M2 的 `dx, dy` 历史（60 样本 = 30 fps × 2 s，`freq_window_sec=2.0`）；
- **17 个频点**：2.0 ~ 10.0 Hz 步进 0.5（`config.py:341-344`，**不要减到 6 个**——17 个频点的 MAC 量小到可以忽略，而减少频点会让 golden data 对不上）；
- 固定频点 → `cos/sin` 预生成 **LUT**（不要现场算，Python 里的 `np.cos/np.sin` 是浮点参考而已）；
- **用功率 `i²+q²` 比大小，省掉 sqrt**；**`atan2` 直接删掉**（Python 里算了但没有任何调用者用它）；
- 噪声底 = 17 个功率值的**中位数**（小排序网，几百 LUT6）；
- `snr = best / noise_floor`；门限 `snr >= 6.0`（`multi_snr_threshold`）；
- 低频拒绝：额外算 0.5 / 1.0 / 1.5 Hz 三点，主频必须 > 低频 3 倍（`multi_reject_ratio=3.0`）；
- 1 阶 IIR 高通（2 Hz）先滤掉慢漂移，`α = exp(-2π·2/30) = 0.659`；
- 每 5 帧更新一次（`update_interval=5`）；
- `freq_confirm=2`：连续 2 次指向同一频点才认。

**验证**：
- 用 `zhendang.py`（8 Hz / 8 px 方块）或 `generate_realistic_vibration_video.py`（6 Hz）在屏幕全屏播放，摄像头对着拍 → UART 应打印出对应频率；
- **与 Python 对拍**：把同一段 `dx/dy` 历史喂给 `vision_goertzel.goertzel_iq`，主频必须一致，幅度比值应在 ±10% 内。

**资源预算**：LUT6 ≤ 1,200，DFF ≤ 1,500，ERAM 2 块，DSP 1。

**UART 输出格式建议**（M3 起）：

```
VIB 1
FREQ 00000006   (Q0.8 或原始 0.5Hz 步进的索引)
SNR  00000007
RMS  0000002A
DX   0000FFCE   (有符号 16bit, Q8.8)
DY   00000012
```

---

### M4 —— 网格 LK → 48 块的 u/v/energy

**目标**：把"哪一块在动"求出来（空间定位）。

**新增**：`vib/vib_grad3x3.v`、`vib/vib_grid_lk.v`、`vib/vib_solve2x2.v`

- `vib_grad3x3.v`：3×3 高斯（整数、移位）+ 中心差分 ×0.5 → `Ix, Iy`（照 `vision_multi_object.py:432-442` 的 `_gradients`）；2 条 320×8 行缓存；
- `vib_grid_lk.v`：每块累加 **6 个量**：`axx=ΣIx², ayy=ΣIy², axy=ΣIxIy, bx=ΣIxIt, by=ΣIyIt, energy=Σ|It|`；
  - **按行复用**（关键！照 `fpga_estimate.py:47-49`）：只保留"一行块"的 **8 × 6 × 32bit = 1536 DFF** 累加器，行末结算写入 48×3×24bit 的块结果 RAM；
  - ❌ **绝对不要**给 48 个块各配一套累加器（那会变成 48×6×32 = 9216 DFF，还会被综合工具展开成大量 LUT）；
- `vib_solve2x2.v`：帧末时分复用求解
  ```
  det = axx*ayy - axy*axy
  有效 = (grad >= min_grad_sum) && (det >= 0.02 * trace²)      // trace = axx+ayy
  u   = (-bx*ayy + axy*by) / det
  v   = (-axx*by + axy*bx) / det
  ```
  - **`det` 的条件数门限是必须的**（`multi_min_cond_ratio=0.02`，`vision_multi_object.py:487`），否则平坦/直线边缘块会解出乱飞的 u/v；
  - 除法：**1 个共享的除法器/倒数表**，每帧 48 次（30 fps → 1440 次/秒），时间复用绰绰有余。

**验证**：**与 Python 对拍是最重要的一环**：
- 生成 `golden_blocks.csv`（列：`frame,bx,by,u,v,energy`，每帧 48 行）；
- RTL 用同一帧序列（testbench `$readmemh`）跑，逐块比 `u/v`，目标误差 < 0.1 px；
- 板上：对着摄像头缓慢平移，`u/v` 符号应与运动方向一致。

**资源预算**：LUT6 ≤ 3,000，DFF ≤ 3,500，ERAM 4 块，DSP 4~8。

---

### M5 —— 全局运动补偿 + 块筛选

**新增**：`vib/vib_global_motion.v`

- **用 2D 量化直方图众数**，不要用中位数——你自己在 `config.py:212-214` 已经算过：*"硬件里中位数要排序网（192 个值约 9000 LUT6），直方图只要 (2n+1)² 个计数器（n=16 → 1089 个 ≈ 1 ERAM）+ 扫一遍"*；
- **注意缩放**：`gm_bin=0.25`、`gm_n=16` 的半量程是 ±4 px/帧，那是为 1280×720 定的。DEC=4 后每帧位移只有 1/4，半量程应改成 ±1 px → `bin=0.0625`；
- `active = valid && energy >= min_energy_abs && disp >= min_disp`（`disp = |u,v|`，这里可以用 `u²+v² >= min_disp²` 避免 sqrt）；
- 最外圈块强制不激活（`vision_multi_object.py:719-723`）；
- 有能量块占比 ≥ 45% 且整体位移 ≥ 0.3 px 时才判定为"相机在晃"，从块位移里减掉 `g_u/g_v`。

**验证**：整体平移摄像头时 `g_u/g_v` 跟上，而 `active` 块数不暴涨（不误报）。

**资源预算**：LUT6 ≤ 1,200，DFF ≤ 800，ERAM 2 块。

---

### M6 —— 聚类 + 简化跟踪

**新增**：`vib/vib_cluster.v`、`vib/vib_track.v`

- 聚类：8 连通 + `|du|,|dv| <= 1.5` 一致性。**48 个块比 192 个块容易得多**——可以用固定 48 状态的一遍扫描 + 并查集合并，**不需要栈**，迭代次数有上界；
- 跟踪：**最多 2~4 个目标**（不要一上来做 8 个）；用**固定大小搜索窗**（不做 Python 里数据相关的窗口跟随/收缩）；
- 匹配：最近邻 + 距离门限；
- 每目标维护 u/v 历史 60 帧（30 fps × 2 s）。

> ⚠️ **必须手动重标的常数**（Python 的 `fit_resolution` 里 `scale = max(1.0, w/1280)` 被 clamp 在 ≥1.0，所以低分辨率下这些**不会自动缩小**，直接用会严重跑偏）：
>
> | 常数 | 1280×720 值 | DEC=4 / 320×180 应用值 | DEC=2 / 640×360 应用值 |
> |---|---|---|---|
> | `multi_match_dist` | 90.0 | **≈ 22** | **≈ 45** |
> | `multi_cluster_margin` | 30 | **≈ 8** | **≈ 15** |
> | `multi_track_margin` | 24 | **≈ 6** | **≈ 12** |
> | `multi_gm_bin` | 0.25 | **≈ 0.0625** | **≈ 0.125** |

**验证**：目标不跳 ID、不闪；`next_id` 增长应远小于帧数。

---

### M7 —— 每目标 Goertzel

复用 M3 的 `vib_goertzel.v`，加一个目标维度的时分复用（目标数 × 17 频点，占空比仍然极低）。

**验证**：`multi_two_result.csv` 那种双目标场景，两个目标各自的频率都要对。

---

### M8 —— HDMI 画框（可选，最后做）

- **F10**：`hdmi_mixer` 现在只有整屏填色，**没有画框逻辑、没有字库**，这是新增逻辑；
- 画框：只要比较器（`x0<=x<=x1 && y0<=y<=y1`）→ 便宜；
- **坐标要 ×4（DEC=4）或 ×2（DEC=2）回到 1280×720 显示坐标系**，这一步很容易忘；
- 写字：需要字库 ROM（放 ERAM），比画框贵；
- **必须在 lab_ex2 基线上先把时序收敛，再考虑加 OSD**——参考 F7，lab_ex3 加了 OSD 后 Slice 已 70%、WNS 只剩 103 ps。

---

## 4. 常数换算表（DEC=4 / 320×180 / 8×6 下）

`area_ratio = (40×30) / 2700 = 0.4444`（`reference_cell_area = 2700 = 60×45`）

| 常数 | 参考值 | 320×180/8×6 应用值 | 说明 |
|---|---|---|---|
| `min_grad_sum` | 1500 | **667** | `1500 × area_ratio` |
| `min_energy_abs` | 30 | **13.3** | `30 × area_ratio` |
| `min_disp` | 0.75 px/帧 | **0.75（不变）** | `config.py:382` 明写"与分辨率无关" |
| `track_min_pixels` | 25 | **17** | `25 × sqrt(area_ratio)` |
| `min_box_side` | 8 | **6** | `8 × sqrt(area_ratio)` |
| `min_cond_ratio` | 0.02 | **0.02（不变）** | 结构张量条件数，与尺度无关 |
| `fs` | 30 | **30** | 每 2 帧使能 |
| `freq_window` | 60 | **60** | `round(2.0 × 30)` |
| `min_hist` | 22 | **22** | `round(1.5 × 30 / 2)` |
| 高通系数 α | 0.659 | **0.659** | `exp(-2π·2.0/30)` |
| 频点 | 17 个 2.0~10.0 | **不变** | |
| 低频拒绝点 | 0.5/1.0/1.5 | **不变** | |
| `update_interval` | 5 帧 | **5** | |
| `freq_confirm` | 2 | **2** | |
| `multi_snr_threshold` | 6.0 | **6.0（不变）** | |
| `multi_reject_ratio` | 3.0 | **3.0（不变）** | |

> 灰度与盒式平均**可交换**（`gray = (R+2G+B)>>2` 是线性运算）——Python 的 `cv2.resize(INTER_AREA)` 是"先平均后灰度"，FPGA 是"先灰度后平均"，数学上等价，只差 ≤1 LSB 的舍入。**不要为这点差异去查 bug。**

---

## 5. Golden data 生成与对拍流程（**这一节是成败关键**）

**必须先做这一步，再写 RTL。** 否则后面是在 snr 余量很小的实测数据上调参，无法定位问题。

### 5.1 生成脚本 `vib_golden_fpga.py`（在 Python 工程里）

1. 读入 1280×720 测试片段（`generate_realistic_vibration_video.py --size 1280x720 --fps 30 --freq 6 --amplitude 8` 生成，或真实拍摄）；
2. `cv2.resize(INTER_AREA, 1/4)` → **320×180**（和 FPGA 的 4×4 盒式平均对齐）；
3. 构造跟踪器，**显式**设置（不要依赖自动缩放）：
   ```python
   MultiObjectMotionTracker(
       grid_x=8, grid_y=6,          # 显式 8×6
       fs=30.0,                     # 显式 30 fps
       freq_window_sec=2.0,
       history_len=60,              # 30fps × 2s
       match_dist=22,               # ← 手动按 320/1280 缩放
       cluster_margin=8, track_margin=6,
       gm_bin=0.0625,
       ...  # 其余按第 4 节表格
   )
   ```
4. **每帧**（不做 vib_step 抽帧，因为输入已经是 30 fps）跑一次，输出三份 CSV：

| 文件 | 列 | 对拍对象 |
|---|---|---|
| `golden_proj.csv` | `frame,dx,dy` | M2 投影相关 |
| `golden_blocks.csv` | `frame,bx,by,u,v,energy` | M4 网格 LK |
| `golden_tracks.csv` | `frame,obj_id,u,v,freq,snr,rms,box_x,box_y,box_w,box_h` | M6/M7 跟踪 + Goertzel |

5. 同时把每帧 320×180 灰度导出为 `frames/f%04d.mem`（16 进制，每行 1 字节），给 testbench 用 `$readmemh` 喂进 RTL。

### 5.2 对拍三层次

1. **Sim 层（最严格）**：testbench 用 `$readmemh` 喂帧 → RTL 输出与 `golden_blocks.csv` 逐帧逐块比 `u/v`，容差 0.1 px。
2. **板上静态层**：固定靶标做已知位移（如 `zhendang.py` 的方块），看 `u/v` 方向与量级。
3. **板上动态层**：全屏播放已知频率的测试视频，摄像头对着拍，看频率输出。

---

## 6. 资源预算与红线

| 资源 | 基线 lab_ex2 | 算法预计增量 | 合计 | 总量 | 占用 |
|---|---|---|---|---|---|
| LUT6 | 10,422 | +6,000 ~ +8,700 | 16,400 ~ 19,100 | 21,216 | 77% ~ **90%** |
| Slice | 12,926 | — | ~19,000 ~ 21,000 | 21,216 | 90% ~ **99%** |
| DFF | 13,465 | +4,000 | ~17,500 | 42,432 | 41% |
| ERAM20K | 40 | +37（帧存 23 + 行缓存 1 + 块 RAM 1 + 直方图 1 + 历史 2 + 字库） | ~77 | 108 | 71% |
| DSP | 8 | +6 | 14 | 40 | 35% |

### 三条红线

1. **必须叠在 lab_ex2 基线上做**（不带 OSD）。lab_ex3 加了 OSD 后 Slice 已 70%、**WNS 只有 103 ps**，再加算法会直接崩。
2. **每加一个 Milestone 都要看 WNS**。一旦 WNS < 300 ps 就停下来做流水线切割，不要继续加功能。
3. **Slice 超过 85% 就降低并行度**（例如把 4×4 盒式平均的横向累加改成串行时分复用），或者回退到 M2+M3 的单 ROI 路线收工。

> 上面的 Slice 估算是**估算**，不是综合结果。第一次综合（M1 之后）就应该拿真实数字重算这张表。

---

## 7. 风险清单与工程纪律

| # | 风险 | 应对 |
|---|---|---|
| R1 | **抽头拖慢显示** | F2 已保证不可能（无背压）。但算法**必须每 valid 拍吃掉像素**，不能 stall；一旦做不完只能丢像素（4×4 降采样有 16× 余量，够） |
| R2 | **帧对齐错位**（`It` 用了错行的上一帧） | M1 的 `px_cnt == 57600` 断言是唯一的早期防线；再加一个"行号一致性"计数器 |
| R3 | **非使能帧误更新 `prev_gray`** | 2.4 节：只有使能帧才做就地读-改-写 |
| R4 | **病态块解出乱飞的 u/v** | `det >= 0.02·trace²` 与 `grad >= min_grad_sum` 双重门限，缺一不可 |
| R5 | **低分辨率常数没重标** | 第 4 节表格 + 第 6 节 M6 警告框。这是最容易犯、最难查的错 |
| R6 | **定点位宽不足** | `Ix/Iy` 建议 Q4.4 以上（有符号 9~10 bit）；累加器 32bit；`u/v` 输出 Q8.8。每个 Milestone 都要和浮点 golden 回归 |
| R7 | **时序收敛** | 第 6 节红线 1/2/3 |
| R8 | **ERAM 超支** | 先算账再写代码。DEC=4 的 23 块是算过的；DEC=2 的 90 块**装不下**，别试 |
| R9 | **块累加器被展开** | 严格按行复用（8 组），不要写成 48 组数组 |

### 纪律

- 新增 RTL 全部放 `user_source/hdl_source/vibration/`，并在 `.al` 的 `<Verilog>` 段注册；
- 新增模块**不产生 ready/背压**；
- 每阶段结束都在 UART 上留一段可读打印（用 M0 已打通的通道）；
- 每阶段都先跑 Python golden data，再动手写 RTL。

---

## 8. 待你确认 / 待测的 3 件事

### ① 先测真实振幅 —— 它决定 DEC 倍率

**这是唯一还没定的关键参数。** 建议在做 M1 之前，用 Python 在真实场景跑一次 1280×720/16×12，读出 `u/v` 的 **p99 绝对值（px/帧）**：

| 实测 p99 位移 | 建议 DEC | 320×180 下位移 | 相对 0.75 px 门限余量 |
|---|---|---|---|
| ≥ 12 px/帧 | **4**（320×180） | ≥ 3 px | 4× ✅ 舒服 |
| 6 ~ 12 px/帧 | **4**，但盯着看 | 1.5 ~ 3 px | 2 ~ 4× ✅ 可以 |
| 3 ~ 6 px/帧 | **2**（640×272 ROI） | 0.75 ~ 1.5 px | 1 ~ 2× ⚠️ 勉强 |
| < 3 px/帧 | 必须 2× 或全分辨率 | < 0.75 px | ❌ 需要动 DDR |

> 你说"振幅相对较大"，我预计落在前两档，那样 **DEC=4 / 320×180 就够**，整个方案可以完全不碰 DDR——这是风险最低的路线。

### ② `S_csi_rx_clk` 的实际频率

sdc 写的是 2.415 ns → 414 MHz → 828 Mbps/lane（与 RTL 注释的"828 Mbps/Lane"一致），但 `config.py:20` 写的是 **480 Mbps/lane**，两者矛盾。这决定每像素有几个时钟周期可用：

- 若 ≈ 103.5 MHz → **1.39 时钟/像素**，1 px/clock 的流水线够用（利用率 72%）；
- 若 ≈ 60 MHz（480 Mbps/lane 那档）→ **0.81 时钟/像素**，1 px/clock **不够**，必须改成 4 px/拍宽的流水线。

**建议：M1 综合后看一次时序报告里 `S_csi_rx_clk` 的实际约束值。** 在这之前不要定数据通路宽度。

### ③ 是否接受"先只做单 ROI（M2+M3）"作为第一版交付

如果接受，那么第一版**完全不碰网格、聚类、跟踪、OSD、DDR**，硬件代价大约只有完整方案的 1/5，而且已经能回答"有没有在振、振多少 Hz"。之后 M4~M7 再往上加空间定位和多目标。

---

## 附：和之前那份 AI 规划的三点主要分歧

1. **它建议振动通道降到 640×360 以省资源**；但 `config.py:382` 与 `VisionPipeline.py:30-37` 明写噪声底（~0.5 px/帧）**与分辨率无关**，降采样会让位移减半而门限不变 → 灵敏度减半。**正确做法是保持空间分辨率、只在时间上每 2 帧使能一次**（你 docstring 里给 FPGA 的原话）。你说振幅偏大所以可以接受降采样——这我同意，但请把它当成**你主动选择的取舍**，而不是"降采样免费"。
2. **它的资源账把 LUT4(38184) 和 LUT6(21216) 混用了**，并假设 2160 Kbit ERAM 全空。实际基线已用 40/108 块 ERAM、60% Slice，真正的瓶颈是 **LUT6/Slice 和时序收敛**（lab_ex3 WNS 仅 103 ps），不是 DSP。
3. **它说"从现有代码看…通过 UART 输出频率"**——Python 工程里**没有串口代码**。UART 协议是新增的设计决定，因此必须额外定义"FPGA 输出 ↔ CSV 列"的映射，否则无法逐帧对拍。

---

*文档版本：v1 · 基于实际源码勘察（`config.py` / `vision_multi_object.py` / `isp_top.v` / `isp128_to_rgb_stream.v` / `design_top_wrapper.v` / `camera_to_dsi_display.sdc` / `fpga_estimate.py`）*
