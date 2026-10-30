# 队友上手指南

> 更新日期：2026-10-26。先确定分支，再按对应README操作。
> 本文件随Git提交和Gitee推送；本机`docs/`是补充笔记，不是使用工程的前提。

## 1. 先选择要用的版本

|用途|分支|功能与状态|
|---|---|---|
|本次 MCU + 原图像链交接|`A-original-reuse`|提交 `ee675b6`，右上角安路 Logo 已启用；MCU 仅被动接入，详见 `MCU_USAGE.md`|
|使用已认可的普通光照图像版本|`fix/hdmi-tx-valid`|源码基线`73c0f35`，加入文档澄清；没有高光自动曝光保护|
|继续高光保护实验|`codex/highlight-protection-test`|保留`6662832`测试代码，合入稳定版文档；尚未完成板上效果验证|

本仓库的`main`另有队友维护的振动工作。本文交接的是上表两条图像分支，不要只下载默认分支就认为拿到了这里的图像版本。

首次获取稳定版：

```powershell
git clone git@gitee.com:wang-zhanheng/sc520-vibration-detection.git
cd sc520-vibration-detection
git switch --track origin/fix/hdmi-tx-valid
git log -1 --oneline
```

已有本地仓库且工作区干净时，更新稳定分支：

```powershell
git fetch origin
git switch fix/hdmi-tx-valid
git pull --ff-only origin fix/hdmi-tx-valid
git status --short --branch
```

要做高光实验，在干净工作区执行`git switch codex/highlight-protection-test`；首次切换时Git可从对应远端分支建立本地分支。切换前先提交自己的修改；命令提示有冲突或本地修改时，先处理具体问题，不要直接强制覆盖。

切完后读**当前分支**的[README](README.md)，尤其是开头的版本状态与资源表。

## 2. 工程默认做什么

SC520CS摄像头采集RAW10，经去马赛克、AWB、Gamma、DDR、空间颜色校正后，输出1280×720的HDMI图像。像素时钟75MHz，1650×750时序约60.606Hz；UGREEN 25854采集卡已验证能锁定。

两条图像分支默认均关闭`VIB_ON`，因此没有振动测频输出。历史振动规划和历史验证记录不能据此当作当前默认功能。

“原图”表示不做`img_proc`中的灰度、二值化或边缘处理，**仍然经过AWB、Gamma和空间颜色校正**。它不是传感器未经处理的原始数据。

## 3. 按键按一下即可，不用长按

|按键|引脚|稳定版|高光测试版|
|---|---|---|---|
|KEY1|D5|原图|原图|
|KEY2|A9|灰度→二值化→Sobel→灰度|相同|
|KEY3|B9|扩展算法组；当前`EXT_N=0`，无效果|临时开/关高光曝光保护，上电默认关闭|
|KEY4|C7|颜色校正档位0→1→2→3→0|相同|

KEY4四档对应k=0/0.5/0.75/1.0，上电默认档位2。左上OSD显示算法名，左下数字只显示KEY4档位，右上为固定安路Logo。

KEY4切到0仅关闭空间颜色校正，不关闭AWB或Gamma。旧`I_button`的N2/J14不是上述板载键。

测试版目前**没有高光开关状态OSD**，左下数字不能判断高光开关；复位可回到默认关闭状态。KEY3的临时用途只限这次测试，转正式版时必须恢复扩展算法组。

## 4. 编译必须保留HDMI数据库补丁

使用安路TD 6.2.168116，器件PH1P35MDG324、-3速级。在仓库根目录运行：

```powershell
Get-Process hwserver -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item td_project\baseline_rtl.db,td_project\patched_rtl.db,td_project\pA.log,td_project\pB.log,td_project\pC.log -ErrorAction SilentlyContinue
.\td_project\patch\build_all.ps1
```

三阶段分别是A综合、B修复12处HDMI加密核计数器选择信号、C布局布线和bitgen。不要直接用GUI的Run或旧`flow_build.tcl`代替完整流程，否则会遗漏补丁。

