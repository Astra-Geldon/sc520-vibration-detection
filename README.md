# SC520 五拨码实时图像增强系统 · 最终版

当前交付为用户确认保留的五拨码版本，适用于安路 **PH1P35MDG324（-3）＋SC520CS 摄像头**。2026-11-01 02:51:30 已完成 JTAG SRAM 下载；用户随后要求以“最终版”保存和发布。此次发布只整理说明与归档，未改变 RTL、参数或板上程序。

- Gitee 分支：`demo-five-switch-20261101`，不要把仓库默认分支当成本版本。
- “最终版”本地快照：`5abdac4`；对应 bit 的生产源码：`85c7f7d`。后续说明提交不需要重新编译。
- 当前全开彩色参数：**曝光 E900、gain code128（标称 G12）、shading k=0.75、固定 N1**。
- 保留原图/增强彩色、灰度、自适应二值化、Sobel、右上安路 Logo。KEY3/KEY4 旧候选菜单已移除。
- MCU 硬核被动接入；本版本没有装载 MCU 固件，拨码、曝光配置和图像处理均由 FPGA 逻辑执行。

## 获取和使用

```powershell
git clone --branch demo-five-switch-20261101 https://gitee.com/wang-zhanheng/sc520-vibration-detection.git
cd sc520-vibration-detection
```

本地工作区为 `D:\FPGA\codex\20261029project`。先阅读 [队友上手指南](TEAM_GUIDE.md)，需要自己下载 bit 时阅读 [编译与烧录](BUILD_AND_PROGRAM.md)。

### 当前 bitstream（本机已归档，直接烧录无需重编译）

```text
D:\FPGA\codex\_build\20261029project\final-20261101\SC520_final_five_switch_20261101.bit
```

SHA-256：`4d3e193aa914d10deed1493e32bebb461fea994d957756b77819ecc7fe7ebcdb`，大小 **1,789,539 字节**。它与 02:51:30 下载的文件逐字节相同。JTAG SRAM 配置掉电丢失，重新上电后需再次下载；没有写 Flash。

源码和说明提交到 Gitee；bit、数据库、完整工具日志保留在本机 `_build`，不混进源码仓库。云端读者无法通过上述本机路径下载 bit，需要本机持有者提供该文件，或按编译说明重建。

## 五拨码和按键

| 输入 | 引脚 | 开启 | 关闭 |
|---|---|---|---|
| SW1 | A4 | AWB 白平衡 | 单位增益，保留同步延迟 |
| SW2 | B4 | Gamma＋N1 中暗部提亮 | 两项同时旁路 |
| SW3 | E11 | Color Shading，固定 k=0.75 | 旁路空间颜色校正 |
| SW4 | D11 | 去马赛克，正常彩色 | RAW Bayer 样本灰度演示 |
| SW5 | C12 | E900／G12 高光保护 | E1991／G24 旧参数参考 |
| KEY1 | D5 | 返回增强彩色 | 短按一次 |
| KEY2 | A9 | 灰度→二值化→Sobel→灰度 | 短按循环 |

SW6 不使用，不需焊线。KEY3/KEY4 不再调参数。开关高电平定义为开启，实际拨动方向以 OSD 为准。

左下两行显示 `S1 AWB / S2 GAM / S3 CSC` 和 `S2 N1 / S5 EXP / S4 DEM`：绿色 ON、灰色 OFF、黄色 WAIT。SW2 共用一个开关，因此 GAM 与 N1 分别标 S2。切换后等待数秒再比较画质。

SW4 关闭时 AWB、CSC、N1 自动关闭，Gamma 仍随 SW2。N1 仅增强彩色模式参与；CSC 仅彩色/二值化参与。KEY2 的灰度显示与 SW4 的 RAW 灰度不是同一种处理。[详细操作和状态语义](FIVE_SWITCH_DEMO_20261101.md)。

## 当前图像链路

```text
SC520CS RAW10 → MIPI CSI → BGGR双线性去马赛克 → AWB → Gamma
    → RGB打包/DDR → Color Shading → 图像模式(img_proc)
    → 固定N1中暗部提亮 → 算法状态/Logo OSD → HDMI
```

曝光保护从传感器端降低整帧曝光和增益；N1 对中暗部逐像素提亮，峰值≥192时不再增加亮度。当前没有 H1 区域掩模、交替曝光、HDR 多帧融合或 D 降噪。

