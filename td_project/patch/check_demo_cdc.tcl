# Local physical audit of the five production control mailboxes. No probe RTL.
set demo_cdc_paths 0
foreach {inst width} {
    u_demo_mipi_controls 5
    u_demo_hdmi_controls 5
    u_demo_sensor_controls 1
    u_demo_mipi_status 5
    u_demo_sensor_status 3
} {
    foreach {from to limit expected} [list \
        {payload[*]} {O_dst_data[*]} 8.0 $width \
        request request_s1 8.0 1 \
        acknowledge acknowledge_s1 8.0 1 \
        request_s1 request_s2 4.0 1 \
        acknowledge_s1 acknowledge_s2 4.0 1] {
        set a [get_regs $inst/$from]
        set b [get_regs $inst/$to]
        if {[llength $a] != $expected || [llength $b] != $expected} {
            error "DEMO CDC collection mismatch: $inst $from -> $to"
        }
        if {[string match *_s1 $to] || [string match *_s2 $to]} {
            foreach reg $b {
                if {![get_property ASYNC_REG $reg]} {error "DEMO CDC ASYNC_REG missing: $reg"}
            }
        }
        set label [string map [list {[} _ {]} _ {*} all] "${inst}_${from}_${to}"]
        set report "demo_cdc_${label}.rpt"
        report_timing_path -from $a -to $b -ep_num 64 -path_num 1 -report_type max_min -file $report
        set fd [open $report r]
        set detail [read $fd]
        close $fd
        set delays [regexp -all -inline {Data Path Delay[ \t]*:[ \t]*([0-9.]+)ns} $detail]
        if {[llength $delays] == 0} {error "DEMO CDC missing routed path: $label"}
        set worst 0.0
        foreach {whole value} $delays {
            if {$value > $worst} {set worst $value}
        }
        if {$worst > $limit} {error "DEMO CDC physical delay exceeded: $label $worst > $limit"}
        puts "DEMO_CDC_PHYSICAL $label source_count=[llength $a] target_count=[llength $b] max_data_delay_ns=$worst limit_ns=$limit"
        incr demo_cdc_paths
    }
}
if {$demo_cdc_paths != 25} {error "DEMO CDC audit group count mismatch"}
puts "DEMO_CDC_PHYSICAL_PASS groups=$demo_cdc_paths"
