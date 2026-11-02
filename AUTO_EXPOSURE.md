# 融合版自动曝光

适用于`E:\杂七杂八\4竞赛\FPGA\sc520-vibration-detection`的`codex/fusion-exposure-linked-lift`源码。本轮只进行源码和Icarus验证，未完整TD编译、未生成新Bit、未烧录。全套融合行为见[FUSION_EXPOSURE_LINKED](FUSION_EXPOSURE_LINKED.md)。

## 操作

- KEY4（I_key[3]，C7）切换自动曝光，上电默认开启；10ms去抖，长按只切换一次。上电一直按住时，先释放再按。KEY3仍控制微振动。
- 左下标签为`K4 AE`：ON表示自动模式已提交，OFF表示关闭后的固定参数组已提交，WAIT表示初始化、写入等待、模式过渡或振动／RAW暂停。
- 自动模式从E900、增益码128开始。只调整E，范围128～1991；增益码128对应标称G12，保持固定。关闭自动曝光后恢复E900/G12。
- SW5只允许显示端自动补亮，不再选择固定曝光档；SW2只控制Gamma。两个开关都不会向本控制器提交E/G参数。
- 振动开启或SW4关闭进入RAW时，暂停自主调整。恢复后等待新统计再继续。已经启动的I2C事务正常结束，模式切换的基础参数归一化仍会完成。

E是传感器曝光控制参数，不是毫秒；本文的G12为标称总增益，不是会随AE自动变化的控制量。

## 测光与控制

活动入口为[fusion_exposure_control.v](user_source/hdl_source/fusion_exposure_control.v)，前端统计为[ae_luma_sampler.v](user_source/hdl_source/ae_luma_sampler.v)。旧`uiisp_beta/ae_set.v`保留历史内容，但不再是本轮活动工程入口。

统计位置在AWB/Gamma之前，完全不读取显示端补亮结果。每16个有效四像素包抽取第0个像素，完整720p帧共14,400样本；亮度为`(R+2G+B)>>4`，范围0～63。正常情况下均值小于16请求增曝，大于24请求减曝，中间保持。

明暗并存时叠加高光约束：亮度≥48的样本至少2%，且亮度≤12的样本至少20%，视为混合场景。此时若亮度≥60的样本至少2%，且全帧均值不低于8，则优先减曝；亮端仍有覆盖时，即使均值偏暗也不反向增曝。该规则用于给高光留余量，全局E仍无法同时覆盖任意强逆光场景。

每次参数组完成后丢弃3个新统计帧，再要求连续2个同方向结果才调整。步长约当前E的1/16，触及128或1991后不反复重写相同参数。短帧、长帧、RAW过渡和过时序号不作为新的调节反馈。

## 请求E与已生效E

`O_ae`是待写入请求；它改变时，传感器不一定已经按该E曝光。融合补亮使用单独的`O_applied_exposure`，只在控制器观察到done先低后高且摄像头配置正常后更新。参数写入、模式切换、冻结或配置失效期间，有效位被屏蔽，最近的已生效E寄存值仍保留。

真实写入仍由[uicfgcs520.v](user_source/hdl_source/uics520_cfg/uicfgcs520.v)等原控制器完成，保留真实FS等待、3812组保持/释放、完整8次寄存器写、NACK有界重试和成功后两帧等待。该确认是ACK与约定生效等待完成，不是寄存器读回证明。

已生效E与有效位通过握手邮箱整体跨域，在HDMI帧界提交。显示端还隔离曝光变化后的过渡帧，避免新状态与DDR中的旧画面混合参与触发统计；它仍不是逐像素精确曝光标签。

## 验证与构建边界

```powershell
python tools/test_fusion_exposure.py --output validation/fusion_exposure_linked/control
python tools/test_fusion_linked_lift.py --output validation/fusion_exposure_linked/lift
python tools/test_ae_luma_sampler.py
python tools/test_ae_highlight_guard.py
```

曝光控制专用验证覆盖65次真实参数请求、请求／生效隔离、done卡高、上下限、固定G12、冻结、忙中切模式、配置失效以及KEY4去抖；摘要见[控制验证](validation/fusion_exposure_linked/control/summary.json)。补亮和集成验证结果以各自最新输出为准。

旧`test_auto_exposure.py`与`test_five_switch_sensor.py`仍描述历史SW5固定档协议，不应拿其旧目标值验收本轮接口。新源码的资源、Slice、DSP和物理时序尚未测得。完整TD构建仍按[构建说明](BUILD_AND_PROGRAM.md)执行A→B→C及更新后的CDC审计；不能沿用旧Bit或旧资源报告作为新功能的实现证明。
