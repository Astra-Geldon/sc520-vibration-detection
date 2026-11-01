# 当前算法与实际数据链路

适用当前 Final_Project 整合版：图像采集、基础处理、增强与 HDMI 沿用 `20261029project`，微振动链路沿用 `backup-vibration-20261030`。本说明以顶层实例和有效代码为准；旧模块默认参数或注释不代表当前配置。发布目标为 Gitee `main`，当前 Bit SHA256 为 `A2CA15E1BC1A57199D6171230E50BCB8DF6F2C4F75635CF387B6BB1AB753B4E1`。

## 活动链路与算法位置

```text
传感器曝光/增益（SW5，从采集源控制）
SC520CS RAW10 → MIPI CSI → BGGR双线性去马赛克（SW4）
→ AWB（SW1）→ Gamma（SW2）→ RGB打包/DDR帧缓存
→ Color Shading（SW3）→ img_proc模式 → 固定N1（SW2）
→ 状态/模式名/安路Logo OSD → HDMI

ISP被动抽头 → 640×360微振动链路 → 结果标记叠加至HDMI
                               └→ UART诊断
```

源代码入口：[顶层](user_source/hdl_source/design_top_wrapper.v)、[ISP](user_source/hdl_source/isp/isp_top.v)。图像路径保持原流式处理和 DDR 视频缓存，无交替曝光；振动路径另用外部 DDR 保存上一帧。六项图像展示能力为 DEM/AWB/GAM/CSC/N1/EXP，其中 Gamma 和 N1 共用 SW2。KEY3 独立控制微振动算法，默认 OFF。

## 1. 去马赛克与RAW展示（SW4）

[去马赛克](user_source/hdl_source/isp/demosaic_4x_2_0/demosaic.v) 使用BGGR排列、3×3邻域的双线性插值，从RAW重建RGB。关闭后保留原行缓冲和同步拍数，将中心四个Bayer样本分别复制成灰度RGB。

RAW展示不是从正常RGB计算灰度。AWB、CSC、N1在RAW状态自动旁路，Gamma仍随SW2。KEY2灰度模式则对已经过ISP的RGB计算灰度。

## 2. 亮度加权AWB与帧间平滑（SW1）

活动文件为 [awb.v](user_source/hdl_source/awb.v)。从四像素并行组的第0个像素取样，权重为 `(R+2G+B)>>4`。过曝样本（R+G+B≥720）和启发式肤色样本（R>G+15且max−min>46）不参与统计。

帧首读取上一帧完整统计，串行计算G/R、G/B，每路48拍；R/B增益限制0.5～2.0，G不变。首个有效结果直接使用，后续按 `old+(new-old)/64` 平滑；有效样本少于4096时保留旧增益，没有回退全帧统计。数据延迟RAM为100拍，保留与计算结果的对齐。

SW1关闭选择单位增益，仍保留RAM和同步流水。算法可减小帧内漂色和快速跳变，但它不是语义肤色识别，也不保证单色/极端彩光场景白平衡正确。

## 3. Gamma：16段锚点与线性插值（SW2）

实现为 [isp_top.v](user_source/hdl_source/isp/isp_top.v) 中的 `axis_gamma_rgb96/gamma07`。以输入高4位选择16组 `base/delta`，低4位段内插值：

```text
y = base + ((delta × (x & 15) + 8) >> 4)
x=255 时特殊输出255
```

当前示例映射：16→37、128→157、240→244、255→255。函数名虽为gamma07，当前修改后的实际曲线不能描述为精确0.7次幂，也不是256项直接输出LUT。

关闭时同一寄存拍选择原值，保留像素/同步延迟。它与N1不同：Gamma在DDR前作用于各RGB通道，N1在显示后端共用一个RGB增益。

## 4. Color Shading：一维水平R/B颜色校正（SW3）

实现：[color_shading.v](user_source/hdl_source/color_shading.v)、[color_shading_lut.v](user_source/hdl_source/color_shading_lut.v)。当前表为 **10列×1行**，每128像素一列，列间分32级、每4像素更新插值；不按y坐标分区，不是旧10×6二维表。

R/B使用Q8增益，G直通。顶层强度固定k=0.75，SW3在校正输出和输入像素间选择；没有将动态强度送入新乘法器。R/B最终按8位饱和，已经削顶的信息不会靠后级处理恢复。

表来自既有多场景经验校准，是静态空间补偿；AWB负责全局色温，二者不能相互替代。换镜头、模组或照明后可能需重新评估，不能称为自动标定或通用降噪。

## 5. N1：固定中暗部增益曲线（SW2）

实现：[fixed_n1_lift.v](user_source/hdl_source/fixed_n1_lift.v)。对 `img_proc` 结果取 `peak=max(R,G,B)`，查 **256项固定Q8增益表**；三个通道共用同一增益，并计算 `(pixel×gain+128)>>8` 后饱和。

