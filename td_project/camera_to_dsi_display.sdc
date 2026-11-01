create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 2.415 -waveform {0.000 1.208} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]

# 2026-10-24：HDMI 时钟改回主 PLL 的 clk4/clk5（75.000 / 375.000 MHz），
# rename 必须跟着改路径 —— 否则这两个时钟没有被正确定义/分组，
# 时序会假性恶化（上一次实测 SWNS -4.803ns 就是这么来的）。
rename_clock -name {HDMI_PIXEL_CLK}  [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]

# 复位是纯异步复位，不参与时序（与队友 timing.sdc 一致）
set_false_path -from [get_ports {I_rst_n}]

# Mechanical switch inputs are asynchronous and feed only the first stage of
# u_demo_switches; subsequent synchronizer/mailbox paths keep their constraints.
set_false_path -from [get_ports {I_sw[*]}]


set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]

# Held payload and toggle handshakes: maximum physical flight 8ns.
# Keep these commands static: TD read_sdc stores Tcl loops without evaluating them.
# Synchronizer stage1 -> stage2 remains timed, with an additional 4ns bound.
set_max_delay -from [get_regs {u_demo_mipi_controls/payload[*]}] -to [get_regs {u_demo_mipi_controls/O_dst_data[*]}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_mipi_controls/request}] -to [get_regs {u_demo_mipi_controls/request_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_mipi_controls/acknowledge}] -to [get_regs {u_demo_mipi_controls/acknowledge_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_mipi_controls/request_s1}] -to [get_regs {u_demo_mipi_controls/request_s2}] 4.0
set_max_delay -from [get_regs {u_demo_mipi_controls/acknowledge_s1}] -to [get_regs {u_demo_mipi_controls/acknowledge_s2}] 4.0
set_max_delay -from [get_regs {u_demo_hdmi_controls/payload[*]}] -to [get_regs {u_demo_hdmi_controls/O_dst_data[*]}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_hdmi_controls/request}] -to [get_regs {u_demo_hdmi_controls/request_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_hdmi_controls/acknowledge}] -to [get_regs {u_demo_hdmi_controls/acknowledge_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_hdmi_controls/request_s1}] -to [get_regs {u_demo_hdmi_controls/request_s2}] 4.0
set_max_delay -from [get_regs {u_demo_hdmi_controls/acknowledge_s1}] -to [get_regs {u_demo_hdmi_controls/acknowledge_s2}] 4.0
set_max_delay -from [get_regs {u_demo_sensor_controls/payload[*]}] -to [get_regs {u_demo_sensor_controls/O_dst_data[*]}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_sensor_controls/request}] -to [get_regs {u_demo_sensor_controls/request_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_sensor_controls/acknowledge}] -to [get_regs {u_demo_sensor_controls/acknowledge_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_sensor_controls/request_s1}] -to [get_regs {u_demo_sensor_controls/request_s2}] 4.0
set_max_delay -from [get_regs {u_demo_sensor_controls/acknowledge_s1}] -to [get_regs {u_demo_sensor_controls/acknowledge_s2}] 4.0
set_max_delay -from [get_regs {u_demo_mipi_status/payload[*]}] -to [get_regs {u_demo_mipi_status/O_dst_data[*]}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_mipi_status/request}] -to [get_regs {u_demo_mipi_status/request_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_mipi_status/acknowledge}] -to [get_regs {u_demo_mipi_status/acknowledge_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_mipi_status/request_s1}] -to [get_regs {u_demo_mipi_status/request_s2}] 4.0
set_max_delay -from [get_regs {u_demo_mipi_status/acknowledge_s1}] -to [get_regs {u_demo_mipi_status/acknowledge_s2}] 4.0
set_max_delay -from [get_regs {u_demo_sensor_status/payload[*]}] -to [get_regs {u_demo_sensor_status/O_dst_data[*]}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_sensor_status/request}] -to [get_regs {u_demo_sensor_status/request_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_sensor_status/acknowledge}] -to [get_regs {u_demo_sensor_status/acknowledge_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_demo_sensor_status/request_s1}] -to [get_regs {u_demo_sensor_status/request_s2}] 4.0
set_max_delay -from [get_regs {u_demo_sensor_status/acknowledge_s1}] -to [get_regs {u_demo_sensor_status/acknowledge_s2}] 4.0

# Passive frame-latency observer: the result mailbox holds its 17-bit payload
# until acknowledgment; the OSD freezes it in blanking. Events use toggles.
set_max_delay -from [get_regs {u_video_latency/u_result_cdc/payload[*]}] -to [get_regs {u_video_latency/u_result_cdc/O_dst_data[*]}] -datapath_only 8.0
set_max_delay -from [get_regs {u_video_latency/u_result_cdc/request}] -to [get_regs {u_video_latency/u_result_cdc/request_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_video_latency/u_result_cdc/acknowledge}] -to [get_regs {u_video_latency/u_result_cdc/acknowledge_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_video_latency/u_result_cdc/request_s1}] -to [get_regs {u_video_latency/u_result_cdc/request_s2}] 4.0
set_max_delay -from [get_regs {u_video_latency/u_result_cdc/acknowledge_s1}] -to [get_regs {u_video_latency/u_result_cdc/acknowledge_s2}] 4.0
set_max_delay -from [get_regs {S_cam_frame_toggle}] -to [get_regs {u_video_latency/camera_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_video_latency/camera_s1}] -to [get_regs {u_video_latency/camera_s2}] 4.0
set_max_delay -from [get_regs {u_video_latency/output_toggle}] -to [get_regs {u_video_latency/output_s1}] -datapath_only 8.0
set_max_delay -from [get_regs {u_video_latency/output_s1}] -to [get_regs {u_video_latency/output_s2}] 4.0
