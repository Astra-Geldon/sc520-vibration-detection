# 资源压缩审查

本文记录2026-11-03的历史资源清理。2026-11-04已完成行缓存ERAM迁移、ISP深度和UART诊断裁剪对照，当前低LUT结果及各实验取舍见[资源压缩技术研究与实测](RESOURCE_COMPRESSION_RESEARCH.md)。下方“当前基线”数字属于历史构建，不能与2026-11-04实验Bit混用。

## 当前基线

最新物理报告为`td_project/camera_to_dsi_display_phy.area`：LUT6使用17780/21216（83.80%），Slice使用18576/21216（87.56%），REG使用17886/42432（42.15%），ERAM20K使用66/108（61.11%），DSP使用40/40（100%）。相对原物理基线减少170个LUT6、299个Slice和12个REG；ERAM、DSP、PLL、MCU不变。最新时序为STA覆盖率97.07%、SWNS+0.103ns、HWNS+0.020ns，余量仍很小，任何需要增加流水级或改变RAM读时序的优化都必须重新做逐拍验证和TD布局布线。

物理层级中较大的可控模块如下：

|实例|逻辑LUT|进位资源|寄存器|ERAM|DSP|
|---|---:|---:|---:|---:|---:|
|`u_uart_log_debug`|214|80|673|0|0|
|`u_vib_gz_peak`|1805|196|2241|2|5|
|`u_vib_bbox_grid`|1025|175|707|0|0|
|`u_vib_lk_grid_multi`|1247|88|1797|8|2|
|`u_isp_top`|1543|653|2440|22|23|
|`u_fusion_lift_control`|587|104|550|0|0|

## 已完成的安全清理

`fusion_lift_control`原来保留了一个没有任何状态转移能够进入的`S_REFERENCE_MUL→S_EXPOSURE_CAP→S_LUMA_SEARCH`串行计算链。该链使用的乘法累加器、曝光上限搜索寄存器、包络统计和`target_*`寄存器最终都没有读点。现在删除这段不可达状态和无读点数据，保留顶层端口和当前`IDLE/REFERENCE_DIV`行为不变。

已通过：

```powershell
python tools/test_fusion_tone_control.py
python tools/test_fusion_linked_lift.py --case all
python tools/check_fusion_linked_integration.py
python tools/test_ae_luma_sampler.py
```

最新TD报告已确认清理后的物理变化：LUT6减少170、Slice减少299、REG减少12。层级报告显示`u_fusion_lift_control`由640 LUT/598 REG降为587 LUT/550 REG；其他层级会因重新布局和打包出现小幅波动，不能用层级差值直接等同源码删除量。

`ae_luma_sampler`也删除了只写不读的亮度总和、暗部/余量计数器及其无用常量；保留参数名以兼容既有例化，实际分类仍只使用近饱和计数和8个亮度桶。

构建验收同时修正了`u_demo_mipi_status`的CDC集合口径：源侧payload仍为5位，目标侧只有实际有读点的3位，两个检查脚本均按真实网表收集；最新A/B/C和40组寄存器/物理CDC审计全部通过。

## 历史报告中的后续方向

1.串口诊断已完成独立编译期裁剪对照，实测结果见新报告；当前生产源码仍保留UART，因为它用于板上振动链路自检和故障定位。

2.分布式RAM行缓存已完成显式ERAM迁移，结果和逐拍验证记录见新报告；当前低LUT构建保留该迁移。

3.`vib_video_tap`的512深度拍FIFO不能按表面占用缩小。输入是一整行240拍的突发流，FIFO用于吸收输入和灰度降采样之间的速率差；缩小深度会重新出现丢拍和行错位。它与`vib_prev_frame_ddr`中的FIFO处于不同数据阶段，不能直接合并成一个ping-pongbuffer。

4.`vib_lk_grid_multi`的累加器有少量位宽收缩空间，但收益主要是少量寄存器，且需要重新证明有符号累加、边界和求解器输入不会溢出。在当前时序余量下，收益不足以抵消风险，暂不改动。

5.DSP已经满载，不能再依靠工具自动合并主图像乘法器换资源。振动bbox的`dsp_style="no"`已经用于避免DSP合并和物理浮空网；后续计算应优先采用移位加法、串行复用或RAM换LUT，并逐项验证吞吐和时序。

6.当前已确认的低风险复用边界：`vib_gz_multi`已经把48块×27频点串行复用为单乘法器，`vib_gz_peak`的诊断扫描与计算状态也已在模块内复用；不能跨模块再合并而不改变触发窗口和峰值保持。`vib_lk_grid_multi`每拍同时需要当前高斯行和上一帧It行，`vib_prev_frame_ddr`又承担DDR突发帧副本，二者不能直接做pingpong共用。Fusion的RGB三通道同拍输出，Tone LUT/混合改单通道时分复用会增加3拍或提高时钟，不能作为当前安全压缩。

7.ISP的2048深RAM压缩实验也已完成：ERAM减少16块但LUT/Slice增加，已回退到当前低LUT源码；具体数字见新报告。

## 结论

当前最稳妥的生产口径是保留低LUT实现；若比赛发布版不需要串口，再单独生成关闭UART诊断的Bit。ISP深度版只适合ERAM优先场景，不要与UART、振动算法、DDR仲裁和视频流水同时修改。
