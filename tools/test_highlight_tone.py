"""Verify local tone math/properties, moving video and physical-key controls.

The reference curve uses real arithmetic rather than the DUT's bit slices.
UI/sensor simulation uses their real 75/24 MHz clocks and original debounce
counters. This does not replace TD timing/resource checks or visual acceptance.
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


def run_logged(command: list[str], log: Path, root: Path, timeout: int) -> subprocess.CompletedProcess:
    result = subprocess.run(command, cwd=root, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, errors="replace", timeout=timeout)
    log.write_text(result.stdout, encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--iverilog-bin", type=Path,
                        default=Path("D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin"))
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    root = args.root.resolve()
    output = (args.output or root.parent / "_build" / root.name /
              "h1-local-tone-20261030" / "verification").resolve()
    output.mkdir(parents=True, exist_ok=True)
    summary = {"pass": False, "scope": "RTL tone math/properties/video and physical-key UI/sensor requests",
               "visual_acceptance": "not_tested", "output": str(output)}
    try:
        compiler = args.iverilog_bin.resolve() / "iverilog.exe"
        runtime = args.iverilog_bin.resolve() / "vvp.exe"
        if not compiler.is_file():
            located = shutil.which("iverilog")
            if not located:
                raise RuntimeError("Icarus Verilog not found; pass --iverilog-bin <directory>")
            compiler = Path(located)
            located_runtime = shutil.which("vvp")
            runtime = Path(located_runtime) if located_runtime else compiler.with_name("vvp.exe")
        if not runtime.is_file():
            raise RuntimeError(f"vvp not found: {runtime}")
        hdl = root / "user_source" / "hdl_source"
        sources = [root / "tools" / "tests" / "tb_highlight_tone.v", hdl / "highlight_region.v",
                   hdl / "highlight_tone.v", hdl / "img_mode_sel.v", hdl / "uiisp_beta" / "ae_set.v"]
        top_path = hdl / "design_top_wrapper.v"
        top = re.sub(r"/\*.*?\*/|//[^\n]*", "", top_path.read_text(encoding="utf-8"), flags=re.S)
        ui = re.search(r"img_mode_sel\s*#\s*\((.*?)\)\s*u_img_mode_sel", top, re.S)
        for parameter, value in (("EXP_RST", 2), ("REGION_RST", 2), ("REGION_N", 5)):
            if not ui or not re.search(rf"\.{parameter}\s*\(\s*{value}\s*\)", ui.group(1)):
                raise RuntimeError(f"Top UI must set {parameter}={value}")
        if not re.search(r"ae_set\s*#\s*\(\s*\.EXP_RST\s*\(\s*2\s*\)\s*\)\s*u_ae_set", top):
            raise RuntimeError("Sensor and UI startup exposure selectors must both be2 (AE1200)")
        if not re.search(r"\.I_exp_key_n\s*\(\s*I_key\[2\]\s*\)", top):
            raise RuntimeError("Physical sensor KEY3 is disconnected or remapped")
        if not re.search(r"highlight_tone\s+u_highlight_tone\s*\(", top):
            raise RuntimeError("Top-level tone module is missing")
        summary["source_sha256"] = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                                    for path in sources + [top_path]}
        compiled = output / "highlight_tone.vvp"
        command = [str(compiler), "-g2012", "-Wall", "-s", "tb_highlight_tone", "-o", str(compiled)]
        command.extend(map(str, sources))
        summary["compile_command"] = command
        build = run_logged(command, output / "compile.log", root, 60)
        if build.returncode:
            raise RuntimeError(f"Compile failed ({build.returncode}):\n{build.stdout}")
        simulated = run_logged([str(runtime), str(compiled)], output / "simulation.log", root, args.timeout)
        print(simulated.stdout, end="")
        if simulated.returncode:
            raise RuntimeError(f"Simulation failed ({simulated.returncode})")
        required = ["PASS colors:", "PASS frame 0:", "PASS frame 1:", "PASS frame 2:",
                    "PASS tone_pixels:", "PASS keys:", "PASS sensor:", "PASS highlight_tone:"]
        missing = [marker for marker in required if marker not in simulated.stdout]
        if missing:
            raise RuntimeError(f"Simulation did not complete required checks: {missing}")
        counts = re.search(r"PASS tone_pixels: (\d+) checked pixel/blank cycles; (\d+) hue/shoulder", simulated.stdout)
        if not counts:
            raise RuntimeError("Simulation check counts are missing")
        summary.update({"pass": True, "checked_pixel_cycles": int(counts.group(1)),
                        "property_checks": int(counts.group(2)), "active_video_pixels": 3*1280*720,
                        "frames": 3, "regions_per_frame": 3,
                        "ui_clock_hz": 75000000, "sensor_clock_hz": 24000000,
                        "debounce_accelerated": False,
                        "coverage": ["all256 gray codes monotone / neutral",
                                     "color cube, seven chromatic rays, deterministic20000 random RGBs",
                                     "half-code common-gain hue error bound",
                                     "candidate order, black, full white and no new clipping",
                                     "exact H1 Y4=831/832 and max249/250 boundaries",
                                     "off/invalid/blank/disabled passthrough; H1 marker",
                                     "three full720p moving frames, restored background, no trail",
                                     "real UI/sensor clocks and original debounce counters",
                                     "KEY4 five-state, physical bounce/long hold, KEY1/KEY2",
                                     "KEY3 UI/sensor cycle1200/900/1991/1600/1200",
                                     "simultaneous KEY3+KEY4; AE busy/config gating",
                                     "top-level default AE1200/C2 and physical KEY3 connection"]})
        print(f"Logs and summary: {output}")
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        summary["error"] = str(error)
        print(f"FAIL highlight_tone: {error}", file=sys.stderr)
    finally:
        (output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
