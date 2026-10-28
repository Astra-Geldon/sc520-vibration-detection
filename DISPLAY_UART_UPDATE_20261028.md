# 框内编号、频率与精简串口日志（2026-10-28）

本次在19点24分生成、用户已上板的17频点修复版本上，仅修改显示与日志。振动采样、Goertzel、峰值筛选、阈值、相邻去重与连续确认均未改动。旧的已上板版本已在Gitee的`backup/vibration-grid-17bin-20261028`分支备份；此处新增显示版本尚待用户自行完整编译、烧录。

## 屏幕

- 保持6行×8列，单框160×120显示像素、2像素边框。
- 框内左上显示1～4，对应串口HZ1～HZ4、OBM1～OBM4与OBP1同槽位；这是目标槽位编号，并非永久物体ID。
- 框内右上显示十进制频率，例如`3.0Hz`、`8.0Hz`、`10.0Hz`。支持现有全部17频点，不显示未知编码。
- 字形10×14像素，同框颜色，窄黑底；标签黑底距网格上/左或右边界6像素，完整留在框内。
- 颜色：1品红、2青色、3黄色、4橙色。四槽颜色未变。
- 删除左上绿色L形参考标识。保留上沿、左沿的白色分块刻度，保留原算法名称和安路Logo。
- 位置与频率经窗口完成toggle成对复制到像素域，在帧消隐期锁存；一帧内使用同一组目标数据。
- 字模和位置译码使用组合逻辑及寄存器，没有新增乘法、除法或块RAM实例。实际映射资源以用户的TD报告为准。
- 叠加模块将RGB、DE、VS共同延迟3拍；算法视频抽头位于叠加之前。像素计数改为在DE下降沿换行，并在VS消隐边沿重同步，消除旧计数的首像素/首行错拍。

## 串口

保持115200、8N1、每秒一轮。每轮从45行/697字节改为7行/441字节，取消重复横幅及空行。所有值仍为8位十六进制，屏幕频率使用十进制；例如串口`00000050`对应屏幕`8.0Hz`。

```text
SEC  xxxxxxxx WINC xxxxxxxx RVER xxxxxxxx VTAP xxxxxxxx ITER xxxxxxxx
ACT  xxxxxxxx QACT xxxxxxxx CNFM xxxxxxxx STK0 xxxxxxxx OBP1 xxxxxxxx
HZ1  xxxxxxxx HZ2  xxxxxxxx HZ3  xxxxxxxx HZ4  xxxxxxxx
OBM1 xxxxxxxx OBM2 xxxxxxxx OBM3 xxxxxxxx OBM4 xxxxxxxx
PBLK xxxxxxxx PKMG xxxxxxxx RBIN xxxxxxxx RHZ  xxxxxxxx AEXP xxxxxxxx
F04  xxxxxxxx F06  xxxxxxxx F08  xxxxxxxx F10  xxxxxxxx
MBFR xxxxxxxx CLRC xxxxxxxx SCNC xxxxxxxx WPRD xxxxxxxx
```

ACT/QACT/CNFM仍分别为原始过能量门、过突出度门、连续确认后的数量。OBM为raw peak >> 8。PBLK及同组频谱字段指原始最强块，不一定是已确认目标。RVER保持`00020001`，表示检测算法未变。

默认停用并在生成器/RTL快照处注释：VOFP、VOFL、ITPX、ITLN、VSUM、AGCR、FXBX、FXEN、TON1、TON2、FBPN、CHLK、TNST。输入接口保留，便于后续定向恢复诊断。当前保留VTAP/ITER异常计数以及CLRC/SCNC完整性检查。

生成器为`tools/gen_uart_log2.py`，后续修改`FIELD_GROUPS`后重新生成。可运行`python tools/gen_uart_log2.py --check`只核对一致性。

用户使用VOFA+ 1.3.10。按行数限制的历史容量可约延长6.4倍，按字节限制约1.58倍。如果软件采用固定时间截止，固件压缩不能改变该时间，长时间完整留档仍需接收软件保存到文件。

## 本次检查与上板核对

已完成实际RTL仿真：OSD共20场景、3,287,040像素逐点比对，覆盖四角、四槽编号、全部17频点、白色刻度、绿色参考移除、帧中目标更新与RGB/DE/VS对齐。UART使用实际发送器，从串行引脚解码3轮1323字节，逐字节匹配，并核对整轮快照及1秒间隔。生成器和RTL一致性、端口、工程路径与未改算法文件校验另有本次验证记录。

未启动TD、未烧录、未生成新bitstream。用户仍需执行完整A→B→C流程，确认HDMI修复、DSP40/40约束、资源及SWNS/HWNS，再上板检查：四个边角文字不截断；屏幕编号与HZ槽位对应；框消失时文字同时消失；白色刻度保留且绿色L消失；每秒恰好7行完整日志。

源码变更入口：`design_top_wrapper.v`、`vibration/vib_osd_marker.v`、`uart_log_debug.v`、`tools/gen_uart_log2.py`。marker已由顶层include，不需新增TD Design Files，否则可能重复定义。约束、PLL/GCLK、HDMI加密核和振动检测核心文件未修改。
