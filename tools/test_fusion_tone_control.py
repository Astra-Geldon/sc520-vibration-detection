#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""独立Icarus帧驱动验证fusion_lift_control的新Tone控制策略。"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "user_source" / "hdl_source" / "fusion_shadow_lift.v"
OUT = ROOT / "validation" / "fusion_tone_control_20261103"


TB = r'''
`timescale 1ns/1ps
module tb;
    localparam integer W=128, H=12, N=192;
    reg clk=0; always #1 clk=~clk;
    reg rst_n=0, vs=0, de=0, enable=0, exposure_valid=1;
    reg [23:0] data=0, envelope_data=0;
    reg [15:0] exposure=900;
    wire [4:0] strength;
    wire [15:0] reference_exposure;
    wire [9:0] reference_luma;
    wire triggered;
    wire [23:0] blend_bypass;
    integer frame_no=0, checks=0, max_strength=0, ae_hold_checks=0;
    integer exit_frame=0, j, old_strength;

    fusion_lift_control #(.H_ACTIVE(W), .V_ACTIVE(H), .EXPECTED_SAMPLES(N),
        .SAMPLE_LOG2(3)) dut(
        .I_clk(clk), .I_rst_n(rst_n), .I_vs(vs), .I_de(de), .I_enable(enable),
        .I_data(data), .I_envelope_data(envelope_data),
        .I_exposure(exposure), .I_exposure_valid(exposure_valid),
        .O_strength(strength), .O_reference_exposure(reference_exposure),
        .O_reference_luma(reference_luma), .O_triggered(triggered));
    fusion_lift_blend u_bypass_check(
        .I_de(1'b1), .I_enable(enable), .I_original(24'h123456),
        .I_envelope(24'hedcba9), .I_strength(strength), .O_data(blend_bypass));

    task blank;
        input integer count;
        integer i;
        begin
            for(i=0;i<count;i=i+1) begin
                @(negedge clk); vs=0; de=0; data=0; envelope_data=0;
            end
        end
    endtask

    // 只发VS而不发有效像素，收集上一帧的最终三拍归约结果。
    task evaluate_previous;
        begin
            @(negedge clk); vs=1; de=0; data=0; envelope_data=0;
            @(negedge clk); vs=0;
            blank(8);
        end
    endtask

    // pattern=0均匀中灰；pattern=1左右强反差。控制器只需场景证据，
    // 因而包络取原值，避免把像素曲线数值混入本测试。
    task frame;
        input integer pattern;
        input integer frame_exposure;
        integer i, x, value;
        begin
            exposure=frame_exposure;
            @(negedge clk); vs=1; de=0; data=0; envelope_data=0;
            @(negedge clk); vs=0;
            for(i=0;i<W*H;i=i+1) begin
                @(negedge clk); de=1; x=i%W;
                if(pattern==1) value=(x<W/2) ? 32 : 224;
                else value=128;
                data={value[7:0],value[7:0],value[7:0]};
                envelope_data=data;
            end
            blank(8);
            frame_no=frame_no+1;
            if($isunknown({strength,triggered,reference_exposure,reference_luma}))
                $fatal(1,"输出出现X frame=%0d",frame_no);
            if(enable && strength>old_strength+1)
                $fatal(1,"强度上升超过1档 frame=%0d old=%0d new=%0d",frame_no,old_strength,strength);
            if(enable && old_strength>strength+1)
                $fatal(1,"强度下降超过1档 frame=%0d old=%0d new=%0d",frame_no,old_strength,strength);
            if(strength>max_strength) max_strength=strength;
            old_strength=strength;
            checks=checks+1;
        end
    endtask

    task expect_bypass;
        begin
            if(strength!==0 || triggered!==0 || reference_exposure!==0 || reference_luma!==0)
                $fatal(1,"SW5关闭没有旁路清零 strength=%0d triggered=%b refE=%0d refL=%0d",
                       strength,triggered,reference_exposure,reference_luma);
            if(blend_bypass!==24'h123456)
                $fatal(1,"SW5关闭像素混合器未逐位旁路 data=%06x",blend_bypass);
        end
    endtask

    initial begin
        old_strength=0;
        enable=0; exposure=900; rst_n=0;
        blank(8); expect_bypass;
        rst_n=1; blank(4);
        frame(1,900); frame(1,900); expect_bypass;

        // 三个完整强反差帧后，再发一个无效帧边界让最后一帧完成归约。
        enable=1;
        frame(1,900); if(triggered) $fatal(1,"第一帧强反差提前触发");
        frame(1,900); if(triggered) $fatal(1,"第二帧强反差提前触发");
        frame(1,900); if(triggered) $fatal(1,"第三帧结束时误报触发");
        evaluate_previous;
        if(!triggered || reference_exposure!==900 || reference_luma==0)
            $fatal(1,"强反差三帧后未触发 refE=%0d refL=%0d",reference_exposure,reference_luma);

        // 稳定场景下每帧最多一档，最终到16档。
        for(j=0;j<24;j=j+1) begin
            frame(1,900);
            if(!triggered) $fatal(1,"强反差保持期间意外退出 frame=%0d",frame_no);
        end
        evaluate_previous;
        if(strength!==16 || max_strength!==16)
            $fatal(1,"稳定强反差未达到16档 strength=%0d max=%0d",strength,max_strength);

        // AE在途期间连续改变E，显示强度和首次参考必须保持。
        old_strength=strength;
        frame(1,700); frame(1,650);
        if(strength!==old_strength || !triggered)
            $fatal(1,"AE变化期间强度未保持 old=%0d new=%0d",old_strength,strength);
        ae_hold_checks=ae_hold_checks+1;
        frame(1,700);
        if(strength!==old_strength || !triggered)
            $fatal(1,"AE再次变化期间强度未保持 old=%0d new=%0d",old_strength,strength);
        ae_hold_checks=ae_hold_checks+1;
        if(reference_exposure!==900)
            $fatal(1,"AE变化改写了首次参考E=%0d",reference_exposure);

        // 先令E改变，再移除高光；保持均匀场景约45个稳定帧后应退出。
        frame(0,700); frame(0,700);
        exit_frame=0;
        for(j=1;j<=55;j=j+1) begin
            frame(0,700);
            if(!triggered && exit_frame==0) exit_frame=j;
        end
        if(exit_frame<40 || exit_frame>50)
            $fatal(1,"均匀场景退出不在约45稳定帧内 exit_frame=%0d",exit_frame);
        if(triggered) $fatal(1,"均匀场景55帧后仍在保护");

        // 保护位清除后强度逐帧退到0，再次出现三帧反差必须重新触发。
        for(j=0;j<24;j=j+1) begin
            frame(0,700);
            if(triggered) $fatal(1,"退出后均匀场景再次误触发");
        end
        evaluate_previous;
        if(strength!==0) $fatal(1,"退出后的强度未归零 actual=%0d",strength);
        frame(1,700); frame(1,700); frame(1,700); evaluate_previous;
        if(!triggered || reference_exposure!==700)
            $fatal(1,"退出后不能重新触发 triggered=%b refE=%0d",triggered,reference_exposure);

        $display("PASS fusion_tone_control checks=%0d frames=%0d max_strength=%0d ae_hold_checks=%0d exit_frame=%0d rearmed=%0d",
                 checks,frame_no,max_strength,ae_hold_checks,exit_frame,triggered);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1,"fusion_tone_control仿真超时");
    end
endmodule
'''


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    OUT.mkdir(parents=True, exist_ok=True)
    tb = OUT / "fusion_tone_control_tb.v"
    binary = OUT / "fusion_tone_control.vvp"
    compile_log = OUT / "compile.log"
    simulation_log = OUT / "simulation.log"
    iverilog = Path(shutil.which("iverilog") or
                    r"C:\Users\lenovo\AppData\Local\iverilog\bin\iverilog.exe")
    vvp = Path(shutil.which("vvp") or iverilog.with_name("vvp.exe"))
    summary = {
        "pass": False,
        "td_run": False,
        "scope": "独立fusion_lift_control小帧仿真：SW5旁路、三帧触发、16档平滑、AE保持、约0.75秒退出和再次触发",
        "source": str(SOURCE.relative_to(ROOT)).replace("\\", "/"),
        "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "parameters": {"H_ACTIVE": 128, "V_ACTIVE": 12, "EXPECTED_SAMPLES": 192, "SAMPLE_LOG2": 3},
    }
    try:
        tb.write_text(TB, encoding="utf-8", newline="\n")
        compiled = subprocess.run(
            [str(iverilog), "-g2012", "-Wall", "-s", "tb", "-o", str(binary), str(tb), str(SOURCE)],
            cwd=OUT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        compile_log.write_bytes(compiled.stdout)
        if compiled.returncode:
            raise RuntimeError("Icarus编译失败：\n" + compiled.stdout.decode("utf-8", "replace"))
        run = subprocess.run([str(vvp), str(binary)], cwd=OUT,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        simulation_log.write_bytes(run.stdout)
        result = run.stdout.decode("utf-8", "replace")
        print(result, end="", flush=True)
        if run.returncode or "PASS fusion_tone_control" not in result:
            raise RuntimeError("fusion_tone_control仿真失败，详见simulation.log")
        summary.update({key: int(value) for key, value in re.findall(
            r"(checks|frames|max_strength|ae_hold_checks|exit_frame|rearmed)=(\d+)", result)})
        summary["pass"] = True
    except Exception as error:
        summary["error"] = str(error)
        print(str(error), flush=True)
    (OUT / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
