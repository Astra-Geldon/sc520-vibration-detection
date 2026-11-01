# 前端抽样自动曝光

工程：`D:\workplace\anlogic\sc520-vibration-detection-main`。本次仅修改源码并进行局部仿真、静态检查，未运行 TD、未更新 Bit、未烧录。

## 操作

- 上电默认开启。按 **C7／I_key[3]（K3，原 KEY4）** 切换；10 ms 消抖，长按只切换一次。上电一直按住时，先释放再按。
- 左下原 `S5 EXP` 项改为同样大小的 **`K3 AE`**：ON 绿色，OFF 灰色，WAIT 黄色。WAIT 表示初始化、参数写入等待，或振动／RAW 模式暂停自动调整。
- 自动模式从曝光900、增益码128开始，忽略 SW5。关闭后恢复 **当前 SW5** 的固定档：ON=900/128，OFF=1991/160，待参数组完成后显示 OFF。
- 振动开启（原 KEY3／I_key[2]／B9）或 SW4 关闭进入 RAW Bayer 展示时，保持当前曝光，暂停自主调整。恢复后等待新帧再继续。模式切换的基础参数归一化仍会完成，已经启动的 I2C 事务也会正常结束。

## 实现与范围

复用 AWB 输入端 `(R+2G+B)>>4` 的6位亮度，但使用独立、无肤色或过曝筛选的统计。每16个有效96位包取第0个像素，完整720p帧为14400样本；20位和直接比较常数门限，不求平均值。均值小于16判暗，大于24判亮，中间保持。门限处于 AWB/Gamma 前的线性域，需按上板效果标定。

每次传感器参数组完成后丢弃3个新统计帧，再要求连续2个同方向结果。曝光按当前值约1/16增减，限制128～1991；增益固定128。只有真实 done 低→高且摄像头配置正常才发布生效，复用原帧边界调度、8次寄存器写、NACK重试与写后等待。短帧、长帧、RAW过渡帧均不给控制器有效亮度反馈。

该方案不新增运行时乘除法、DSP、ERAM或DDR访问；视频路径只增加被动信号输出。逻辑规模原估计约150～300 LUT、100～180 FF，实际资源、Slice与时序须以本次 TD 结果为准。统计规则中的乘法均为 elaboration 常数。固定增益下，极暗环境达到最长曝光后仍可能偏暗；全局曝光不能同时解决强逆光的所有区域。

## 验证与构建

验证目录：`validation/auto_exposure_20261101/`；修改前源码在 `before/`，对应哈希在 `before_sha256.json`。本轮不把已有旧 Bit 当作 AE 构建结果。

可复现局部检查：

```powershell
python tools/test_ae_luma_sampler.py
python tools/test_auto_exposure.py
python tools/test_five_switch_sensor.py --output validation/auto_exposure_20261101/manual_sensor
python tools/test_video_latency_osd.py
python tools/check_all_inst.py
python tools/check_video_latency_integration.py
```

新增统计邮箱和K3同步器已纳入SDC，现共40组CDC审计。静态/mock检查不能替代布线时序。由用户按 `BUILD_AND_PROGRAM.md` 运行完整 A→B→C，并检查本次 DSP≤40、setup/hold收敛以及40组CDC物理检查通过后，再烧录观察亮暗变化与K3状态。
