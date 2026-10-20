# probe_nets2.tcl -- 宽口径探测：我们这棵树的 HDMI 核内部叫什么

if {[catch {
    set p0 [pwd]
    cd F:/Anlogic/arch
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    cd $p0
    import_db baseline_rtl.db

    foreach pat {*video_valid* *valid_2d* *valid_3d*} {
        puts "===== get_nets -hier $pat ====="
        if {[catch {set ns [get_nets -hier $pat]} e]} { puts "  ERR $e" ; set ns {} }
        puts "  COUNT = [llength $ns]"
        set i 0
        foreach n $ns { if {$i < 20} { puts "    $n" } ; incr i }
    }

    foreach pat {*tmds_encode* *hdmi_tx_controller*} {
        puts "===== get_cells -hier $pat ====="
        if {[catch {set cs [get_cells -hier $pat]} e]} { puts "  ERR $e" ; set cs {} }
        puts "  COUNT = [llength $cs]"
        set i 0
        foreach c $cs { if {$i < 10} { puts "    $c" } ; incr i }
    }

    puts "===== 顶层层次（hdmi 相关）====="
    if {[catch {list_hierarchy -top design_top_wrapper} e2]} { puts "  list_hierarchy ERR $e2" } else {
        foreach line [split $e2 "\n"] {
            if {[string match *hdmi* $line] || [string match *tmds* $line] || [string match *encrypt* $line]} { puts "  $line" }
        }
    }
    puts "PROBE2_DONE"
} err]} { puts "PROBE2_ERROR $err" }
exit