构建脚本默认TD入口为`F:\Anlogic\bin\td_commands_prompt.exe`。队友的安装位置不同时，传入自己的实际路径：

```powershell
.\td_project\patch\build_all.ps1 -TdExe 'D:\实际安装目录\bin\td_commands_prompt.exe'
```

不要把器件速级`set speed 3`改成4。

|验收项|需要看到什么|
|---|---|
|A/C日志|`PHASE_A_DONE ERR=0`、`PHASE_C_DONE ERR=0`|
|B日志|`PATCH_FINISHED`和`VERIFIED_COUNTER_SELECTORS12`|
|时序与布线|SWNS/HWNS为正、STNS/HTNS为0，未布线端点为0|
|产物|`td_project/camera_to_dsi_display.bit`的生成时间符合本次构建|

bit存在、bitgen完成或脚本退出成功，都不能单独证明画面或算法正确。一次完整编译约15分钟；文档修改不需要编译，参数实验优先用一次固件内的按键对照。

## 5. Git版本、磁盘bit和板上版本是三件事

Git不跟踪bit、综合数据库、资源报告和运行日志。拉代码或切分支不会更新这些文件，也不会改变FPGA当前配置。资源只能引用与源码匹配的报告。

每次构建保留对应的源码提交、bit生成时间、SHA256和构建日志，例如：

```powershell
git rev-parse HEAD
git status --short
Get-Item td_project\camera_to_dsi_display.bit | Select-Object Name,Length,LastWriteTime
Get-FileHash td_project\camera_to_dsi_display.bit -Algorithm SHA256
```

接手者从Git获取的是源码；没有与目标版本对应的bit时需要构建。不要借用文件名相同的旧bit，也不要把本机旧实验备份当作当前基线。

## 6. 烧录与采集

确认板子上电、FTDI/JTAG接好，并核对目标bit后，在仓库根目录执行：

```powershell
.\tools\burn.ps1 -Bit 'td_project\camera_to_dsi_display.bit'
```

TD安装路径不同时，烧录脚本也支持`-TdExe`参数。它会复制bit到临时路径、清理残留hwserver、执行下载，并检查`PRG-2014 Chip validation success: PH1P35MDG324`。FTDI设备未找到、连接失败或芯片校验失败都不算烧录成功。

JTAG配置掉电丢失，每次重新上电都需要烧录。

采集卡抓帧先关闭Windows相机、OBS等可能占用设备的软件，再执行暖机抓帧：

```powershell
.\tools\capture.ps1 -Count 2 -Warmup 120 -OutDir 'capture_check'
```

抓帧脚本需要PATH中有ffmpeg、Python3，且该Python环境安装了numpy和Pillow。缺少图像分析依赖时，在使用的Python环境中执行`python -m pip install numpy pillow`。

暖机初期的黑帧不能直接证明HDMI坏了；录像软件的30fps也不代表FPGA输出30Hz。用户的视频是FPGA的HDMI直接采集，不是手机拍屏。

## 7. 资源看哪里

完整资源类型、总量、占用率、余量及DSP分配见当前分支的[README资源表](README.md#baseline-resources)。稳定版与测试版构建数字不同，不能混用。

两版DSP均为31/40：AWB11、Gamma12、空间颜色校正8，剩9个。扩展算法不能按“还有40个DSP”预算。真正参与编译的AWB文件是`user_source/hdl_source/awb.v`，工程中有同名备份目录，不要改错。

## 8. 高光测试版的边界

该测试版来自`6662832`，本次合并只同步文档，不代表算法修复完成。已完成过三阶段构建，但此前下载失败，未完成板上效果验证。高光计数位宽/阈值分母、持续补光时曝光恢复策略等仍有已知问题需要修正；静态检查通过不能替代行为验证。

KEY3关闭时恢复曝光1991，但测试版Gamma末段也有修改，所以“关闭高光保护”不等于恢复稳定版的全部像素映射。普通光照不受影响仍需实测，不能提前写成验收结论。
