#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用独立整数参考验证融合补亮控制、曝光联动和像素处理，不运行TD。"""

from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
HDL = ROOT / "user_source/hdl_source"
BASELINE = "9d930ed"
IVERILOG = Path(shutil.which("iverilog") or
                r"C:\Users\lenovo\AppData\Local\iverilog\bin\iverilog.exe")


CONTROL_BENCH = r'''
`timescale 1ns/1ps
module tb;
    localparam integer W=256, H=12, N=W*H/64;
    reg clk=0; always #1 clk=~clk;
    reg rst_n=0, vs=0, de=0, enable=0, exposure_valid=1;
    reg [23:0] data=0, envelope_data=0;
    reg [15:0] exposure=900;
    wire [4:0] strength;
    wire [15:0] reference_exposure;
    wire [9:0] reference_luma;
    wire triggered;
    integer p, k, value, x, frame_no=0;

    fusion_lift_control #(.H_ACTIVE(W), .V_ACTIVE(H), .EXPECTED_SAMPLES(N),
        .SAMPLE_LOG2(6)) dut(
        .I_clk(clk), .I_rst_n(rst_n), .I_vs(vs), .I_de(de), .I_enable(enable),
        .I_data(data), .I_envelope_data(envelope_data), .I_exposure(exposure),
        .I_exposure_valid(exposure_valid), .O_strength(strength),
        .O_reference_exposure(reference_exposure), .O_reference_luma(reference_luma),
        .O_triggered(triggered));

    task blank;
        input integer count;
        integer i;
        begin
            for(i=0;i<count;i=i+1) begin
                @(negedge clk); de=0; data=0; envelope_data=0;
            end
        end
    endtask

    task boundary;
        begin
            @(negedge clk); vs=1; de=0;
            @(negedge clk); vs=0;
            blank(140);
        end
    endtask

    task reset_dut;
        begin
            rst_n=0; enable=0; vs=0; de=0;
            blank(8);
            @(negedge clk); rst_n=1;
            boundary;
        end
    endtask

    // pattern=0为均匀背景，pattern=1为左暗右亮的明暗冲突场景。
    task frame;
        input integer pattern;
        begin
            for(p=0;p<W*H;p=p+1) begin
                @(negedge clk); de=1; x=p%W;
                if(pattern==0) value=128;
                else value=(x<W/2) ? 32 : 224;
                data={8'(value),8'(value),8'(value)};
                envelope_data=data;
            end
            blank(8);
            boundary;
            frame_no=frame_no+1;
            if($isunknown({strength,triggered,reference_exposure,reference_luma}))
                $fatal(1,"输出出现X frame=%0d",frame_no);
        end
    endtask

    initial begin
        reset_dut;
        enable=1; exposure=900; exposure_valid=1;
        // 先建立正常背景基线，再进入高光/暗部共存场景。
        for(k=0;k<5;k=k+1) frame(0);
        if(triggered || strength!=0) $fatal(1,"均匀背景误触发");
        for(k=0;k<3;k=k+1) frame(1);
        if(!triggered || reference_exposure!=900 || reference_luma!=512)
            $fatal(1,"明暗场景未在三帧后触发或基线错误 E=%0d L=%0d",reference_exposure,reference_luma);
        // 稳定E后，Tone强度逐帧上升而不是一步跳满。
        for(k=0;k<25;k=k+1) frame(1);
        if(strength<12 || strength>16) $fatal(1,"Tone稳定强度异常=%0d",strength);
        // E变化期间保持现有显示强度，避免AE和Tone同时抖动。
        exposure=600;
        for(k=0;k<10;k=k+1) frame(1);
        if(strength<12 || !triggered) $fatal(1,"E变化期间Tone异常 E=%0d strength=%0d",exposure,strength);
        // 光源移开后恢复均匀背景，等待约0.75秒稳定帧后自动退出。
        exposure=900;
        for(k=0;k<70;k=k+1) frame(0);
        if(triggered || strength!=0 || reference_exposure!=0 || reference_luma!=0)
            $fatal(1,"高光移开后未自动退出 trig=%b strength=%0d",triggered,strength);
        // 退出后再次出现明暗冲突，必须能够建立新的参考并触发。
        for(k=0;k<3;k=k+1) frame(1);
        if(!triggered) $fatal(1,"退出后重新触发失败");
        $display("PASS fusion_control_new frames=%0d",frame_no);
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1,"融合控制仿真超时");
    end
endmodule
'''


