# SC520CS图像处理与微振动识别

安路HX1P35A开发板（PH1P35MDG324，-3）与SC520CS摄像头的图像处理、微振动识别及HDMI整合工程。

当前源码分支为`codex/fusion-exposure-linked-lift`，在已上板融合版`d755598`上改为“自动曝光＋按曝光损失自动补亮”。本轮只修改源码并进行Icarus局部验证，**尚未完整TD编译、生成新bitstream或烧录**。目录中的旧Bit不包含本轮新按键逻辑，不能用它验收下表功能。融合原理及版本区分见[融合说明](FUSION_EXPOSURE_LINKED.md)。

## 获取与操作

```powershell
git clone https://gitee.com/wang-zhanheng/sc520-vibration-detection.git
cd sc520-vibration-detection
```

上述命令取得远端默认分支，不保证包含当前本地测试分支；本轮尚未推送远端。使用队友提供的工程时，先确认分支、提交和Bit来源。

| 输入 | 当前源码功能 |
|---|---|
| KEY1 | 回到原图／增强彩色模式 |
| KEY2 | 切换灰度、二值化、Sobel模式 |
| KEY3（I_key[2]，B9） | 微振动算法开关，上电默认关闭 |
| KEY4（I_key[3]，C7） | 自动曝光开关，上电默认开启 |
| SW1 | AWB白平衡 |
| SW2 | Gamma |
| SW3 | 水平Color Shading |
| SW4 | 去马赛克／RAW Bayer样本灰度 |
| SW5 | 允许按需自动补亮；不改变传感器曝光或增益 |

KEY4开启时只自动调整曝光时间参数E，范围128～1991，传感器增益固定G12；关闭后恢复E900/G12。SW5开启不代表立即提亮：检测到明暗区域并存时先保存参考曝光和中暗部亮度，连续有效帧确认后，只补偿E下降造成的中暗部损失；光源离开后自主渐退，E回升时减弱。SW2与补亮独立。

左下`K4 AE`显示ON/OFF/WAIT；`S5 N1`显示OFF（关闭或当前模式旁路）、ARM（已允许但没有实际补偿）、ON（正在补亮）、WAIT（控制或状态未就绪）。开关方向以OSD为准。SW4关闭时AWB/CSC/N1旁路，Gamma仍随SW2；振动或RAW模式暂停自动曝光。SW6不使用。详见[队友指南](TEAM_GUIDE.md)和[五拨码说明](FIVE_SWITCH_DEMO_20261101.md)。

## 工程范围与构建

图像采集、基础处理、视频缓存和HDMI沿用`20261029project`；微振动接入`backup-vibration-20261030`的实际RTL：640×360抽头、8×6分块、64帧窗口、2～15Hz/0.5Hz频点链路。KEY3、振动算法、摄像头启动和HDMI修复不属于本轮融合改动。HDMI优先，振动抽头保持被动监听。

当前工程只接入一个融合曝光控制器和一个融合补亮控制器。旧`ae_set.v`、`fixed_n1_lift.v`保留作历史参考，已退出活动编译入口。延迟显示口径见[延迟显示说明](LATENCY_DISPLAY.md)。

完整构建按[编译烧录说明](BUILD_AND_PROGRAM.md)执行`td_project/patch/build_all.ps1`的A→B→C，保留加密HDMI核12处数据库补丁和CDC审计。Icarus通过不能替代布局布线、资源及物理CDC检查。

## 已烧录旧融合版与资源

可回滚的旧源码提交为`d755598`。已烧录Bit为`td_project/camera_to_dsi_display_ae_shadow_fusion_20261102.bit`，1,789,539字节，SHA256：

```text
908e5c61e438f0c32dd2b8335234ba548e73360c325c11255fb950cae2110db6
```

**以下全部是旧融合版的物理资源，本轮新源码的资源和时序尚未测得。**旧版报告见[构建记录](validation/ae_shadow_fusion_build_20261102/build_result.json)。

| 旧融合版资源 | 已用／总量 | 占用率 |
|---|---:|---:|
| IO | 68／160 | 42.50% |
| LUT6 | 17,570／21,216 | 82.81% |
| FF（Slice寄存器） | 17,696／42,432 | 41.70% |
| Slice | 18,510／21,216 | 87.25% |
| F7MUX | 265／10,608 | 2.50% |
| F8MUX | 84／5,304 | 1.58% |
| ERAM20K | 66／108 | 61.11% |
| DSP | 40／40 | 100.00% |
| MCU | 1／1 | 100.00% |
| DDR_BYTE | 6／12 | 50.00% |
| MIPI_TX | 0／2 | 0.00% |
| MIPI_RX | 1／2 | 50.00% |
| PAD | 27／160 | 16.88% |
| PLL | 3／6 | 50.00% |
| GCLK | 10／32 | 31.25% |
| LCLK | 0／12 | 0.00% |
| SCLK | 28／48 | 58.33% |
| MLCLK | 2／6 | 33.33% |
| IOCLK | 4／18 | 22.22% |

旧融合版SWNS为+0.103ns、HWNS为+0.020ns，STNS/HTNS为0，40组CDC检查通过。旧版DSP已满；本轮新增运算采用移位加法和串行控制，最终DSP映射仍须由新TD报告确认。MCU被动接入，未加载应用固件；UART诊断由FPGA实现。

更早的图像/整合版本资源保留在[资源档案](RESOURCE_USAGE.md)，不能当成本轮资源结果。Git保存源码和验证摘要；Bit、数据库及完整工具报告保留本地。JTAG SRAM配置掉电丢失。

[当前算法](CURRENT_ALGORITHMS.md)·[自动曝光](AUTO_EXPOSURE.md)·[整合记录](INTEGRATION_NOTES.md)·[文档索引](DOCUMENTATION_INDEX.md)
