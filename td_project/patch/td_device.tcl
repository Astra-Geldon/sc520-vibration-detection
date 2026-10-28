# Resolve the device database from this TD installation, not a fixed drive.
# build_all.ps1 supplies SC520_TD_ARCH for every phase process.
proc sc520_import_device {} {
    if {[info exists ::env(SC520_TD_ARCH)] && $::env(SC520_TD_ARCH) ne ""} {
        set td_arch [file normalize $::env(SC520_TD_ARCH)]
    } else {
        set td_arch [file normalize [file join [file dirname [info nameofexecutable]] .. arch]]
    }
    if {![file isfile [file join $td_arch ph1_35p.db]]} {
        error "ph1_35p.db not found in $td_arch; run patch/build_all.ps1 -TdExe <TD bin/td_commands_prompt.exe>"
    }
    set saved_dir [pwd]
    cd $td_arch
    set result [catch {import_device ph1_35p.db -package PH1P35MDG324 -speed 3} message options]
    cd $saved_dir
    if {$result} {
        return -options $options $message
    }
    puts "TD_DEVICE_ARCH=$td_arch DEVICE=PH1P35MDG324 SPEED=3"
}