Gamma 为 **16 段锚点＋线性插值**；Color Shading 是 **10 列一维水平 R/B 增益表**；N1 才使用 **256 项固定 Q8 增益表**。AWB 保留前帧统计、串行除法和帧间平滑。精确说明、源码入口和局限见 [当前算法说明](CURRENT_ALGORITHMS.md)。

有效画面为 1280×720，HDMI 总时序1650×750、像素时钟约75MHz，输出约 **60.606Hz**。UGREEN 25854 是已使用的 HDMI 采集设备。采集软件选择30fps不代表FPGA输出降为30fps。

## 资源占用

以下为生产源码 `85c7f7d` 的最终布局布线结果，器件 PH1P35MDG324-3。拨码关闭算法仅作运行时旁路，**不会释放已配置的硬件资源**。

| 资源 | 用量 | 器件总量 | 占用率 |
|---|---:|---:|---:|
| LUT6 | 9,209 | 21,216 | 43.41% |
| Slice | 10,327 | 21,216 | 48.68% |
| FF | 8,972 | 42,432 | 21.14% |
| ERAM20K | 39 | 108 | 36.11% |
| DSP | 31 | 40 | 77.50% |
| PLL | 3 | 6 | 50.00% |
| MCU 硬核 | 1 | 1 | 100.00% |

相比认可的固定参数基线 `f86bc17`：**+368 LUT6、+486 Slice（+4.94%）、+296 FF**；ERAM/DSP/PLL/MCU 不变。增量来自动态旁路、去抖/跨域状态传递和新增左下面板。当前没有利用 MCU 卸载计算。

内部 setup/hold 裕量 **+0.123 / +0.020 ns**，STNS/HTNS=0。完整生产时钟检查和25组CDC路由延迟检查通过。外部接口时序覆盖边界沿用原工程，不能扩大解释为整个系统的完整时序签核。

[资源详细说明与历史版本对照](RESOURCE_USAGE.md) · [构建数据](validation/five_switch_demo_20261101/build.json) · [最终发布记录](validation/five_switch_demo_20261101/final_release.json)

## 工程结构和阅读顺序

| 位置 | 内容 |
|---|---|
| `user_source/hdl_source/design_top_wrapper.v` | 当前活动顶层、按键/拨码和完整图像链连接 |
| `user_source/hdl_source/isp/`、`awb.v` | 去马赛克、Gamma和活动AWB实现 |
| `color_shading*.v`、`fixed_n1_lift.v` | 水平颜色校正与固定N1 |
| `img_proc.v`、`osd_overlay.v`、`osd_logo_rom.v` | 灰度/二值化/Sobel、状态框和Logo |
| `uics520_cfg/`、`uiisp_beta/ae_set.v` | 传感器初始化、曝光/增益切换及重试 |
| `user_source/constraints_source/pin.adc` | 实体引脚约束 |
| `td_project/`、`td_project/patch/` | TD工程及必须保留的HDMI数据库补丁/时序检查 |
| `tools/` | 仿真、抓图和烧录辅助脚本 |
| `validation/five_switch_demo_20261101/` | 与当前源码绑定的小型验证/资源/下载证据 |
| `history/`、其余日期命名MD | 历史实验记录，不作为当前按键/算法说明 |

先读 [TEAM_GUIDE](TEAM_GUIDE.md)，再按需要查看 [算法](CURRENT_ALGORITHMS.md)、[资源](RESOURCE_USAGE.md)、[编译烧录](BUILD_AND_PROGRAM.md)、[MCU现状](MCU_USAGE.md) 和 [MCU经验](MCU_LESSONS.md)。[全部文档索引](DOCUMENTATION_INDEX.md) 标明当前与历史范围。

## 当前功能边界

当前没有微振动测频、串口诊断、旧候选参数菜单、色度降噪、多数滤波、高斯预滤波或阈值锁定；源文件存在不代表实例已参与综合。静态曝光保护不能保证任意强光场景都不过曝，N1不能恢复传感器已削顶的纹理；shading表也不是任意镜头/照明下的万能标定。

此次仅更新说明与版本归档，不重新编译或改写板上镜像。版权及授权以源码内原厂/原作者声明为准。
