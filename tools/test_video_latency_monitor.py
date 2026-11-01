"""Check frame association and delay formatting with asynchronous Icarus clocks.

No TD tools are invoked. Generated simulation logs stay in the validation tree.
The testbench predicts age from external camera/output event times and frame-slot
identities, rather than reading the monitor's counters or conversion state.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "validation/latency_osd_20261101/sim_monitor"
OUT.mkdir(parents=True, exist_ok=True)
SOURCES = [
    ROOT / "tools/tests/tb_video_latency_monitor.v",
    ROOT / "user_source/hdl_source/video_latency_monitor.v",
    ROOT / "user_source/hdl_source/demo_switch_control.v",
]

compiler = shutil.which("iverilog") or r"C:\iverilog\bin\iverilog.exe"
runtime = shutil.which("vvp") or r"C:\iverilog\bin\vvp.exe"
compiled = OUT / "monitor.vvp"
build = subprocess.run(
    [compiler, "-g2012", "-Wall", "-s", "tb_video_latency_monitor", "-o", str(compiled),
     *map(str, SOURCES)],
    cwd=ROOT, text=True, capture_output=True, timeout=60,
)
(OUT / "compile.log").write_text(build.stdout + build.stderr, encoding="utf-8")
build.check_returncode()
run = subprocess.run([runtime, str(compiled)], cwd=ROOT, text=True,
                     capture_output=True, timeout=180)
(OUT / "result.log").write_text(run.stdout + run.stderr, encoding="utf-8")
print(run.stdout, end="")
if run.stderr:
    print(run.stderr, end="")
run.check_returncode()
assert "VIDEO_LATENCY_MONITOR_PASS" in run.stdout, "Missing simulation pass marker"
(OUT / "summary.json").write_text(json.dumps({
    "pass": True,
    "scope": "Frame-slot latency observation, asynchronous event crossings and BCD publication",
    "td_compilation": "not_run",
    "board_validation": "not_run",
    "source_sha256": {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in SOURCES
    },
}, indent=2), encoding="utf-8")
