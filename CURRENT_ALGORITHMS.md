# 当前算法与实际数据链路

适用提交`d1fe233 初赛final`源码及本轮清理工作树。当前清理版Bit已完成TD综合、布局布线、Bit生成和40组物理CDC审计；烧录状态以最新哈希和日志为准，旧实现仅在历史提交中保留。

## 活动链路与算法位置

```text
传感器曝光（KEY4自动调整E；关闭后E900；G固定G12）
SC520CS RAW10 → MIPI CSI → BGGR双线性去马赛克（SW4）
→ AWB（SW1）→ Gamma（SW2）→ RGB打包/DDR帧缓存
→ Color Shading（SW3）→ img_proc模式 → Tone高光压缩＋暗部提升（SW5允许）
→ 状态/模式名/安路Logo OSD → HDMI

AWB/Gamma前被动抽样 → 背景优先AE（紧急高光保护）→ 已生效E回传至补亮
ISP被动抽头 → 640×360微振动链路 → 结果标记叠加至HDMI
                               └→ UART诊断
```

源代码入口：[顶层](user_source/hdl_source/design_top_wrapper.v)、[ISP](user_source/hdl_source/isp/isp_top.v)。图像路径保持原流式处理和DDR视频缓存，无交替曝光；振动路径另用外部DDR保存上一帧。六项显示为DEM/AWB/GAM/CSC/N1/AE；Gamma只由SW2控制，补亮只由SW5允许。KEY3独立控制微振动，默认OFF；KEY4控制AE，默认ON。

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
x=255时特殊输出255
```

当前示例映射：16→37、128→157、240→244、255→255。函数名虽为gamma07，当前修改后的实际曲线不能描述为精确0.7次幂，也不是256项直接输出LUT。

关闭时同一寄存拍选择原值，保留像素/同步延迟。它与N1不同：Gamma在DDR前作用于各RGB通道，N1在显示后端共用一个RGB增益。

## 4. Color Shading：一维水平R/B颜色校正（SW3）

实现：[color_shading.v](user_source/hdl_source/color_shading.v)、[color_shading_lut.v](user_source/hdl_source/color_shading_lut.v)。当前表为 **10列×1行**，每128像素一列，列间分32级、每4像素更新插值；不按y坐标分区，不是旧10×6二维表。

R/B使用Q8增益，G直通。顶层强度固定k=0.75，SW3在校正输出和输入像素间选择；没有将动态强度送入新乘法器。R/B最终按8位饱和，已经削顶的信息不会靠后级处理恢复。

表来自既有多场景经验校准，是静态空间补偿；AWB负责全局色温，二者不能相互替代。换镜头、模组或照明后可能需重新评估，不能称为自动标定或通用降噪。

## 5. 融合补亮：高光压缩与暗部提升Tone LUT（SW5）

实现：[fusion_shadow_lift.v](user_source/hdl_source/fusion_shadow_lift.v)。SW5只允许补亮，不选择曝光档。关闭、未触发或实际强度为0时，对原图逐位旁路；补亮只在彩色、非RAW模式工作，和SW2的Gamma独立。

显示端在补亮前做4×3粗区域明暗统计；SW5允许且未触发时持续保存稳定正常帧作为候选基线，进入后锁存参考E和中暗部统计，再由连续有效帧完成参考计算并确认触发。粗区域只判断是否需要，不分别施加区域增益。保持条件解除后强度逐帧下降；约8次评估不满足保持条件、强度退到0且同一E稳定45个有效帧（60Hz约0.75秒）后退出。

当前RTL记录参考E和中暗部统计，但参考量目前不直接参与强度数值或E差值反馈计算。同一已生效E稳定至少3个有效帧后，保持条件成立时公共Tone强度逐帧增加到0～16级，条件解除时逐帧减小；“恢复到触发前观感”必须以上板实拍确认。曝光在途、无效帧和DDR过渡帧暂停统计证据，保留此前候选参考。

像素处理使用16段Tone LUT生成统一包络：暗部提升，中间调平滑，高光进入肩部压缩，输入255保持255。每个RGB通道查同一条曲线，再按`原图+round((包络−原图)×strength/16)`混合；包络高于原值时提亮，低于原值时压缩高光。它不再是固定增益表，也不是SW2开启就始终叠加的常开N1。

Tone LUT的16段锚点以输入高4位分段，段内用低4位移位加法插值，不新增DSP或帧缓存。统一包络和公共强度避免分区接缝，计算复用既有视频寄存级，不增加总视频拍数。当前DSP、Slice和时序结果见README及RESOURCE_USAGE。

补亮受包络上限限制，极大曝光损失可能无法完全补回；场景移动、照明变化和噪声也可能影响亮度参考。传感器或前级已经削顶的信息无法由后级恢复。详见[融合说明](FUSION_EXPOSURE_LINKED.md)。

## 6. 背景优先自动曝光与紧急高光保护（KEY4）

活动控制入口：[fusion_exposure_control.v](user_source/hdl_source/fusion_exposure_control.v)；统计入口：[ae_luma_sampler.v](user_source/hdl_source/ae_luma_sampler.v)。真实写入仍由[uicfgcs520.v](user_source/hdl_source/uics520_cfg/uicfgcs520.v)、[uics520regAE.v](user_source/hdl_source/uics520_cfg/uics520regAE.v)和[SC520GainTbl.v](user_source/hdl_source/uics520_cfg/SC520GainTbl.v)完成。

KEY4默认ON，从E900、增益码128（标称G12）开始，只迭代E128～1991；关闭后恢复E900/G12。SW5不再连接曝光控制器。E是传感器控制参数，不是毫秒，G保持固定。

AWB/Gamma前每16个四像素包抽取一个像素，完整720p帧14,400样本，统计六位亮度`(R+2G+B)>>4`并归入8个亮度桶。控制器以排除最高桶后的背景P60为主要依据：P60低于22增曝，高于30减曝，其他情况保持；背景有效样本少于40%时保持。亮度≥60的样本达到10%时触发紧急减曝，防止大面积饱和。该策略把微振动目标所在的大部分背景作为优先观测区域。

每次真实参数组完成后丢弃3个新统计帧，再要求2个连续同向反馈，步长约E的1/16。补亮另要求同一已生效E稳定至少3个有效帧才改变强度，退出要求约45个有效帧稳定。保持原上电/真实FS等待、完整8写、NACK有界重试和写后两帧等待。done先低后高且摄像头配置正常才确认，不能把初始化时done为高误当完成。振动或RAW暂停自主调整，已启动组写正常结束。

`O_ae`仅为请求值；补亮只读取另外保存的已生效E和有效位。参数在途、模式过渡、冻结或配置失效期间不接受该状态作为新补亮统计依据。跨域邮箱在HDMI帧界提交，显示端隔离过渡帧；这仍不是寄存器读回证明或DDR逐像素世代标签。详见[自动曝光说明](AUTO_EXPOSURE.md)。

## 模式与OSD

[img_proc.v](user_source/hdl_source/img_proc.v)的活动配置是：自适应二值化开启，多数滤波/高斯预滤波/阈值锁定关闭。灰度`(R+2G+B)>>2`；灰度与Sobel取DDR读出数据，不经过shading或N1。二值化固定取shading后的输入，阈值为上一帧均值并作1/4帧间平滑。Sobel为3×3的`|Gx|+|Gy|`，保留原邻域边界/延迟。

[osd_overlay.v](user_source/hdl_source/osd_overlay.v)显示原四模式名称、安路Logo、延迟和六项状态。`K4 AE`显示ON/OFF/WAIT；`S5 N1`显示OFF（关闭或模式旁路）、ARM（允许但实际强度为0）、ON（正在补亮）、WAIT（控制或状态未就绪）。关闭算法不会实时释放FPGA资源。

## 已退出活动编译入口的历史实现

旧`uiisp_beta/ae_set.v`、`fixed_n1_lift.v`不再作为本轮活动入口。旧N1增益表也未接入当前工程；当前唯一显示端包络由`fusion_tone_lut`生成，没有另一路常开固定N1，也没有另一套独立AE与融合AE并行运行。

H1掩模、C0～C3补偿、D降噪、P肩部/W颜色保护、E/G/N候选菜单、交替曝光和旧大诊断逻辑仍属于历史实验。历史记录见[文档索引](DOCUMENTATION_INDEX.md)，当前精确资源见README及RESOURCE_USAGE。

## 微振动识别与结果输出

活动链路复用备份工程的被动抽头、帧差/预处理、分块LK、Goertzel频率分析、峰值确认及包围框标记。实际RTL为640×360、8×6分块、64帧窗口、27个频点，2～15Hz、间隔0.5Hz，未改为规划中的320×180方案。

KEY3默认OFF；关闭时算法链保持复位，振动DDR请求被门控，HDMI振动标记旁路。开启后运行识别并叠加标记，保留UART诊断。抽头不向图像路径施加反压，DDR调度以HDMI连续输出为优先。本轮未改振动算法。

`vib_bbox_grid`保留`dsp_style="no"`资源属性，用于避免DSP压力导致图像模块被自动合并，算法公式、位宽和流水节拍沿用。当前清理版总DSP为40/40、LUT6为17,780、Slice为18,576、REG为17,886，具体资源见README及RESOURCE_USAGE。全部旧资源及证据见[README](README.md)。

旧版曾确认绿色竖条消失；完整振动测频精度不在本轮验收范围。当前清理版已完成TD综合、布局布线和Bit生成，板上效果需使用最新Bit单独验收。
