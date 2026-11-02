"""检查融合入口、按键布线、CDC脚本和顶层语法，不调用TD。"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
HDL = ROOT / "user_source/hdl_source"
OUT = ROOT / "validation/fusion_exposure_linked/integration"
IV = Path(r"C:\Users\lenovo\AppData\Local\iverilog\bin\iverilog.exe")
sys.path.insert(0, str(ROOT / "tools"))
from check_all_inst import nocmt, parse_module


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    summary = {"pass": False, "td_run": False, "physical_cdc_verified": False}
    checked_files = []
    try:
        top_file = HDL / "design_top_wrapper.v"
        top_text = top_file.read_text(encoding="utf-8")
        top = nocmt(top_text)
        project_file = ROOT / "td_project/camera_to_dsi_display.al"
        project = project_file.read_text(encoding="utf-8")
        refs = re.findall(r'<File Path="([^"]+)"', project)
        assert all((project_file.parent / ref).resolve().is_file() for ref in refs)
        assert refs.count("../user_source/hdl_source/fusion_exposure_control.v") == 1
        assert not any(ref.endswith(("/ae_set.v", "/fixed_n1_lift.v")) for ref in refs)
        assert '`include "fusion_shadow_lift.v"' in top_text
        assert '`include "fixed_n1_lift.v"' not in top_text
        for name in ("ae_set", "fixed_n1_lift", "fixed_n1_extra_lift", "adaptive_n1_control"):
            assert not re.search(r"\b" + name + r"\s+(?:#\s*\([^;]+?\)\s*)?\w+\s*\(", top)
        names = ("fusion_exposure_control", "fusion_lift_control", "fusion_n1_envelope",
                 "fusion_lift_blend", "osd_overlay", "video_latency_monitor")
        for name in names:
            file = HDL / ("fusion_shadow_lift.v" if name in names[1:4] else name + ".v")
            _, ports = parse_module(nocmt(file.read_text(encoding="utf-8")), name)
            match = re.findall(r"\b" + name + r"\s*(?:#\s*\([^;]*?\)\s*)?\w+\s*\((.*?)\);", top, re.S)
            assert len(match) == 1, name
            used = re.findall(r"\.(\w+)\s*\(", match[0])
            assert len(used) == len(set(used)) and set(used) == set(ports), (name, used, ports)
            checked_files.append(file)
        # 三个控制位不再携带SW5，AE与补亮各自独立。
        sensor = re.search(r"u_demo_sensor_controls\s*\((.*?)\);", top, re.S)[1]
        assert ".I_src_data({~S_demo_switches[3], S_vib_enable_sys, S_ae_enable_sys})" in sensor
        ae = re.search(r"u_fusion_exposure_control\s*\((.*?)\);", top, re.S)[1]
        assert ".I_auto_en(S_demo_sensor_controls[0])" in ae
        assert ".I_freeze(S_demo_sensor_controls[1] || S_demo_sensor_controls[2])" in ae
        enable = re.search(r"wire S_fusion_enable\s*=\s*(.*?);", top, re.S)[1]
        assert "S_demo_hdmi[4]" in enable and "S_demo_hdmi[1]" not in enable
        control = re.search(r"u_fusion_lift_control\s*\((.*?)\);", top, re.S)[1]
        assert ".I_data(S_post_stage_original)" in control
        assert ".I_envelope_data(S_post_stage_data)" in control
        assert ".I_exposure({5'd0, S_demo_sensor_status[14:4]})" in control
        assert ".I_exposure_valid(S_fusion_exposure_ready)" in control
        assert ".I_key_n(I_key[3])" in top
        assert "S_key3_sync[1:0], I_key[2]" in top
        # 无关生产RTL与已烧录留档逐字节一致。
        unchanged = ["video_in.v", "video_out.v", "hdmi_mixer.v", "ae_luma_sampler.v",
                     "ae_key_toggle.v", "demo_switch_control.v", "img_proc.v",
                     "uics520_cfg/uicfgcs520.v"]
        for name in unchanged:
            path = HDL / name
            old = subprocess.check_output(["git", "show", "d755598:" + path.relative_to(ROOT).as_posix()], cwd=ROOT)
            assert old.replace(b"\r\n", b"\n") == path.read_bytes().replace(b"\r\n", b"\n"), name
        old_top = subprocess.check_output(["git", "show", "d755598:user_source/hdl_source/design_top_wrapper.v"], cwd=ROOT).decode("utf-8")
        marker = "    // Vibration path from the backup branch."
        assert old_top[old_top.index(marker):] == top_text[top_text.index(marker):]
        # IP不提供可仿真模型，因此只解析顶层及本次活动模块，缺失IP保留黑盒。
        compiled = subprocess.run([str(IV), "-g2012", "-i", "-Wall", "-I", str(HDL),
            "-s", "design_top_wrapper", "-o", str(OUT / "top_syntax.vvp"), str(top_file),
            str(HDL / "fusion_exposure_control.v"), str(HDL / "ae_key_toggle.v"),
            str(HDL / "video_latency_monitor.v"), str(HDL / "osd_overlay.v"),
            str(HDL / "osd_font_rom.v"), str(HDL / "osd_logo_rom.v"),
            str(HDL / "hdmi_mixer.v")], cwd=ROOT,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        (OUT / "top_syntax.log").write_bytes(compiled.stdout)
        assert compiled.returncode == 0, compiled.stdout.decode("utf-8", errors="replace")
        # 复用已有故障注入脚手架，只更新邮箱宽度；这是语法检查，不是物理时序。
        harness = (ROOT / "tools/check_video_latency_integration.py").read_text(encoding="utf-8")
        tcl = harness.split("TCL = r'''", 1)[1].split("'''", 1)[0]
        tcl = tcl.replace("u_demo_sensor_controls 4", "u_demo_sensor_controls 3")
        tcl = tcl.replace("u_demo_sensor_status 4", "u_demo_sensor_status 15")
        (OUT / "patch").mkdir(exist_ok=True)
        for name in ("check_demo_cdc.tcl", "check_demo_cdc_registers.tcl"):
            path = ROOT / "td_project/patch" / name
            shutil.copyfile(path, OUT / "patch" / name)
            checked_files.append(path)
        sdc = ROOT / "td_project/camera_to_dsi_display.sdc"
        shutil.copyfile(sdc, OUT / sdc.name)
        checked_files.append(sdc)
        faults = {
            "none": "LATENCY_TCL_MOCK_PASS",
            "measure_missing": "DEMO CDC collection mismatch: u_ae_measure_cdc",
            "key_not_async": "AE KEY CDC ASYNC_REG missing: u_ae_key/key_meta",
            "key_slow": "LATENCY CDC physical delay exceeded: u_ae_key_key_meta_u_ae_key_key_sync",
        }
        for fault, expected in faults.items():
            (OUT / "audit_mock.tcl").write_text(tcl.replace("set mock_fault none", "set mock_fault " + fault), encoding="utf-8")
            run = subprocess.run([shutil.which("tclsh"), "audit_mock.tcl"], cwd=OUT,
                capture_output=True, encoding="utf-8", errors="replace", timeout=30)
            log = run.stdout + run.stderr
            (OUT / ("cdc_" + fault + ".log")).write_text(log, encoding="utf-8")
            assert expected in log, (fault, log)
            if fault == "none":
                assert run.returncode == 0 and "DEMO_CDC_REGISTERS_PASS groups=40" in log
                assert "DEMO_CDC_PHYSICAL_PASS groups=40" in log
            else:
                assert run.returncode != 0
        checked_files += [top_file, project_file]
        summary.update(pass_=True, controls_independent=True, old_modules_excluded=True,
                       unchanged_rtl=unchanged, vibration_path_unchanged=True,
                       top_syntax_ip_blackboxes=True, mocked_cdc_groups=40,
                       fault_injection=list(faults)[1:])
        summary["pass"] = summary.pop("pass_")
        print("PASS 融合入口、KEY4/SW5独立、SW2仅Gamma、真实生效E、顶层语法、CDC40组脚本及3项故障注入")
    except Exception as error:
        summary["error"] = str(error)
        print(str(error))
    summary["source_sha256"] = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in checked_files}
    (OUT / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
