# 必读：本仓库不含 HDMI 加密核的 valid2→valid3 补丁

> 状态：**【推断】+【待上板验证】**。结论来自代码/网表证据与另一工程的实测对照，
> 尚未在本仓库的构建产物上直接验证。
> 添加日期：2026-10-20。

---

## 1. 一句话

本仓库源代码里**没有** `S_video_valid_2d → S_video_valid_3d` 这处网表补丁。
直接 clone 本仓库、在 TD 里新建工程综合出来的比特流，是**未打补丁**的版本；
在 USB 采集卡（实测用 UGREEN 25854）上大概率是**全黑 90 帧**，而接显示器可能正常。

如果你只是 clone 下来编译、然后接采集卡看不到画面，**先看这一节，不要先去改 AVI / 位序 / PLL 相位**。

---

## 2. 证据

| # | 事实 | 出处 |
|---|---|---|
| E1 | 本仓库有 `.gitignore`，其中 `*.db` 被整体忽略 | `.gitignore` |
| E2 | 补丁是打在**综合/优化后的网表数据库**（`*_rtl.db`）上的，不是打在 RTL 上 | 见第 4 节流程 |
| E3 | 因此仓库里只有 RTL，任何 `*_rtl.db` / `*.bit` 都不在版本库中 | 仓库文件列表：无 `.db`、无 `.bit` |
| E4 | HDMI 核本体是 IEEE-1735 加密的（第 77 行起 `pragma protect begin_protected`），RTL 层面改不了内部计数器 | `user_source/hdl_source/hdmi_1_4b_transmitter_core_wrapper.enc.v:77` |
| E5 | 已知故障现象：未打补丁的同一颗加密核，采集卡 60~90 帧全黑（`min=max=0`）；打补丁后同一块板、同一根线、同一张采集卡立刻出图 | 另一工程（彩条 / SC520 相机例程）实测记录 |

E5 的具体判据（在另一工程上已复现两次）：

```
u_hdmi_tx/u_hdmi_1_4b_transmitter_core_wrapper/u_hdmi_tx_controller_wrapper/u0_hdmi_tmds_encode/
    S_video_valid_2d  →  S_video_valid_3d
补丁前：老网 14 个引脚（valid2_reg.q、valid3_reg.d、12 个 mux6_syn_[2..5].sel）
补丁后：老网 2 个引脚、新网 14 个引脚，12 个 sel 全部对得上
```

本仓库的层次前缀与上面完全一致（`design_top_wrapper.v` 里例化名就是 `u_hdmi_tx`），
所以打补丁的路径不需要改。

---

## 3. 为什么仓库里没记录这件事

`README.md` 的「已知限制」写的是「画面偏暗、需要自动曝光」，说明作者那边**是能看到画面的**。
这与「采集卡全黑」并不矛盾：**同一路 HDMI，显示器能认、采集卡不认**是这类时序/有效窗问题的典型表现。
作者当时用的显示设备是显示器还是采集卡，仓库里没有记录**【待确认】**。

---

## 4. 怎么补（在本仓库上重放）

前提：先按正常流程综合到 `opt_gate`，拿到 `camera_to_dsi_display_rtl.db`；**之后不要再跑 `read_design`**，
否则补丁会被覆盖。

```powershell
# 1) 综合（read_design → opt_rtl → opt_gate），产出 *_rtl.db
cd td_project\camera_to_dsi_display_Runs\syn_1
& 'D:\Anlogic\TD6.2.1\Bin\td_commands_prompt.exe' 'D:/Anlogic/TD6.2.1/doc/scripts/DefaultFlow.tcl'

# 2) 在 rtl.db 上把 12 个 mux 的 sel 从 S_video_valid_2d 改到 S_video_valid_3d，再覆盖回 rtl.db
#    同时把 settings.cfg 的 start_step 改成 opt_gate
# 3) 只重跑 gate 阶段
& 'D:\Anlogic\TD6.2.1\Bin\td_commands_prompt.exe' 'D:/Anlogic/TD6.2.1/doc/scripts/DefaultFlow.tcl'

# 4) place / route / bitgen
cd ..\phy_1
& 'D:\Anlogic\TD6.2.1\Bin\td_commands_prompt.exe' 'D:/Anlogic/TD6.2.1/doc/scripts/DefaultFlow.tcl'
```

补丁脚本判据必须打印：

```
VERIFIED_COUNTER_SELECTORS = 12
```

---

## 5. 验收判据（按顺序，缺一不可）

1. STA：报告里同时出现 `HDMI_PIXEL_CLK`、`HDMI_SERIAL_CLK`，无 `SYN-8411`，SWNS/HWNS 为正；
2. 烧录后采集卡抓 **≥60 帧**，不能只看单帧、也不能只看烧录进程退出码；
3. 判「画面活的」看帧间差：第 15 帧 vs 第 90 帧，灰度差 >8 的像素占比 >5%；
4. 对照组：另烧一个已知能出图的彩条 bit。彩条能出、本设计全黑 → 回到本节；
   彩条也全黑 → 先查线/卡/供电，不要改 HDL。

> 采集卡**没有输入时也会给 90 帧全 0**，所以只看 `mean==0` 分不清「无信号 / 合法全黑 / 核解不出来」。

---

## 6. 与主基准的关系

本仓库其余与 `HX1P35A_SC520CS_基准.md` 的差异（PLL 实际 75.000/375.000 MHz、按键 `N2/J14`、
复位 `R10`、VTC `V_SyncStart=725/730`、`I_key_in=1'b0`）在该基准文件里有逐条记录，
不属于本文件范围，这里只补充「补丁不在仓库」这一条。
