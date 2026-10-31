# 文档索引与版本适用范围

2026-11-01最终版。当前生产源码85c7f7d、快照5abdac4，分支demo-five-switch-20261101。以下当前文档以有效顶层配置为准；本次只更新说明与归档，没有修改RTL。

## 当前入口

| 文档 | 用途 |
|---|---|
| [README](README.md) | 版本、操作、bit路径、资源总览 |
| [TEAM_GUIDE](TEAM_GUIDE.md) | 队友快速上手 |
| [FIVE_SWITCH_DEMO](FIVE_SWITCH_DEMO_20261101.md) | 五拨码映射和ON/OFF/WAIT语义 |
| [CURRENT_ALGORITHMS](CURRENT_ALGORITHMS.md) | 实际链路、表、公式和未启用功能 |
| [RESOURCE_USAGE](RESOURCE_USAGE.md) | 全部资源、基线比较、时序和证据范围 |
| [BUILD_AND_PROGRAM](BUILD_AND_PROGRAM.md) | 已归档bit自行烧录、修改后完整重建 |
| [MCU_USAGE](MCU_USAGE.md) | 被动硬核现状、接口和后续最小扩展路线 |
| [MCU_LESSONS](MCU_LESSONS.md) | MCU/FPGA协作与调试经验 |

本次构建/验证摘要在 [validation/five_switch_demo_20261101](validation/five_switch_demo_20261101/final_release.json)。原始JSON是当时生成的不可变证据，旧pending字段表示记录生成时状态；最终交付状态看final_release.json。原始完整日志、数据库、bit统一存本机_build；云端的本机绝对路径不是下载地址。

## 历史实验与旧验证记录

下列文档保留原结论和数据，全部已有历史/取消标记。相对链接继续保留；不要照着旧文档使用KEY3/KEY4候选菜单、六拨码焊线、旧bit或旧资源预算。没有将未采用的实验改写成当前功能。

