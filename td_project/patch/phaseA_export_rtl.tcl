# phaseA_export_rtl.tcl -- 阶段 A：正常综合到 optimize_rtl，导出逻辑数据库
#
# 背景（见 docs/队友黑屏分析-逐条核查.md）：HDMI 发射核是 IEEE-1735 加密核，
# 内部「计数器 sel 用 valid_2d、像素数据在第 3 拍」的错拍无法改源码。
# 队友（2026-10-06 round35）验证过的做法是：综合到 optimize_rtl 后，
# 在 TD 的逻辑数据库里把这 12 个 mux 的 sel 改接到 valid_3d，再继续
# optimize_gate/place/route。本脚本就是前半段。
#
# 注意：不能 write_verilog 之后重新分析 —— 受保护实例会变成 encrypted inst。
#       必须用 export_db / import_db。
#
# 用法：cd td_project && echo 'source patch/phaseA_export_rtl.tcl' | td_commands_prompt.exe

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

# device db 需要当前目录能找到 ph1_35p.db
step device { sc520_import_device }

step open      { open_project camera_to_dsi_display.al }
step elaborate { elaborate -top design_top_wrapper }
step adc       { read_adc ../user_source/constraints_source/pin.adc }
step ip_adc    { read_ip_adc -ip ddr2 -file ../user_source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc }
step opt_rtl   { optimize_rtl }

# 约束要在库里，否则后面 place/route 的时序报告没有意义
step sdc       { read_sdc camera_to_dsi_display.sdc }
step ip_sdc1   { read_sdc -ip ddr2           ../user_source/hdl_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc }
step ip_sdc2   { read_sdc -ip w128_d512_fifo ../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.tcl }

step export_db { export_db baseline_rtl.db }

puts ""
puts "########## PHASE_A_DONE ERR=$::ERR ##########"
exit 0
