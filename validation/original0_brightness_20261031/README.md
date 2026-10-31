# 原图0亮度链路审计证据

被审计源码：`cc91060`，不是新硬件候选。用户第四图明确原图0/C0/P0/W0仍过亮，因此排除C3作为该反馈原因；不使用原图3截图代替原图0，不从JPEG推断RAW或寄存器值。本轮不采集摄像头、不修改RTL、不运行TD或烧录。

- `broad_history.json`及同名表格：24个图像链快照＋2个MCU正常生产固件快照，覆盖10月18～31日，包含昨天/前天及今天各轮候选。
- `green_path_followup.json/.md`：独立复核19个版本的RAW换算、插值、RGB打包/DDR与绿色通道；未发现近期新增整体放大，当前Gamma256项与10月18日一致。
- `fixed_gain_followup.md`、`earlier_sensor_history.json`：早期增益144于10月24日改160的提交证据、初始化后覆盖到高增益的链路，以及24/16/8/4倍单变量验证建议；标称值不等于本轮硬件实测。
- `rtl_reproduction.json`：生产菜单与tone的44次KEY3切换、256点中性灰曲线摘要、4096组C0/P0/W0旁路验证；包含生产源码SHA和顶层/实际AWB清单断言。菜单可独立保留C3只作次要发现，不作为当前C0过曝的解释。
- `history_active_sources.json`：5个历史版本、7个实际使用文件的Git blob SHA256；这些文件一致。Gamma的256输入对照表明0～239不变、240～254降低、255不变。
- `sensor_summary.json`：曝光0=1991、gain160请求映射、官方手册与传感器实际状态确认的边界。所有数值均为代码请求或手册定义，本轮未读回板卡。
- `latest_frozen_source_check.json`：核对当前生产文件与最近已烧录候选的冻结源码清单，属于本地来源核查，不代表本轮重新验证板上镜像。

完整说明见仓库根目录`ORIGINAL0_BRIGHTNESS_AUDIT_20261031.md`。临时复现脚本`reproduce.py`、`archive_evidence.py`、测试平台和日志统一保存在：

`D:/FPGA/codex/_build/20261029project/original0-brightness-audit-20261031/`

这些验证只证明代码行为和所查历史变化，不把“同参数真实原图0近期变亮”的全部原因标记为已解决。
