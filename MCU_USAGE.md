# MCU 当前状态与扩展方法

适用提交d1fe233初赛final。MCU硬核已例化，但没有运行项目固件，没有接管曝光、拨码、图像处理、微振动、DDR或HDMI。

## 当前连接

活动顶层：[design_top_wrapper.v](user_source/hdl_source/design_top_wrapper.v) 的 `u_mcu_passive`。

| 接口 | 当前连接与状态 |
|---|---|
| 核心/定时器时钟 | `S_100m_clk`，100MHz |
| 复位 | `~S_pll_lock` |
| APB时钟 | 板载50MHz；没有接入APB从设备 |
| AHB | 输出未接外设；读数据0、ready1、response0 |
| APB返回 | prdata0、pready1、pslverr0 |
| GPIO0/1输入 | 旧I_button[0/1]；输出与方向不控制图像链 |
| GPIO2～7输入 | 常量0 |
| MCU UART | RX空闲高，TX未接板级输出；当前板级振动诊断 UART 来自 FPGA 逻辑 |
| I²C | 输入空闲高，输出悬空；摄像头由FPGA uicfgcs520独占 |
| QSPI | 未使用 |
| MCU固件 | 本发布未装载ELF/BIN；bit中没有本项目应用程序 |

`MCU.v`实际实例参数覆盖为 `MCU_JTAG_SEL="0"`、复位向量0x20E00000、AHB_FREQ="50.0"、DPLL_POST_DIV=5；不要把内层生成文件的参数默认值误认为实际生效值。当前顶层fabric JTAG输入固定0；PAD JTAG由硬核参数选择，不能仅凭这些tie-off就断言PAD调试可用或不可用。本最终版未做新的MCU调试装载验收。

## 文件入口

- [MCU.v](user_source/ip_source/MCU/MCU.v)：当前实际参数与封装入口。
- [MCU_f9f874759a41.v](user_source/ip_source/MCU/MCU_f9f874759a41.v)：TD生成硬宏包装。
- `user_source/ip_source/MCU/Design.xml`、`DesignConfiguration.xml`：IP定义/配置。
- [ps_wrapper.v](user_source/hdl_source/ps_wrapper.v)：保留的通用包装，不是当前顶层活动实例。

当前正常视频和微振动链路不需要 FD、OpenOCD 或 ELF，直接下载匹配的 Bit 即可。当前Bit的位置、SHA256和烧录命令见[编译烧录说明](BUILD_AND_PROGRAM.md)。

## 真正使用MCU的最小路线

历史独立MCU测试工程已验证GPIO回环、TCM固件装载和AHB窗口0x80000000读写；APB地址窗口当时没有确认，不能照抄一个APB地址当已跑通方案。以下过程应在新分支进行，不更改当前最终bit：

1. 先建立很小的固件、TCM链接脚本和串口/调试输出，验证MCU确实执行；bit配置与ELF下载分别确认。
2. 用GPIO回环检查连接和极性，再接AHB-Lite最小寄存器：只读版本号、可读写scratch。处理地址相与数据相，返回hrdata/hready/hresp。
3. 增加一个模式请求及提交/忙状态，将配置作为低速控制，像素运算留在现有FPGA流水。多位跨域数据采用保持数据＋请求/应答，不能逐位双触发器冒充原子传输。
4. 在帧/消隐边界提交图像控制。必要时返回已应用状态，避免把总线写完成当画面已生效。
5. 若迁移传感器控制，先明确I²C唯一所有者、默认态、三态和ACK交接，再移除被替代驱动。不要把两套主设备直接并到SDA/SCL。
6. 每次确认MCU接管一项后，再删除相应FPGA控制块，用资源报告证明净收益；不同时保留两套生产控制器及一整套常驻诊断。

以上AHB经验来自历史测试，最终版目前没有这个外设或可运行固件，不能直接运行地址访问示例。构建、时钟、JTAG和固件环境变化都需重新验证。

## 编译、烧录与资源

整合工程构建必须保留 HDMI 数据库补丁及生产时钟/CDC 检查，步骤见 [编译说明](BUILD_AND_PROGRAM.md)。当前占用 1 个 MCU 硬核、40 个 DSP，其中原图像 31 个 DSP 保持独立；bbox 已改用 LUT/Slice。硬核占用不能与 Slice 相加，也不能据此声称计算已经搬到 MCU。

当前 Bit SHA256 为 `5f8c6b9bc429b6badeebc0cb93c41bbce051cf8276bb31e3c3c2fa7e1956aaa0`；本轮已完成A/B/C和40组物理CDC审计。未装载MCU固件，亦未完成完整微振动频率识别验收；板上下载需按[编译烧录说明](BUILD_AND_PROGRAM.md)单独确认。

实际开发经验与常见错误见 [MCU_LESSONS](MCU_LESSONS.md)，当前算法见 [CURRENT_ALGORITHMS](CURRENT_ALGORITHMS.md)。
