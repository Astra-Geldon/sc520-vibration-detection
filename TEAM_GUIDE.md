# 队友上手指南：00020007网格测频备份

这是带振动检测的备份分支，当前功能以[README](README.md)为准，不是早期仅有灰度等算法的图像分支。

```powershell
git clone --branch backup/vibration-grid-r00020007-20261028 https://gitee.com/wang-zhanheng/sc520-vibration-detection.git
cd sc520-vibration-detection
git log -1 --oneline
```

已有仓库时先保存自己的修改，再fetch并切换到该分支；不要强制覆盖队友工作。此前`backup/vibration-grid-17bin-20261028`是00020001备份，`fix/hdmi-tx-valid`是图像基线，`main`由其他工作维护，本次均未覆盖。

当前为64帧、6×8网格、最多4槽、2.0～10.0Hz/0.5Hz；框是固定网格单元，不是物体外形包围框。共同运动实验停用，RVER=00020007。

编译必须在仓库根目录运行`.\td_project\patch\build_all.ps1`，完成A→B HDMI数据库修复→C，不能只点普通综合。TD入口不同时加`-TdExe`。核对资源、时序、补丁标志和固件生成时间后再由使用者烧录。Git不保存bit和数据库，切分支不会改变板上固件。

串口115200、8N1，每秒7行，HZ1～HZ4以十六进制输出频率×10；屏幕编号1～4与槽号对应。不要把全局最强原始峰当作一定合格的候选，也不要把CNFM=4当作四频率均正确。

用户已经测到3/5/8/10Hz四目标同时正确的片段，但仍有漏目标、3Hz附近误报10Hz及移动误框；这是可回退的当前进展版本，不是全部完成验收的最终版。本次上传不调整这些判据。

本版增加紧凑候选诊断，31字段、7行、441字节/秒。QBLK/QHZ/QMAG/QSTA是最强合格候选及入槽状态，P2HZ/P2MG是PBLK的非相邻次峰。已提供正对/斜拍反馈和四目标日志；状态以[当前记录](CURRENT_BASELINE_R00020007_20261028.md)为准。

此前00020006分支`backup/vibration-grid-r00020006-20261028`保留。下一步扩到12Hz尚未实施，本次上传仍是2～10Hz版本。
