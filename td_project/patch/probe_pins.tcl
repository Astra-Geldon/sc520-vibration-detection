# probe_pins.tcl -- 列出 S_video_valid_2d/3d 两个网上的全部 pin，找那 12 个计数器选择器

if {[catch {
    set p0 [pwd]
    cd F:/Anlogic/arch
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    cd $p0
    import_db baseline_rtl.db

    set base u_hdmi_tx/u_hdmi_1_4b_transmitter_core_wrapper/u_hdmi_tx_controller_wrapper
    set n2d $base/u0_hdmi_tmds_encode/S_video_valid_2d
    set n3d $base/u0_hdmi_tmds_encode/S_video_valid_3d

    foreach n [list $n2d $n3d] {
        puts "===== PINS ON $n ====="
        if {[catch {set ps [get_pins -verbose -of [get_nets $n]]} e]} { puts "  ERR $e" ; continue }
        puts "  COUNT = [llength $ps]"
        set i 0
        foreach p $ps {
            puts "    $p"
            incr i
            if {$i >= 40} { puts "    ... (truncated)"; break }
        }
    }

    # 找计数器相关的 cell（队友那边叫 S_cnt_t_1_b*、mux6_syn_*）
    foreach pat {*S_cnt_t_1*} {
        puts "===== CELLS $pat ====="
        if {[catch {set cs [get_cells -hier $pat]} e]} { puts "  ERR $e" ; continue }
        puts "  COUNT = [llength $cs]"
        set i 0
        foreach c $cs { if {$i < 40} { puts "    $c" } ; incr i }
    }
    puts "PROBE3_DONE"
} err]} { puts "PROBE3_ERROR $err" }
exit
