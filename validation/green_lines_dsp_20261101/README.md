# DSP 映射单项修复：编译与烧录档案

2026-11-01 15:56:33（北京时间）已完成 JTAG SRAM 下载。用户随后提供的截图中，原来的密集绿色竖条已消失；见 `user_feedback.json` 和 `board_user_feedback_20261101.jpg`。

唯一生产源码变化：`vib_bbox_grid` 模块声明前添加 `(* dsp_style = "no" *)`。算法、位宽、时序逻辑与 HDMI 未修改；242 个输入文件的前后哈希核对及逐字节差异检查通过。

## Bit

本目录 `Final_Project_bbox_lut_20261101.bit` 与 `../../td_project/camera_to_dsi_display.bit` 内容相同，大小 1,789,539 字节。

SHA256：`A2CA15E1BC1A57199D6171230E50BCB8DF6F2C4F75635CF387B6BB1AB753B4E1`。

## 编译结果

- bbox DSP 6→0，全工程合并前需求 46→40，`No need to merge 9x9 Dsps.`。
- 原图像 DSP 共 31 个，与主图像工程一致；没有本次原有的 5 条物理浮空网或跳过布线警告，`eco open net = 0`。
- Slice 19,163/21,216；LUT6 18,362/21,216；FF 16,778/42,432；ERAM 66/108；DSP 40/40。
- SWNS +0.121 ns，HWNS +0.020 ns，STNS/HTNS 均为 0。
- A→B→C、HDMI 12 处补丁、生产时序和独立 25 组 CDC 检查均通过。
- 六项旧静态检查通过；另外两项旧脚本的失败原因见 `static_checks.json`。这些脚本不能替代实际 TD 展开及构建结论。

## 已验证的烧录命令

从 Final_Project 目录执行；此命令已在本轮运行成功，无需因阅读本文件重复烧录。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\program_final.ps1 -Bit '.\validation\green_lines_dsp_20261101\Final_Project_bbox_lut_20261101.bit' -ExpectedSha256 'A2CA15E1BC1A57199D6171230E50BCB8DF6F2C4F75635CF387B6BB1AB753B4E1' -TdExe 'D:\Anlogic\TD6.2.1\bin\td_commands_prompt.exe' -OutputRoot 'D:\FPGA\codex_zyj\_build\Final_Project\bbox-lut-programming' -Spd 7 -Cable 0
```

注意：发布时已将 `program_final.ps1` 的默认 SHA256 更新为本版，推荐显式传入上面的 SHA256。烧录方式为 JTAG SRAM，掉电后配置会丢失。

## 文件索引

- `build_verification.json`：构建检查、资源、时序与 Bit 身份。
- `program_verification.json`、`programming.json`、`program.log`：实际下载、器件校验、暂存 Bit 哈希核对。
- `reports/`：本次 A/B/C 日志、gate/phy 资源、最终时序、独立 CDC 日志。
- `source_before.json`、`source_after.json`、`source_change.json`：242 个输入文件核对结果。
- `vib_bbox_grid.before.v`、`vib_bbox_grid.after.v`：唯一变更文件的前后副本。
- `static_checks.json`：旧静态脚本的通过项及不适用项。

详细整合说明见[INTEGRATION_NOTES](../../INTEGRATION_NOTES.md)。用户最新截图已不再显示此前的密集绿色竖条，完整振动测频精度未在本次验收。更完整的修复前证据保留在本地工作区 `0 docs/Final_Project绿色竖条排查记录_20261101.md`。

`reports/`、源码前后副本、完整工具日志及 Bit 只在本机保留；远端提交本 README、验证摘要／哈希 JSON 和用户反馈截图。