PIXEL_BENCH = r'''
`timescale 1ns/1ps
module tb;
    reg de=1, enable=1;
    reg [23:0] original=0;
    reg [7:0] peak=0;
    reg [4:0] strength=0;
    wire [23:0] envelope, actual;
    integer s,p,v,k,last,checks=0,highlight_checks=0,zero_checks=0;
    integer er,eg,eb,rr,rg,rb;
    reg [23:0] expected_envelope, expected;
    reg [31:0] rng=32'h19a7806b;
    fusion_n1_envelope n1(.I_de(de), .I_enable(enable), .I_data(original),
        .I_peak(peak), .O_data(envelope));
    fusion_lift_blend blend(.I_de(de), .I_enable(enable), .I_original(original),
        .I_envelope(envelope), .I_strength(strength), .O_data(actual));

    function integer tone;
        input integer pixel;
        integer base, delta, product, segment;
        begin
            segment=pixel/16;
            case(segment)
                0:  begin base=0;   delta=18; end
                1:  begin base=18;  delta=18; end
                2:  begin base=36;  delta=18; end
                3:  begin base=54;  delta=18; end
                4:  begin base=72;  delta=18; end
                5:  begin base=90;  delta=18; end
                6:  begin base=108; delta=16; end
                7:  begin base=124; delta=15; end
                8:  begin base=139; delta=14; end
                9:  begin base=153; delta=13; end
                10: begin base=166; delta=12; end
                11: begin base=178; delta=10; end
                12: begin base=188; delta=10; end
                13: begin base=198; delta=12; end
                14: begin base=210; delta=15; end
                default: begin base=225; delta=30; end
            endcase
            product=delta*(pixel%16)+8;
            tone=(pixel==255)?255:base+product/16;
        end
    endfunction

    function integer channel_blend;
        input integer pixel, envelope_pixel, level;
        integer value, delta;
        begin
            if(envelope_pixel>=pixel) begin
                delta=envelope_pixel-pixel;
                value=pixel+(delta*level+8)/16;
            end else begin
                delta=pixel-envelope_pixel;
                value=pixel-(delta*level+8)/16;
            end
            channel_blend=(value<0)?0:((value>255)?255:value);
        end
    endfunction

    task check;
        input integer r,g,b;
        begin
            original={8'(r),8'(g),8'(b)};
            peak=(r>g)?((r>b)?r:b):((g>b)?g:b);
            er=tone(r); eg=tone(g); eb=tone(b);
            expected_envelope={8'(er),8'(eg),8'(eb)};
            rr=channel_blend(r,er,strength);
            rg=channel_blend(g,eg,strength);
            rb=channel_blend(b,eb,strength);
            expected={8'(rr),8'(rg),8'(rb)};
            if(!de || !enable) begin expected_envelope=original; expected=original; end
            #1;
            if(envelope!==expected_envelope)
                $fatal(1,"N1包络偏离基线 rgb=%06x actual=%06x expected=%06x",original,envelope,expected_envelope);
            if(actual!==expected)
                $fatal(1,"融合混合偏离整数参考 s=%0d rgb=%06x actual=%06x expected=%06x",strength,original,actual,expected);
            if(peak>=192) begin
                if(peak<255 && ((r==peak && actual[23:16]>r) ||
                                (g==peak && actual[15:8]>g) ||
                                (b==peak && actual[7:0]>b)))
                    $fatal(1,"高光未压缩");
                highlight_checks=highlight_checks+1;
            end
            if(strength==0) begin
                if(actual!==original) $fatal(1,"强度0未逐位复用原图");
                zero_checks=zero_checks+1;
            end
            if(de && enable && ((er>=r && actual[23:16]<r) ||
                                (er<r && actual[23:16]>r) ||
                                (eg>=g && actual[15:8]<g) ||
                                (eg<g && actual[15:8]>g) ||
                                (eb>=b && actual[7:0]<b) ||
                                (eb<b && actual[7:0]>b)))
                $fatal(1,"Tone方向错误");
            checks=checks+1;
        end
    endtask

    initial begin
        for(s=0;s<=16;s=s+1) begin
            strength=s; last=0;
            for(p=0;p<256;p=p+1) begin
                check(p,p,p);
                if(p>0 && actual[23:16]<last) $fatal(1,"灰阶反转 s=%0d p=%0d",s,p);
                last=actual[23:16];
                check(p,p/2,p/3); check(p/2,p,p/3); check(p/3,p/2,p);
                for(v=0;v<=p;v=v+17) begin
                    check(p,v,v/2); check(v/2,p,v); check(v,v/2,p);
                end
            end
        end
        for(k=0;k<3000;k=k+1) begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            strength=rng[31:24]%17;
            check(rng[23:16],rng[15:8],rng[7:0]);
        end
        strength=16; de=0; check(63,127,191); check(255,0,1);
        de=1; enable=0; check(63,127,191); check(255,0,1);
        $display("PASS fusion_pixels checks=%0d highlight_checks=%0d zero_checks=%0d",checks,highlight_checks,zero_checks);
        $finish;
    end
endmodule
'''


