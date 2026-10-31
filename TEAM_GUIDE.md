# 队友上手指南 · 当前最终版

适用分支 `demo-five-switch-20261101`，更新日期2026-11-01。旧图像分支、微振动分支和历史参数菜单不适用于本说明。

## 先把画面跑起来

1. 按 [README](README.md) 获取指定分支。连接SC520CS、开发板电源、USB/JTAG、HDMI显示器或UGREEN采集卡。
2. 使用 [已归档bit及烧录步骤](BUILD_AND_PROGRAM.md)，不需要每次重新编译。下载后等待摄像头初始化。
3. 按KEY1回到彩色，将左下六项调为绿色ON。开关方向以屏幕为准，SW6不用，不焊线。
4. 移动物体确认实时视频；右上显示安路Logo，左上显示模式，左下显示增强算法状态。

## 演示方法

| 开关 | 对比项 | 观察方法 |
|---|---|---|
| SW1 | AWB白平衡 | 对准有白纸和彩色物体的场景，切换后等待色彩稳定 |
| SW2 | Gamma＋N1 | 两项一起改变，比较中暗部亮度与层次 |
| SW3 | 水平颜色校正 | 固定构图，对比左右颜色均匀性 |
| SW4 | 去马赛克／RAW样本灰度 | OFF为Bayer样本演示，非正常彩色转灰度 |
| SW5 | 低曝光低增益／旧参数 | 比较亮部与暗部，等待EXP从WAIT转成ON/OFF |

SW4关闭时AWB/CSC/N1会自动OFF；不是三只开关失灵。KEY2循环灰度/二值化/Sobel，KEY1随时回彩色。KEY3/KEY4无调参功能。左下不再显示旧k档位、C/D/P/W/G/N候选编号。

EXP显示已完成控制器ACK及生效等待；没有实时寄存器读回。其他状态也不是DDR中每个像素的逐帧标签，切换稳定数帧后再比较。

## 要改代码时

当前链路、表和参数见 [CURRENT_ALGORITHMS](CURRENT_ALGORITHMS.md)，资源预算见 [RESOURCE_USAGE](RESOURCE_USAGE.md)。真正使用的AWB是 `user_source/hdl_source/awb.v`，不是同名备份。`img_proc`默认参数不代表顶层实例配置，当前多数滤波/高斯/阈值锁定都关闭。

修改RTL后要完整A→B→C构建，不直接用GUI Run或旧flow脚本替代；加密HDMI核必须保留12处计数器选择补丁。编译输出都放 `_build`，操作步骤见 [BUILD_AND_PROGRAM](BUILD_AND_PROGRAM.md)。本次文档整理不改变已烧录bit。

## MCU和采集

当前MCU没有运行项目固件，也不控制曝光或拨码。需要扩展时先看 [MCU现状](MCU_USAGE.md) 和 [MCU经验](MCU_LESSONS.md)，不要把其他历史迁移工程的板测结论套到本版本。

抓图前关闭占用UGREEN的预览程序，显式选择 `UGREEN 25854`；不要误选电脑摄像头。新打开采集卡可能先有数秒黑帧/启动画面，稳定后再评价；黑场或完全遮挡本来就可能接近黑色。

```powershell
.\tools\capture.ps1 -Device 'UGREEN 25854' -Count 2 -Warmup 120 -OutDir 'D:\FPGA\codex\_build\20261029project\manual-capture'
```

需要ffmpeg及Python的numpy/Pillow。采集的30fps是采集设置，FPGA HDMI输出约60.606Hz。历史MD和旧validation记录只用于追溯，[索引](DOCUMENTATION_INDEX.md) 给出了适用范围。