- [A-original-reuse + Logo 发布说明](A_RELEASE_LOGO_20261030.md)
- [Exposure chain findings](AE_CHAIN_FINDINGS_20261030.md)
- [移动后持续误框：AGC历史参考修复（2026-10-28）](AGC_FRAME_FIX_20261028.md)
- [几乎成功版：固定E900 / G12 / N1](ALMOST_SUCCESS_20261101.md)
- [2026-10-28 已上板振动识别备份](BOARD_BASELINE_20261028.md)
- [C3亮度保持与色度降噪试验](C3_CHROMA_DENOISE_20261031.md)
- [00020007：紧凑候选诊断](CANDIDATE_DIAG_20261028.md)
- [四处分散参考的共同运动抑制（2026-10-28）](COMMON_MOTION_20261028.md)
- [2026-10-28当前上板备份：RVER00020006](CURRENT_BASELINE_R00020006_20261028.md)
- [2026-10-28当前上板备份：RVER00020007](CURRENT_BASELINE_R00020007_20261028.md)
- [框内编号、频率与精简串口日志（2026-10-28）](DISPLAY_UART_UPDATE_20261028.md)
- [SC520 换频确认与地址扩容](FREQ_SWITCH_ADDRESS_20261029.md)
- [SC520 第一阶段扩频：2.0～12.0Hz](FREQUENCY_EXTENSION_12HZ_20261028.md)
- [RVER 0002000A：扩展到 15 Hz](FREQUENCY_EXTENSION_15HZ_20261029.md)
- [高光停止提亮，中暗部分档补偿](G12_HIGHLIGHT_GUARD_20261101.md)
- [保留G12/L1高光和亮度，让非高光更自然](G12_NATURAL_NONHIGHLIGHT_20261031.md)
- [8倍增益基底：中暗部提亮与高光微调](GAIN8_SHADOW_LIFT_20261031.md)
- [Gamma高光尾段单项候选](GAMMA_TAIL_CANDIDATE_20261031.md)
- [强弱峰分级确认（2026-10-28）](GRADED_CONFIRM_20261028.md)
- [原图3强补偿后的质感差异分析](H1_IMAGE_QUALITY_ANALYSIS_20261031.md)
- [H1 高光保护与中间调补偿候选](H1_LOCAL_TONE_20261030.md)
- [原图3更强非高光补偿候选](H1_STRONG_COMPENSATION_20261031.md)
- [裁剪前共同RGB高光压缩候选](HIGHLIGHT_COMMON_SHOULDER_20261031.md)
- [保留当前观感的高光余量研究](HIGHLIGHT_HEADROOM_REVIEW_20261031.md)
- [P档高光偏品红：原因与修正方向](HIGHLIGHT_PINK_REVIEW_20261031.md)
- [视频高光分区验证版](HIGHLIGHT_REGION_20261030.md)
- [近白高光颜色保护候选](HIGHLIGHT_WHITE_PROTECTION_20261031.md)
- [找回“高光改善、人脸偏暗”的历史版本](HISTORICAL_DARK_FACE_REFERENCE_20261031.md)
- [五拨码画质算法演示](history/FIVE_SWITCH_BUILD_NOTES_20261101.md)
- [SC520 MIPI → HDMI 振动频率检测系统](history/README_BEFORE_FINAL_20261101.md)
- [阶段 0：A 版 + Logo 图像基线](IMAGE_BASELINE_20261030.md)
- [图像增强分阶段优化计划](IMAGE_ENHANCEMENT_PLAN_20261030.md)
- [C3质感问题复核与修正路线](IMAGE_QUALITY_REASSESSMENT_20261031.md)
- [图像质量问题在线研究与方案选择（2026-10-31）](IMAGE_QUALITY_RESEARCH_20261031.md)
- [下一阶段思路：先分清真目标与误检，保留识别速度](NEXT_STEPS_20261028.md)
- [原图0过亮：旧A版／当前版bit归档与上板对照](ORIGINAL0_BOARD_AB_COMPARISON_20261031.md)
- [原图0过亮：跨版本代码核查与下一步方案](ORIGINAL0_BRIGHTNESS_AUDIT_20261031.md)
- [C3前置降噪复核、修正与真实采样安排](PRE_C3_RESEARCH_FOLLOWUP_20261031.md)
- [900曝光静态混合场景采集与离线降噪对照](REAL900_STATIC_RESEARCH_20261031.md)
- [S0 空间阴影校正旁路对照](S0_SHADING_BYPASS_20261031.md)
- [固定曝光900：前端增益四档对照](SENSOR_GAIN_COMPARE_20261031.md)
- [六个板载拨码用于算法演示：接入核查](SIX_SWITCH_DEMO_WIRING_20261101.md)
- [阶段 1：多档曝光候选（2026-10-30）](STAGE1_EXPOSURE_20261030.md)
- [SC520 振动链接入第一步（2026-10-28）](STAGE1_VIBRATION_INTEGRATION.md)
- [上电曝光/增益修复：用户确认默认画面恢复](STARTUP_SENSOR_FIX_20261101.md)
- [上板日志与源码记录](validation/20261028/README.md)
- [几乎成功版证据](validation/almost_success_20261101/README.md)
- [C3保亮色度降噪：本地编译证据](validation/c3_denoise_20261031/README.md)
- [保护亮端的N1/N2候选证据](validation/g12_highlight_guard_20261101/README.md)
- [P高光偏品红：修复方向的整数域审查](validation/highlight_common_shoulder_20261031/pink_repair_audit.md)
- [裁剪前高光压缩：验证与编译记录](validation/highlight_common_shoulder_20261031/README.md)
- [近白高光颜色保护：验证与交付记录](validation/highlight_white_protection_20261031/README.md)
- [历史“高光改善、人脸偏暗”版本独立核对](validation/historical_dark_face_20261031/identification_review.md)
- [下一步曝光／增益方案只读核查](validation/historical_dark_face_20261031/next_solution_sensor_review.md)
- [broad_history_table](validation/original0_brightness_20261031/broad_history_table.md)
- [曝光0/C0/P0/W0仍过亮：固定曝光与增益追查补充](validation/original0_brightness_20261031/fixed_gain_followup.md)
- [原图0/C0/P0/W0：绿色通道与更早Git历史审计](validation/original0_brightness_20261031/green_path_followup.md)
- [原图0亮度链路审计证据](validation/original0_brightness_20261031/README.md)
- [本轮用户上板日志](validation/r00020006_20261028/README.md)
- [00020007板测记录](validation/r00020007_20261028/README.md)
- [RVER 0002000A 板测记录](validation/r0002000a_20261029/README.md)
- [振动识别算法移植规划](VIBRATION_PORT_PLAN.md)
- [2026-10-28 振动检测修复：恢复旧工程原始频谱判据](VIBRATION_RECOVERY_20261028.md)
- [小字号与弱峰门限单项调整（2026-10-28）](WEAK_PEAK_STEP_20261028.md)
- [不增加DSP的图像质感研究：离线筛选与缓存复核](ZERO_DSP_IMAGE_QUALITY_STUDY_20261031.md)