def decode(output: bytes) -> str:
    return output.decode("utf-8", errors="replace")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=ROOT / "validation/fusion_linked_lift_20261102")
    parser.add_argument("--case", choices=("all", "control", "pixels"), default="all")
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    source = HDL / "fusion_shadow_lift.v"
    summary = {
        "pass": False, "td_run": False,
        "scope": "独立整数参考、真实像素帧驱动、曝光触发锁存与平滑；不验证物理画质或布线时序",
        "baseline_commit": subprocess.check_output(
            ["git", "rev-parse", BASELINE], cwd=ROOT).decode().strip(),
        "tests": {},
    }
    try:
        baseline = subprocess.check_output(
            ["git", "show", BASELINE + ":user_source/hdl_source/fixed_n1_lift.v"],
            cwd=ROOT).decode("utf-8")
        gains = {int(pixel): int(gain) for pixel, gain in re.findall(
            r"8'd(\d+):\s*O_gain\s*=\s*11'd(\d+)", baseline)}
        if sorted(gains) != list(range(256)):
            raise AssertionError("Git基线N1增益表缺失或不完整")
        (out / "baseline_n1_gains.hex").write_text(
            "".join(f"{gains[pixel]:03x}\n" for pixel in range(256)), encoding="utf-8")
        summary["baseline_gain_sha256"] = hashlib.sha256(
            (out / "baseline_n1_gains.hex").read_bytes()).hexdigest()
        summary["source_sha256"] = {source.relative_to(ROOT).as_posix():
                                    hashlib.sha256(source.read_bytes()).hexdigest()}
        for name, bench in (("control", CONTROL_BENCH), ("pixels", PIXEL_BENCH)):
            if args.case not in ("all", name):
                continue
            tb = out / (name + "_tb.v")
            binary = out / (name + ".vvp")
            tb.write_text(bench, encoding="utf-8", newline="\n")
            compiled = subprocess.run(
                [str(IVERILOG), "-g2012", "-Wall", "-I", os.path.relpath(HDL, out), "-s", "tb",
                 "-o", binary.name, tb.name, os.path.relpath(source, out)], cwd=out,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
            (out / (name + "_compile.log")).write_text(decode(compiled.stdout), encoding="utf-8")
            if compiled.returncode:
                raise AssertionError(name + "仿真编译失败：\n" + decode(compiled.stdout))
            run = subprocess.run([str(IVERILOG.with_name("vvp.exe")), str(binary)],
                                 cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 timeout=120)
            result = decode(run.stdout)
            (out / (name + ".log")).write_text(result, encoding="utf-8")
            print(result, end="", flush=True)
            if run.returncode or "PASS fusion_" not in result:
                raise AssertionError(name + "仿真失败：\n" + result)
            fields = {key: int(value) for key, value in re.findall(r"(\w+)=(\d+)", result)}
            summary["tests"][name] = {"pass": True, **fields}
        summary["pass"] = True
    except Exception as error:
        summary["error"] = str(error)
        print(str(error), flush=True)
    (out / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
