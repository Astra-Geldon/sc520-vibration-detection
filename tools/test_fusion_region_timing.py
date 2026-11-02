#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""对照提交中的原区域控制器，验证三拍极值归约的逐周期等价性。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
IVERILOG = Path(r"C:\Users\lenovo\AppData\Local\iverilog\bin\iverilog.exe")

BENCH = r'''
`timescale 1ns/1ps
module tb;
    localparam integer W=@WIDTH@, H=@HEIGHT@, FULL=@FULL@;
    localparam integer PIXELS=W*H, N=PIXELS/64;
    reg clk=0; always #1 clk=~clk;
    reg rst_n=0, vs=0, de=0, enable=1;
    reg [23:0] data=0;
    wire [3:0] actual, expected;
    integer cycles=0, checks=0, frames=0, valid_frames=0;
    integer short_frames=0, long_frames=0, mid_switch_frames=0, reset_frames=0;
    integer last_sample=-1000, min_sample_gap=2147483647, gap=0;
    integer max_strength=0, changes=0, previous_strength=0, k;
    reg [31:0] rng=32'h19a7806b;
    integer region_value[0:11];
    adaptive_n1_control #(.H_ACTIVE(W),.V_ACTIVE(H),.EXPECTED_SAMPLES(N),.SAMPLE_LOG2(6)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_vs(vs),.I_de(de),.I_enable(enable),
        .I_data(data),.O_strength(actual));
    reference_adaptive_n1_control #(.H_ACTIVE(W),.V_ACTIVE(H),.EXPECTED_SAMPLES(N),.SAMPLE_LOG2(6)) ref_dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_vs(vs),.I_de(de),.I_enable(enable),
        .I_data(data),.O_strength(expected));

    always @(posedge clk) begin
        cycles=cycles+1;
        if(rst_n && dut.vs_start && dut.frame_good) begin
            valid_frames=valid_frames+1;
            gap=cycles-last_sample;
            if(gap<min_sample_gap) min_sample_gap=gap;
            if(gap<3) $fatal(1,"last sample did not have three cycles to settle");
            if(dut.min_sum!==ref_dut.min_sum || dut.max_sum!==ref_dut.max_sum ||
               dut.range_sum!==ref_dut.range_sum)
                $fatal(1,"region reduction mismatch at frame boundary, frame=%0d gap=%0d",frames,gap);
            if(dut.contrast_enter!==ref_dut.contrast_enter || dut.contrast_exit!==ref_dut.contrast_exit)
                $fatal(1,"frame classification mismatch frame=%0d",frames);
        end
        if(rst_n && dut.active && !dut.vs_start && dut.sample_now) last_sample=cycles;
        #0.1;
        if(rst_n) begin
            if(actual!==expected || dut.rise_wait!==ref_dut.rise_wait ||
               dut.fall_wait!==ref_dut.fall_wait)
                $fatal(1,"cycle mismatch cycle=%0d frame=%0d actual=%0d ref=%0d",cycles,frames,actual,expected);
            if(actual>8) $fatal(1,"strength exceeds supported bound");
            if(actual>max_strength) max_strength=actual;
            if(actual!=previous_strength) changes=changes+1;
            previous_strength=actual;
            checks=checks+1;
        end else begin
            if(actual!==0 || expected!==0) $fatal(1,"reset did not clear strength");
            previous_strength=0;
        end
    end

    task blank;
        input integer n;
        integer b;
        begin
            for(b=0;b<n;b=b+1) begin
                @(negedge clk); de=0; vs=0; data=0;
            end
        end
    endtask

    // 各种长度、开关和复位均驱动同一对模块，不修改任何算法门限。
    task frame;
        input integer pattern, pixel_count, perturbation;
        integer p,x,y,col,row,r,v;
        begin
            @(negedge clk); vs=1; de=0; data=0;
            frames=frames+1;
            @(negedge clk); vs=0;
            for(r=0;r<12;r=r+1) begin
                rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
                region_value[r]=8+(rng[15:8]%240);
            end
            for(p=0;p<pixel_count;p=p+1) begin
                @(negedge clk); de=1;
                x=p%W; y=p/W;
                col=(x<W/4)?0:((x<W/2)?1:((x<3*W/4)?2:3));
                row=(y<H/3)?0:((y<2*H/3)?1:2);
                case(pattern)
                    0:v=128;
                    1:v=(x<W/2)?32:224;
                    2:v=region_value[row*4+col];
                    3:v=(row==0)?16:((row==1)?112:240);
                    4:v=16;
                    default:v=240;
                endcase
                data={8'(v),8'(v),8'(v)};
                if(perturbation==1) begin
                    if(p==PIXELS/3) enable=0;
                    if(p==2*PIXELS/3) enable=1;
                end
                if(perturbation==2) begin
                    if(p==PIXELS/2) rst_n=0;
                    if(p==PIXELS/2+3) rst_n=1;
                end
            end
            @(negedge clk); de=0; data=0;
            // 下一帧仅隔一拍空白，检验最后样本后63个有效像素已足够收敛。
            if(pixel_count<PIXELS) short_frames=short_frames+1;
            if(pixel_count>PIXELS) long_frames=long_frames+1;
            if(perturbation==1) mid_switch_frames=mid_switch_frames+1;
            if(perturbation==2) reset_frames=reset_frames+1;
        end
    endtask

    initial begin
        blank(5); @(negedge clk); rst_n=1;
        blank(5);
        if(FULL) begin
            for(k=0;k<6;k=k+1) frame(1,PIXELS,0);
            frame(3,PIXELS,0);
            frame(2,PIXELS,0);
            frame(0,PIXELS,0);
        end else begin
            for(k=0;k<38;k=k+1) frame(1,PIXELS,0);
            if(max_strength!=8) $fatal(1,"mixed scene did not reach maximum strength");
            for(k=0;k<70;k=k+1) frame(0,PIXELS,0);
            if(actual!=0) $fatal(1,"uniform scene did not leave enhancement");
            for(k=0;k<36;k=k+1) frame(2,PIXELS,0);
            for(k=0;k<12;k=k+1) begin
                frame(k%6,PIXELS,0);
                frame(1,PIXELS-64,0);
                frame(1,PIXELS+64,0);
            end
            frame(1,PIXELS,1);
            enable=0; frame(1,PIXELS,0); frame(0,PIXELS,0);
            enable=1; frame(1,PIXELS,0);
            frame(1,PIXELS,2);
            for(k=0;k<10;k=k+1) frame(1,PIXELS,0);
        end
        frame(0,PIXELS,0);
        blank(6);
        if(valid_frames==0 || max_strength==0) $fatal(1,"coverage did not exercise enhancement");
        $display("PASS region_timing width=%0d height=%0d cycles=%0d checks=%0d frames=%0d valid_frames=%0d min_sample_gap=%0d max_strength=%0d changes=%0d short_frames=%0d long_frames=%0d mid_switch_frames=%0d reset_frames=%0d",W,H,cycles,checks,frames,valid_frames,min_sample_gap,max_strength,changes,short_frames,long_frames,mid_switch_frames,reset_frames);
        $finish;
    end
endmodule
'''


