# SC520CS图像处理与微振动识别

安路HX1P35A开发板（PH1P35MDG324，-3）与SC520CS摄像头的图像处理、微振动识别及HDMI整合工程。

当前交付基线源自提交d1fe233（初赛final），已完成自动曝光/补亮死代码清理、高斯行缓存复用和视频抽头行缓存ERAM迁移。当前保留UART诊断，ISP深度压缩实验已回退；本地Bit已完成A→B→C、时序与CDC检查，并通过JTAG下载。各实验结果见[资源压缩研究](RESOURCE_COMPRESSION_RESEARCH.md)。

## 获取与操作

```powershell
git clone https://github.com/Astra-Geldon/sc520-vibration-detection.git
cd sc520-vibration-detection
```

GitHub以main分支交付当前源码，同时保留codex/resource-compression-research分支。仓库为私有，克隆需要对应访问权限；Gitee远程保留为原有来源。Bit、TD数据库和临时仿真文件不随Git上传，取得源码后请按构建说明重新生成Bit，并核对实际构建的哈希。

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

KEY4开启时只自动调整曝光时间参数E，范围128～1991，传感器增益固定G12；关闭后恢复E900/G12。SW5开启只表示允许判断，不代表立即提亮：显示端在彩色非RAW模式下根据12个粗区域的亮暗和反差证据触发Tone处理，并记录触发前稳定帧的E和中暗部统计。AE稳定至少3个有效帧后，补亮强度才按每个有效帧最多1级变化，最高16级；场景不再满足保持条件且AE以同一E稳定约45个有效帧（约0.75秒）后，控制器自主退出并逐步回到0级。当前RTL没有用E差值或中暗部误差直接计算强度，因此“恢复到触发前观感”必须以上板实拍为准，不能仅由代码保证。SW2与补亮独立。

左下`K4 AE`显示ON/OFF/WAIT；`S5 N1`显示OFF（关闭或当前模式旁路）、ARM（已允许但没有实际补偿）、ON（正在补亮）、WAIT（控制或状态未就绪）。开关方向以OSD为准。SW4关闭时AWB/CSC/N1旁路，Gamma仍随SW2；振动或RAW模式暂停自动曝光。SW6不使用。详见[队友指南](TEAM_GUIDE.md)和[五拨码说明](FIVE_SWITCH_DEMO_20261101.md)。

## 工程范围与构建

图像采集、基础处理、视频缓存和HDMI沿用`20261029project`；微振动接入`backup-vibration-20261030`的实际RTL：640×360抽头、8×6分块、64帧窗口、2～15Hz/0.5Hz频点链路。KEY3、振动算法、摄像头启动和HDMI修复不属于本轮融合改动。HDMI优先，振动抽头保持被动监听。

当前工程只接入一个融合曝光控制器和一个融合补亮控制器。旧`ae_set.v`、`fixed_n1_lift.v`保留作历史参考，已退出活动编译入口。延迟显示口径见[延迟显示说明](LATENCY_DISPLAY.md)。

完整构建按[编译烧录说明](BUILD_AND_PROGRAM.md)执行`td_project/patch/build_all.ps1`的A→B→C，保留加密HDMI核12处数据库补丁和CDC审计。Icarus通过不能替代布局布线、资源及物理CDC检查。

[当前算法](CURRENT_ALGORITHMS.md)·[自动曝光](AUTO_EXPOSURE.md)·[整合记录](INTEGRATION_NOTES.md)·[文档索引](DOCUMENTATION_INDEX.md)
