# flow_build.tcl -- drive the whole TD flow manually (no launch_runs).
#
# Why not launch_runs: TD writes *_Runs/*/run.bat containing
#     F:/Anlogic/bin/td_commands_prompt_commands_prompt.exe
# (executable name duplicated), so the run never starts and wait_run
# blocks forever.
#
# Step order follows SWUG105_TCL_Command_User_Guide 3.3.2 (single run):
#     import_device
#     open_project
#     elaborate -top
#     read_adc                      <-- must be AFTER elaborate
#     optimize_rtl
#     read_sdc / read_sdc -ip       <-- before optimize_gate
#     optimize_gate
#     legalize_phy_inst
#     place / route / bitgen
#
# import_device needs the cwd to contain the device database, so the
# script chdir's to the TD arch directory and back.  Everything else
# uses paths relative to td_project.
#
# Usage: cd td_project && echo "source flow_build.tcl" | td_commands_prompt.exe
# ASCII only: TD reads this file with the system codepage.

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

#---------------------------------------------------------------------
# device database (must be imported before anything else)
#---------------------------------------------------------------------
step device {
    cd F:/Anlogic/arch
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    cd $::P0
}
puts "BACK TO = [pwd]"

step open      { open_project camera_to_dsi_display.al }

#---------------------------------------------------------------------
# read_design + opt_rtl
#---------------------------------------------------------------------
step elaborate { elaborate -top design_top_wrapper }
step adc       { read_adc ../user_source/constraints_source/pin.adc }
step ip_adc    { read_ip_adc -ip ddr2 -file ../user_source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc }
step opt_rtl   { optimize_rtl }
step rtl_area  { report_area -file img_rtl.area }

#---------------------------------------------------------------------
# opt_gate
#---------------------------------------------------------------------
step sdc       { read_sdc camera_to_dsi_display.sdc }
step ip_sdc1   { read_sdc -ip ddr2           ../user_source/hdl_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc }
step ip_sdc2   { read_sdc -ip w128_d512_fifo ../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.tcl }
step opt_gate  { optimize_gate -packarea camera_to_dsi_display_gate.area }
step legalize  { legalize_phy_inst }
step sdc_again { read_sdc camera_to_dsi_display.sdc }
step gate_area { report_area -file img_gate.area }
step gate_tim  { update_timing }
step gate_sum  { report_timing_summary -file gate.timing }
step gate_stat { report_timing_status  -file gate.ts }

#---------------------------------------------------------------------
# opt_place
#---------------------------------------------------------------------
step place     { place }
step place_tim { update_timing -mode manhattan }
step phy_area  { report_area -io_info -file camera_to_dsi_display_phy.area }
step place_sum { report_timing_summary -file place.timing }

#---------------------------------------------------------------------
# opt_route
#---------------------------------------------------------------------
step route     { route }
step route_ar  { report_area -io_info -file camera_to_dsi_display_phy.area }
step route_tim { update_timing -mode final }
step route_st  { report_timing_status  -file camera_to_dsi_display_phy.ts }
step route_sum { report_timing_summary -file camera_to_dsi_display_pr.timing }

#---------------------------------------------------------------------
# bitgen
#---------------------------------------------------------------------
step bitgen    { bitgen -bit camera_to_dsi_display.bit }

puts ""
puts "########## FLOW DONE ERR=$::ERR ##########"
exit 0
