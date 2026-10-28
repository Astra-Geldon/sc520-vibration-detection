# phaseC_build_from_patched.tcl -- 阶段 C：从 patched_rtl.db 继续 gate/place/route/bitgen
#
# 关键：必须从 patched_rtl.db 走（不能重新分析 Verilog —— 受保护实例会变成
#       encrypted inst，patch 就丢了；这一点队友在第 34 轮踩过）。
#
# 用法：cd td_project && echo 'source patch/phaseC_build_from_patched.tcl' | td_commands_prompt.exe

source [file join [file dirname [info script]] td_device.tcl]

set ::ERR 0
proc step {name body} {
    puts ""
    puts "########## STEP: $name ##########"
    if {[catch {uplevel 1 $body} e]} {
        puts "########## FAIL: $name : $e ##########"
        set ::ERR 1
        return -code error $e
    }
    puts "########## OK: $name ##########"
}

set ::P0 [pwd]
puts "START DIR = $::P0"

step device  { sc520_import_device }
step import  { import_db patched_rtl.db }

# 确认补丁还在（防呆：import_db 后重新数 pin）
step check   {
    set base u_hdmi_tx/u_hdmi_1_4b_transmitter_core_wrapper/u_hdmi_tx_controller_wrapper
    set o [get_pins -verbose -of [get_nets $base/u0_hdmi_tmds_encode/S_video_valid_2d]]
    set n [get_pins -verbose -of [get_nets $base/u0_hdmi_tmds_encode/S_video_valid_3d]]
    puts "CHECK valid_2d=[llength $o] valid_3d=[llength $n]"
    if {[llength $o] != 2 || [llength $n] != 14} { error "patch not preserved in DB" }
}

step opt_gate { optimize_gate -packarea camera_to_dsi_display_gate.area }
step legalize { legalize_phy_inst }
step place    { place }
step route    { route }
step timing   { update_timing -mode final }
step tstatus  { report_timing_status  -file camera_to_dsi_display_phy.ts }
step tsum     { report_timing_summary -file patched_final_timing.rpt }
step area     { report_area -io_info  -file camera_to_dsi_display_phy.area }
step bitgen   { bitgen -bit camera_to_dsi_display.bit }

puts ""
puts "########## PHASE_C_DONE ERR=$::ERR ##########"
exit 0
