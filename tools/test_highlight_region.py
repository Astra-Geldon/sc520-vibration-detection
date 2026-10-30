"""Run behavioral RTL checks for the live highlight mask and its key controls.

All simulator outputs and logs are written to the stage directory under _build.
This verifies pixel logic and UI/AE startup behavior; it does not replace TD
timing/resource checks or HDMI board validation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


def run_logged(command: list[str], output_file: Path, cwd: Path) -> subprocess.CompletedProcess:
    result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, errors="replace", timeout=120)
    output_file.write_text(result.stdout, encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--iverilog-bin", type=Path,
                        default=Path("D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin"))
    args = parser.parse_args()
    root = args.root.resolve()
    output = (args.output or root.parent / "_build" / root.name /
              "region-segmentation-20261030" / "verification").resolve()
    output.mkdir(parents=True, exist_ok=True)
    summary_file = output / "summary.json"
    summary = {"pass": False, "scope": "RTL mask/UI plus real AE startup request", "output": str(output)}
    try:
        tool_dir = args.iverilog_bin.resolve()
        iverilog = tool_dir / "iverilog.exe"
        vvp = tool_dir / "vvp.exe"
        if not iverilog.is_file():
            located = shutil.which("iverilog")
            if not located:
                raise RuntimeError("Icarus Verilog not found; pass --iverilog-bin <directory>")
            iverilog = Path(located)
            located_vvp = shutil.which("vvp")
            vvp = Path(located_vvp) if located_vvp else iverilog.with_name("vvp.exe")
        if not vvp.is_file():
            raise RuntimeError(f"vvp not found: {vvp}")
        hdl = root / "user_source" / "hdl_source"
        sources = [root / "tools" / "tests" / "tb_highlight_region.v",
                   hdl / "highlight_region.v", hdl / "img_mode_sel.v",
                   hdl / "uiisp_beta" / "ae_set.v"]
        top = (hdl / "design_top_wrapper.v").read_text(encoding="utf-8")
        uncommented = re.sub(r"/\*.*?\*/|//[^\n]*", "", top, flags=re.S)
        ui_instance = re.search(r"img_mode_sel\s*#\s*\((.*?)\)\s*u_img_mode_sel", uncommented, re.S)
        if not ui_instance or not re.search(r"\.EXP_RST\s*\(\s*0\s*\)", ui_instance.group(1)):
            raise RuntimeError("Top-level UI does not explicitly reset to original0 exposure")
        if not re.search(r"\.I_exp_key_n\s*\(\s*I_key\[2\]\s*\)", uncommented):
            raise RuntimeError("Top-level sensor KEY3 input is disconnected or remapped")
        hashes = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sources + [hdl / "design_top_wrapper.v"]}
        summary["source_sha256"] = hashes
        compiled = output / "highlight_region.vvp"
        compile_command = [str(iverilog), "-g2012", "-Wall", "-s", "tb_highlight_region",
                           "-o", str(compiled)] + [str(path) for path in sources]
        summary["compile_command"] = compile_command
        build = run_logged(compile_command, output / "compile.log", root)
        if build.returncode:
            raise RuntimeError(f"RTL compile failed ({build.returncode}):\n{build.stdout}")
        simulation = run_logged([str(vvp), str(compiled)], output / "simulation.log", root)
        print(simulation.stdout, end="")
        if simulation.returncode:
            raise RuntimeError(f"RTL simulation failed with exit code {simulation.returncode}")
        required = ["PASS keys:", "PASS sensor:", "PASS colors:",
                    "PASS frame 0:", "PASS frame 1:", "PASS frame 2:", "PASS highlight_region:"]
        missing = [marker for marker in required if marker not in simulation.stdout]
        if missing:
            raise RuntimeError(f"Simulation did not finish required checks: {missing}")
        match = re.search(r"PASS highlight_region: (\d+) checked pixel/blank cycles", simulation.stdout)
        summary.update({"pass": True, "checked_pixel_cycles": int(match.group(1)),
                        "active_video_pixels": 3 * 1280 * 720,
                        "frames": 3, "regions_per_frame": 3,
                        "coverage": ["white sum width", "RGB channel clipping at 249/250",
                                     "Y208/Y224/Y240 exact and fractional edges", "all 256 neutral codes",
                                     "blank/off/disabled passthrough", "independent source/display data",
                                     "current-pixel mask, moving regions and cleared prior positions",
                                     "KEY4 bounce/hold/cycle", "KEY3 hold/cycle",
                                     "KEY1/KEY2 algorithms", "simultaneous KEY3/KEY4",
                                     "AE gated startup: one request AE1991/AG160",
                                     "top-level UI original0 reset and sensor KEY3 connection"]})
        print(f"Logs and summary: {output}")
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        summary["error"] = str(error)
        print(f"FAIL highlight_region: {error}", file=sys.stderr)
    finally:
        summary_file.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
