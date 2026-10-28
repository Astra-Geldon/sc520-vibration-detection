# phaseB_patch_db.tcl -- 阶段 B：在逻辑数据库里把 12 个计数器选择器从 valid_2d 改接 valid_3d
#
# 依据：队友 2026-10-06「round35_counter_valid3_rtl」验证过的做法
#   docs/HDMI采集卡成功经验/.../round35_counter_valid3_rtl/{patch_database.tcl,结果记录.md}
#
# 为什么要改数据库而不是改 RTL：
#   HDMI 发射核 hdmi_1_4b_transmitter_core_wrapper.enc.v 是 IEEE-1735 加密核，
#   内部 `S_cnt_t_1` 计数器的更新/清零条件用的是 S_video_valid_2d，而像素数据
#   到编码级是第 3 拍（S_video_valid_3d）。错一拍 ⇒ 行首多算一拍、RD 从 -8 起步，
#   显示器能凑合，UGREEN 25856/25854 这类采集卡就会黑屏。
#
# 本仓库实测的接线（与队友那边完全一致）：
#   S_video_valid_2d : 14 pin = 驱动 1 + 12×mux6_syn_[2345].sel + valid_3d_reg.d
#   S_video_valid_3d :  2 pin = valid_3d_reg.q + valid_4d_reg.d
#   patch 后应为：valid_2d 2 pin，valid_3d 14 pin
#
# 用法：cd td_project && echo 'source patch/phaseB_patch_db.tcl' | td_commands_prompt.exe

source [file join [file dirname [info script]] td_device.tcl]

if {[catch {
    set p0 [pwd]
    sc520_import_device

    import_db baseline_rtl.db

    set base u_hdmi_tx/u_hdmi_1_4b_transmitter_core_wrapper/u_hdmi_tx_controller_wrapper
    set oldnet $base/u0_hdmi_tmds_encode/S_video_valid_2d
    set newnet $base/u0_hdmi_tmds_encode/S_video_valid_3d

    set oldpins [get_pins -verbose -of [get_nets $oldnet]]
    set newpins [get_pins -verbose -of [get_nets $newnet]]
    puts "BEFORE: valid_2d=[llength $oldpins] pins, valid_3d=[llength $newpins] pins"

    # 挑出 3 个编码器里 mux6_syn_2..5 的 sel
    set patchpins {}
    foreach pin $oldpins {
        if {[regexp {/u[012]_hdmi_tmds_encode/mux6_syn_[2345]\.sel$} $pin]} {
            lappend patchpins $pin
        }
    }
    if {[llength $patchpins] != 12} {
        error "expected 12 counter selectors, got [llength $patchpins]"
    }

    foreach pin $patchpins {
        report_cells [string range $pin 0 end-4] -connection
        disconnect_net -net $oldnet -objects $pin
        connect_net    -net $newnet -objects $pin
    }

    # ---- 校验 ----
    set oldafter [get_pins -verbose -of [get_nets $oldnet]]
    set newafter [get_pins -verbose -of [get_nets $newnet]]
    puts "AFTER : valid_2d=[llength $oldafter] pins, valid_3d=[llength $newafter] pins"
    foreach pin $patchpins {
        if {[lsearch -exact $oldafter $pin] >= 0} { error "still on valid_2d: $pin" }
        if {[lsearch -exact $newafter $pin] < 0}  { error "not on valid_3d: $pin" }
    }
    if {[llength $oldafter] != 2 || [llength $newafter] != 14} {
        error "unexpected pin counts after patch"
    }
    puts "VERIFIED_COUNTER_SELECTORS12"

    report_nets $oldnet -connection -pin_output_limit 30
    report_nets $newnet -connection -pin_output_limit 30

    export_db patched_rtl.db
    puts "PATCH_FINISHED"
} err]} { puts "PATCH_ERROR $err" ; exit 1 }
exit 0
