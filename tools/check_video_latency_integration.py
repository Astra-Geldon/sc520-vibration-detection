"""Static latency wiring / unchanged DDR logic checks. Never launches TD.

The local pre-edit backup is required. Tcl tests below use mocked tool commands
only to check script syntax, path names and group counts, NOT routed timing.
"""
from pathlib import Path
import difflib
import hashlib
import json
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
HDL = ROOT / "user_source/hdl_source"
OUT = ROOT / "validation/latency_osd_20261101"
SIM = OUT / "sim_integration"
SIM.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(ROOT / "tools"))
from check_all_inst import parse_module, nocmt

top = nocmt((HDL / "design_top_wrapper.v").read_text(encoding="utf-8"))
for name in ("video_in", "video_out", "osd_overlay", "video_latency_monitor"):
    text = nocmt((HDL / (name + ".v")).read_text(encoding="utf-8"))
    _, ports = parse_module(text, name)
    matches = re.findall(r"\b" + name + r"\s*(?:#\s*\([^;]*?\)\s*)?\w+\s*\((.*?)\);", top, re.S)
    assert len(matches) == 1, name
    used = re.findall(r"\.(\w+)\s*\(", matches[0])
    assert set(used) == set(ports) and len(used) == len(set(used)), (name, used, ports)

for name in ("video_in.v", "video_out.v"):
    old = (OUT / "before/user_source/hdl_source" / name).read_text(encoding="utf-8")
    new = (HDL / name).read_text(encoding="utf-8")
    # Observe-only outputs are declarations and aliases. Every original state
    # machine, FIFO, address, busy, ready and data assignment must be identical.
    old_body = nocmt(old).split(");", 1)[1]
    new_body = nocmt(new).split(");", 1)[1]
    new_body = re.sub(r"assign\s+O_latency_\w+\s*=\s*\w+\s*;", "", new_body)
    assert re.sub(r"\s", "", old_body) == re.sub(r"\s", "", new_body), name
    (SIM / (name + ".diff")).write_text("".join(difflib.unified_diff(
        old.splitlines(True), new.splitlines(True), fromfile="before", tofile="after")), encoding="utf-8")

project = (ROOT / "td_project/camera_to_dsi_display.al").read_text(encoding="utf-8")
refs = re.findall(r'<File Path="([^"]+)"', project)
assert refs.count("../user_source/hdl_source/video_latency_monitor.v") == 1
assert all((ROOT / "td_project" / ref).resolve().is_file() for ref in refs)

# Mock TD commands in a separate folder; never read/write a real TD database.
TCL = r'''
array set widths {
    u_demo_mipi_controls 5 u_demo_hdmi_controls 6 u_demo_sensor_controls 4
    u_demo_mipi_status 5 u_demo_sensor_status 4 u_video_latency/u_result_cdc 17 u_ae_measure_cdc 6
}
set mock_fault none
proc get_regs {pattern} {
    global widths mock_fault
    if {$mock_fault eq "measure_missing" && $pattern eq {u_ae_measure_cdc/payload[*]}} {return {}}
    if {[regexp {^(.+)/(payload|O_dst_data)\[\*\]$} $pattern -> inst base]} {
        set count $widths($inst)
        if {$inst eq "u_demo_mipi_status" && $base eq "O_dst_data"} {set count 4}
        set regs {}
        for {set i 0} {$i < $count} {incr i} {lappend regs "${inst}/${base}\[$i\]"}
        return $regs
    }
    return [list $pattern]
}
proc get_property {property reg} {
    global mock_fault
    if {$mock_fault eq "key_not_async" && $reg eq "u_ae_key/key_meta"} {return 0}
    return 1
}
proc get_ports {args} {return dummy}
proc get_nets {args} {return dummy}
proc get_clocks {args} {return dummy}
foreach command {create_clock derive_clocks rename_clock set_false_path set_clock_groups set_max_delay clear_sdc read_sdc update_timing} {
    proc $command {args} {}
}
proc report_timing_path {args} {
    set index [lsearch -exact $args -file]
    set fd [open [lindex $args [expr {$index+1}]] w]
    global mock_fault
    if {$mock_fault eq "key_slow" && [lsearch -exact $args u_ae_key/key_sync] >= 0} {
        puts $fd "Data Path Delay : 4.500ns"
    } else {
        puts $fd "Data Path Delay : 0.500ns"
    }
    close $fd
}
source camera_to_dsi_display.sdc
source patch/check_demo_cdc.tcl
puts LATENCY_TCL_MOCK_PASS
'''
(SIM / "patch").mkdir(exist_ok=True)
for name in ("check_demo_cdc_registers.tcl", "check_demo_cdc.tcl"):
    shutil.copyfile(ROOT / "td_project/patch" / name, SIM / "patch" / name)
