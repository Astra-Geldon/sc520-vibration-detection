# 仅补跑已完成布线的独立CDC检查，不执行综合、布局、布线或bitgen。
# 从td_project目录运行，使用与修正后phaseC相同的相对路径调用方式。
if {[catch {
    if {![file exists demo_routed.db]} {error "Missing demo_routed.db"}
    set child [file join patch phaseD_audit_demo_cdc.tcl]
    exec [info nameofexecutable] $child > demo_cdc_audit.log 2>@1
    set fd [open demo_cdc_audit.log r]
    set audit_log [read $fd]
    close $fd
    puts $audit_log
    if {[string first {DEMO_CDC_PHYSICAL_PASS groups=40} $audit_log] < 0 ||
        [string first PHASE_D_DONE $audit_log] < 0} {
        error "Independent DEMO CDC audit failed"
    }
} audit_error]} {
    puts "FUSION_CDC_RECOVERY_FAIL: $audit_error"
    exit 1
}
puts FUSION_CDC_RECOVERY_PASS
exit 0
