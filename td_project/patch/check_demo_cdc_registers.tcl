# Executed as Tcl after read_sdc, never embedded in the SDC parser.
set demo_register_groups 0
foreach {inst width} {
    u_demo_mipi_controls 5
    u_demo_hdmi_controls 5
    u_demo_sensor_controls 1
    u_demo_mipi_status 5
    u_demo_sensor_status 3
} {
    foreach {from to expected} [list \
        {payload[*]} {O_dst_data[*]} $width \
        request request_s1 1 acknowledge acknowledge_s1 1 \
        request_s1 request_s2 1 acknowledge_s1 acknowledge_s2 1] {
        set a [get_regs $inst/$from]
        set b [get_regs $inst/$to]
        # mipi_status bit4 is intentionally unused: exposure status has its own
        # sensor mailbox. TD drops that destination bit, not a sync stage.
        set dst_expected $expected
        if {$inst eq "u_demo_mipi_status" && $from eq {payload[*]}} {set dst_expected 4}
        if {[llength $a] != $expected || [llength $b] != $dst_expected} {
            error "DEMO CDC collection mismatch: $inst $from -> $to"
        }
        foreach reg [concat $a $b] {
            if {[string match *_s1 $reg] || [string match *_s2 $reg]} {
                if {![get_property ASYNC_REG $reg]} {error "DEMO CDC ASYNC_REG missing: $reg"}
            }
        }
        incr demo_register_groups
    }
}
if {$demo_register_groups != 25} {error "DEMO CDC register group count mismatch"}
puts "DEMO_CDC_REGISTERS_PASS groups=$demo_register_groups"