shutil.copyfile(ROOT / "td_project/camera_to_dsi_display.sdc", SIM / "camera_to_dsi_display.sdc")
(SIM / "audit_mock.tcl").write_text(TCL, encoding="utf-8")
tcl = shutil.which("tclsh")
assert tcl, "tclsh required for syntax-only mocked audit"
result = subprocess.run([tcl, "audit_mock.tcl"], cwd=SIM, capture_output=True, text=True, timeout=30)
(SIM / "tcl_mock.log").write_text(result.stdout + result.stderr, encoding="utf-8")
assert result.returncode == 0, result.stdout + result.stderr
assert "DEMO_CDC_REGISTERS_PASS groups=40" in result.stdout
assert "DEMO_CDC_PHYSICAL_PASS groups=40" in result.stdout
assert "LATENCY_TCL_MOCK_PASS" in result.stdout

# The mocks deliberately inject missing registers, a missing first-stage
# ASYNC_REG attribute, and a slow key stage1->stage2 data path. Each must fail;
# a success marker alone does not demonstrate that the auditor rejects errors.
negative_cases = {
    "measure_missing": "DEMO CDC collection mismatch: u_ae_measure_cdc",
    "key_not_async": "AE KEY CDC ASYNC_REG missing: u_ae_key/key_meta",
    "key_slow": "LATENCY CDC physical delay exceeded: u_ae_key_key_meta_u_ae_key_key_sync",
}
for fault, expected_error in negative_cases.items():
    (SIM / "audit_mock.tcl").write_text(TCL.replace("set mock_fault none", "set mock_fault " + fault), encoding="utf-8")
    failed = subprocess.run([tcl, "audit_mock.tcl"], cwd=SIM, capture_output=True, text=True, timeout=30)
    (SIM / ("tcl_mock_" + fault + ".log")).write_text(failed.stdout + failed.stderr, encoding="utf-8")
    assert failed.returncode != 0 and expected_error in failed.stderr, (fault, failed.stdout, failed.stderr)
(SIM / "audit_mock.tcl").write_text(TCL, encoding="utf-8")

sdc = (ROOT / "td_project/camera_to_dsi_display.sdc").read_text(encoding="utf-8")
assert len(re.findall(r"^set_max_delay\s", sdc, re.M)) == 40
assert "set_false_path -from [get_ports {I_key[3]}] -to [get_regs {u_ae_key/key_meta}]" in sdc
assert "set_false_path -from [get_ports {I_key[*]}]" not in sdc
assert "set_false_path -from [get_ports {I_key[3]}]\n" not in sdc

files = [HDL / n for n in ("design_top_wrapper.v", "video_in.v", "video_out.v",
                          "osd_overlay.v", "video_latency_monitor.v")]
summary = {
    "pass": True,
    "changed_module_top_ports_match": True,
    "video_in_out_original_logic_unchanged": True,
    "project_references_exist": True,
    "tcl_sdc_and_audit_syntax_mock_only": True,
    "cdc_groups_expected": 40,
    "cdc_fault_injection_rejected": list(negative_cases),
    "td_synthesis_place_route_or_programming_run": False,
    "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
}
(OUT / "integration_checks.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print("LATENCY_INTEGRATION_PASS: ports, unchanged DDR logic, project references, mocked Tcl 40 groups")
