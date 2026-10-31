# Prevent an empty/derived default clock view from qualifying as timing closure.
set fd [open patched_final_timing.rpt r]
set prod_report [read $fd]
close $fd
foreach clock {
    sys_clk_50m pll_clk_24m pll_clk_100m MIPI_RX_BYTE_CLK
    HDMI_PIXEL_CLK HDMI_SERIAL_CLK
    u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk
    u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk
} {
    if {[string first $clock $prod_report] < 0} {error "PRODUCTION clock missing: $clock"}
}
if {![regexp {Constraint File[^\n]*camera_to_dsi_display.sdc} $prod_report]} {
    error "PRODUCTION SDC path missing"
}
if {![regexp {STA coverage[ \t]*:[ \t]*([0-9.]+)%} $prod_report unused coverage] || $coverage < 94.0} {
    error "PRODUCTION timing coverage unexpectedly low"
}
foreach metric {SWNS STNS HWNS HTNS} {
    if {![regexp [format {%s:\s*([-+0-9.]+)ns} $metric] $prod_report unused value] || $value < 0.0} {
        error "PRODUCTION timing not closed: $metric"
    }
}
puts "DEMO_PRODUCTION_TIMING_PASS coverage=$coverage"