def decode(data: bytes) -> str:
    """Icarus输出以UTF-8保存，避免依赖控制台的GBK编码。"""
    return data.decode("utf-8", errors="replace")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    source = ROOT / "user_source/hdl_source/fixed_n1_lift.v"
    reference = subprocess.check_output(
        ["git", "show", "38413764adee46320d03507684ba582ea9073d10:user_source/hdl_source/fixed_n1_lift.v"], cwd=ROOT
    ).decode("utf-8")
    reference = reference[reference.index("module adaptive_n1_control #("):]
    reference = reference.replace("module adaptive_n1_control #(", "module reference_adaptive_n1_control #(", 1)
    reference_file = out / "reference_region_control.v"
    reference_file.write_text(reference, encoding="utf-8", newline="\n")
    summary = {
        "pass": False,
        "scope": "当前区域三拍归约与3841376原控制器逐周期O_strength及帧末极值/门限对照；不执行TD编译",
        "reference_commit": subprocess.check_output(["git", "rev-parse", "3841376"], cwd=ROOT).decode().strip(),
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "reference_sha256": hashlib.sha256(reference_file.read_bytes()).hexdigest(),
        "sample_log2": 6,
        "cases": {},
    }
    try:
        for name, width, height, full in (("small", 128, 12, 0), ("full720p", 1280, 720, 1)):
            folder = out / name
            folder.mkdir(parents=True, exist_ok=True)
            bench = folder / "tb.v"
            binary = folder / "tb.vvp"
            bench.write_text(BENCH.replace("@WIDTH@", str(width)).replace("@HEIGHT@", str(height)).replace("@FULL@", str(full)), encoding="utf-8", newline="\n")
            compiled = subprocess.run(
                [str(IVERILOG), "-g2012", "-Wall", "-s", "tb", "-o", str(binary), str(bench), str(source), str(reference_file)],
                cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
            )
            (folder / "compile.log").write_text(decode(compiled.stdout), encoding="utf-8")
            if compiled.returncode:
                raise RuntimeError("仿真编译失败：" + name + "\n" + decode(compiled.stdout))
            run = subprocess.run([str(IVERILOG.with_name("vvp.exe")), str(binary)], cwd=ROOT,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
            output = decode(run.stdout)
            (folder / "simulation.log").write_text(output, encoding="utf-8")
            print(output, end="", flush=True)
            if run.returncode or "PASS region_timing" not in output:
                raise RuntimeError("区域时序等价仿真失败：" + name)
            fields = dict((key, int(value)) for key, value in re.findall(r"(\w+)=(\d+)", output.split("PASS region_timing", 1)[1]))
            summary["cases"][name] = {"pass": True, **fields}
        summary["pass"] = True
    except Exception as error:
        summary["error"] = str(error)
    (out / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
