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

# Five-switch mailboxes hold payload until the receiver commits and returns ACK.
# Source -> first synchronizer and held payload -> receiver are intentional CDC;
# constrain their physical flight to 8ns (< the fastest 9.660ns byte period).
# First -> second synchronizer stays timed and is additionally limited to 4ns.
# Exact register collections are checked so an optimization cannot silently
# remove a synchronization stage or leave an exception matching no register.
foreach {demo_inst demo_width} {
    u_demo_mipi_controls 5
    u_demo_hdmi_controls 5
    u_demo_sensor_controls 1
    u_demo_mipi_status 5
    u_demo_sensor_status 3
} {
    set demo_payload [get_regs [format {%s/payload[*]} $demo_inst]]
    set demo_receive [get_regs [format {%s/O_dst_data[*]} $demo_inst]]
    if {[llength $demo_payload] != $demo_width || [llength $demo_receive] != $demo_width} {
        error "Five-switch mailbox data width mismatch: $demo_inst"
    }
    set_max_delay -from $demo_payload -to $demo_receive -datapath_only 8.0
    foreach {demo_from demo_to} {request request_s1 acknowledge acknowledge_s1} {
        set demo_src [get_regs $demo_inst/$demo_from]
        set demo_dst [get_regs $demo_inst/$demo_to]
        if {[llength $demo_src] != 1 || [llength $demo_dst] != 1} {
            error "Five-switch mailbox CDC register missing: $demo_inst/$demo_to"
        }
        set_max_delay -from $demo_src -to $demo_dst -datapath_only 8.0
    }
    foreach demo_sync {request acknowledge} {
        set demo_s1 [get_regs ${demo_inst}/${demo_sync}_s1]
        set demo_s2 [get_regs ${demo_inst}/${demo_sync}_s2]
        if {[llength $demo_s1] != 1 || [llength $demo_s2] != 1} {
            error "Five-switch mailbox synchronizer missing: $demo_inst/$demo_sync"
        }
        foreach demo_reg [concat $demo_s1 $demo_s2] {
            if {![get_property ASYNC_REG $demo_reg]} {
                error "Five-switch mailbox ASYNC_REG missing: $demo_reg"
            }
        }
        set_max_delay -from $demo_s1 -to $demo_s2 4.0
    }
}
