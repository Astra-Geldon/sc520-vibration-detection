# probe_nets.tcl -- 在 baseline_rtl.db 里找 S_video_valid_2d/3d 的真实层次路径
#   只读、不改动，用于确认 phaseB 要 patch 的对象名。

if {[catch {
    set p0 [pwd]
    cd F:/Anlogic/arch
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    cd $p0
    import_db baseline_rtl.db

    foreach pat {S_video_valid_2d S_video_valid_3d} {
        puts "===== get_nets -hier -regexp {$pat} ====="
        set ns [get_nets -hier -regexp $pat]
        puts "COUNT = [llength $ns]"
        foreach n $ns { puts "  NET: $n" }
    }

    # 看看 mux6_syn 选择器在哪
    puts "===== mux6_syn 相关 cell（前 30 个）====="
    set cs [get_cells -hier -regexp {mux6_syn_[0-9]+}]
    puts "COUNT = [llength $cs]"
    set i 0
    foreach c $cs {
        if {$i < 30} { puts "  CELL: $c" }
        incr i
    }
    puts "PROBE_DONE"
} err]} { puts "PROBE_ERROR $err" }
exit