| peak | Q8增益 | 倍率 |
|---|---:|---:|
| 16 | 448 | 1.75 |
| 64 | 400 | 1.5625 |
| 128 | 320 | 1.25 |
| 191 | 257 | 约1.004 |
| ≥192 | 256 | 1.0，精确保持 |

乘法用显式移位/加法树实现，不额外占用 DSP。当前整合版总 DSP 为 40，原图像处理仍保留独立的 31 个。N1仅在彩色模式、SW2开启、SW4为正常彩色时参与；不改变视频同步延迟。

它是逐像素亮度曲线，不是H1分区掩模、局部平均、自适应HDR或色度降噪。保护的是“进入N1时peak≥192不再被N1增亮”，不能保证传感器或前级永远不饱和，也不能消除低曝光提亮后的噪声。

## 6. 传感器端固定曝光保护（SW5）

控制入口：[ae_set.v](user_source/hdl_source/uiisp_beta/ae_set.v)。真实写入由 [uicfgcs520.v](user_source/hdl_source/uics520_cfg/uicfgcs520.v)、[uics520regAE.v](user_source/hdl_source/uics520_cfg/uics520regAE.v) 和 [SC520GainTbl.v](user_source/hdl_source/uics520_cfg/SC520GainTbl.v) 完成。

| SW5 | 曝光E | 增益控制码 | 标称总增益 | 3e00/01/02 | 3e09/06/07 |
|---|---:|---:|---|---|---|
| ON保护 | 900 | 128 | 8×模拟×1.5×数字=12× | 00 38 40 | 0B 00 C0 |
| OFF旧参考 | 1991 | 160 | 16×模拟×1.5×数字=24× | 00 7C 70 | 0F 00 C0 |

E是控制参数，不是毫秒；寄存器表列的是请求写入值，不是本次上板读回结果。八次写入包含3812=00组保持与3812=30释放。

保持原上电等待、真实帧等待、完整组写和NACK有界重试。首次等待真实FS后提交组写，成功后再等两帧；失败整组最多尝试三次。控制器done必须先低再高，不能把初始化时done高误认成应用成功。忙时合并到最新拨码目标。

这是两组固定参数切换，不是基于场景亮度连续迭代的AE/AGC。全开使用E900/G12，配合N1恢复中暗部；强光仍可能超出动态范围。

## 模式与OSD

[img_proc.v](user_source/hdl_source/img_proc.v) 的活动配置是：自适应二值化开启，多数滤波/高斯预滤波/阈值锁定关闭。灰度 `(R+2G+B)>>2`；灰度与Sobel取DDR读出数据，不经过shading或N1。二值化固定取shading后的输入，阈值为上一帧均值并作1/4帧间平滑。Sobel为3×3 `|Gx|+|Gy|`，保留原邻域边界/延迟。

[osd_overlay.v](user_source/hdl_source/osd_overlay.v) 显示原四模式名称、安路Logo和六项状态。状态来自各域已提交控制，EXP还需等待控制器完成；这不是传感器寄存器读回或DDR逐像素帧标签。关闭算法的硬件仍在FPGA中，不会实时释放资源。

## 已退出当前链路的历史实验

H1掩模、C0～C3补偿、D降噪、P肩部/W颜色保护、E/G/N候选菜单、交替曝光和旧大诊断逻辑均不属于当前活动实现。历史记录见 [文档索引](DOCUMENTATION_INDEX.md)，实际资源见 [RESOURCE_USAGE](RESOURCE_USAGE.md)。

## 微振动识别与结果输出

活动链路复用备份工程的被动抽头、帧差/预处理、分块 LK、Goertzel 频率分析、峰值确认及包围框标记。实际 RTL 为 **640×360、8×6 分块、64 帧窗口、27 个频点，2～15 Hz、间隔 0.5 Hz**。沿用实际 RTL，未改为规划文档中的 320×180 方案。

KEY3 默认 OFF；关闭时算法链保持复位，振动 DDR 请求被门控，HDMI 振动标记旁路。开启后运行识别并将结果标记叠加到 HDMI，保留 UART 诊断输出。抽头不向图像路径施加反压，DDR 调度以 HDMI 连续输出为优先。

为避免 DSP 不足时合并主图像乘法器，`vib_bbox_grid` 仅增加 `(* dsp_style = "no" *)`，将本模块 6 个 DSP 运算映射到 LUT/Slice；未改算法公式、位宽或流水节拍。最终全工程 DSP 为 40，图像 31 个 DSP 保持独立，原 5 条物理浮空网警告已消失。

当前 Bit 于 2026-11-01 15:56:33（北京时间）烧录成功，用户随后截图已无此前绿色竖条。完整频率识别验收尚未进行；构建与烧录证据见[本次修复档案](validation/green_lines_dsp_20261101/README.md)。
