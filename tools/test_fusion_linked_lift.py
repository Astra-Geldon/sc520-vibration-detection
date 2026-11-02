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
BASELINE = "d755598"
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
    reg [10:0] gains[0:255];
    integer frames=0, checks=0, transitions=0, k, previous;
    integer highest=0, entry_tests=0, invalid_tests=0, exposure_tests=0;
    integer shadow_value=32, exposure_perturb=0;
    fusion_lift_control #(.H_ACTIVE(W), .V_ACTIVE(H), .EXPECTED_SAMPLES(N),
        .SAMPLE_LOG2(6)) dut(
        .I_clk(clk), .I_rst_n(rst_n), .I_vs(vs), .I_de(de), .I_enable(enable),
        .I_data(data), .I_envelope_data(envelope_data),
        .I_exposure(exposure), .I_exposure_valid(exposure_valid),
        .O_strength(strength), .O_reference_exposure(reference_exposure),
        .O_reference_luma(reference_luma), .O_triggered(triggered));

    // 参考目标直接穷举17个强度，与RTL的串行比较状态机无关。
    function integer target;
        input integer baseline, current, reference_mean, raw_pixel;
        integer value, raw_luma, envelope_pixel, envelope_luma, candidate, allowance;
        begin
            envelope_pixel=(raw_pixel*gains[raw_pixel]+128)/256;
            raw_luma=raw_pixel/4;
            envelope_luma=envelope_pixel/4;
            allowance=(current>=baseline)?0:(16*(baseline-current))/current;
            if(allowance>16) allowance=16;
            value=0;
            if(raw_pixel>=8 && raw_pixel<=191 && envelope_luma>raw_luma)
                for(candidate=0;candidate<=16;candidate=candidate+1)
                    if(candidate<=allowance &&
                       raw_luma*16+(envelope_luma-raw_luma)*candidate<=reference_mean)
                        value=candidate;
            target=value;
        end
    endfunction

    task blank;
        input integer n;
        integer b;
        begin
            for(b=0;b<n;b=b+1) begin @(negedge clk); de=0; data=0; envelope_data=0; end
        end
    endtask

    task boundary;
        begin
            @(negedge clk); vs=1; de=0; data=0; envelope_data=0;
            @(negedge clk); vs=0;
            // 允许归约流水线与串行目标运算完成，但不追加有效像素。
            blank(128);
        end
    endtask

    task reset;
        begin
            @(negedge clk); rst_n=0; vs=0; de=0;
            blank(5);
            if(strength!==0 || triggered!==0 || reference_exposure!==0 || reference_luma!==0)
                $fatal(1,"复位未清零 strength=%0d triggered=%b ref=%0d",strength,triggered,reference_exposure);
            @(negedge clk); rst_n=1;
            boundary;
        end
    endtask

    // pattern=0均匀；1强反差；2满足迟滞hold但不满足enter。
    // hold图中每区4个样本，8个区有一个亮度4样本，一个区有亮度60样本，
    // 其余样本亮度36：区域均值最小28、最大42，亮差恰为14。
    task frame;
        input integer pattern, pixel_count;
        integer p,x,y,col,row,region,value,envelope_value,old_strength;
        begin
            old_strength=strength;
            for(p=0;p<pixel_count;p=p+1) begin
                @(negedge clk); de=1;
                x=p%W; y=(p/W)%H;
                col=x/64; row=y/4; region=row*4+col;
                case(pattern)
                    0: value=128;
                    1: value=(x<W/2)?shadow_value:224;
                    2: begin
                        value=144;
                        if((y%4)==0 && region<8) value=16;
                        if((y%4)==0 && region==8) value=240;
                    end
                    3:value=(x<W/2)?0:255;
                    4:begin
                        value=(x<W/2)?32:224;
                        if(x==0 && y==0) value=28;
                    end
                    5:value=shadow_value;
                    default:value=16;
                endcase
                data={8'(value),8'(value),8'(value)};
                envelope_value=(value*gains[value]+128)/256;
                envelope_data={8'(envelope_value),8'(envelope_value),8'(envelope_value)};
                if(exposure_perturb && p==W*H/2) exposure=500;
                if(exposure_perturb && p==W*H/2+64) exposure=675;
            end
            blank(8);
            boundary;
            frames=frames+1;
            if(strength>16 || $isunknown({strength,triggered,reference_exposure,reference_luma}))
                $fatal(1,"强度越界或输出未知 frame=%0d",frames);
            if(enable && ((strength>old_strength+1)||(old_strength>strength+1)))
                $fatal(1,"逐帧强度跳变 frame=%0d old=%0d new=%0d",frames,old_strength,strength);
            if(strength!=old_strength) transitions=transitions+1;
            if(strength>highest) highest=strength;
            checks=checks+1;
        end
    endtask

    task steady;
        input integer current, raw_pixel, wanted;
        integer n,baseline,baseline_luma,last_strength;
        begin
            baseline=reference_exposure;
            baseline_luma=reference_luma;
            exposure=current;
            shadow_value=raw_pixel;
            boundary;
            last_strength=strength;
            for(n=0;n<24;n=n+1) begin
                frame(1,W*H);
                if(!triggered || reference_exposure!==baseline || reference_luma!==baseline_luma)
                    $fatal(1,"曝光变化重写触发参考 current=%0d ref=%0d expected=%0d",current,reference_exposure,baseline);
                if(n>1 && wanted>last_strength && strength<last_strength)
                    $fatal(1,"降曝后强度反向下降");
                if(n>1 && wanted<last_strength && strength>last_strength)
                    $fatal(1,"恢复曝光后强度反向上升");
                last_strength=strength;
            end
            if(strength!==wanted || wanted!=target(baseline,current,baseline_luma,raw_pixel))
                $fatal(1,"曝光目标不符 ref=%0d E=%0d raw=%0d actual=%0d wanted=%0d oracle=%0d",baseline,current,raw_pixel,strength,wanted,target(baseline,current,baseline_luma,raw_pixel));
            exposure_tests=exposure_tests+1;
        end
    endtask

    initial begin
        $readmemh("baseline_n1_gains.hex",gains);
        reset;
        for(k=0;k<8;k=k+1) frame(1,W*H);
        if(triggered || strength!=0) $fatal(1,"SW5关闭仍启动补亮");
        enable=1;
        for(k=0;k<10;k=k+1) frame(0,W*H);
        if(triggered || strength!=0) $fatal(1,"SW5开启后均匀场景误启动");
        frame(1,W*H); frame(1,W*H);
        if(triggered || strength!=0) $fatal(1,"未满3个连续有效帧便启动");
        frame(1,W*H);
        if(!triggered || reference_exposure!=900 || reference_luma!=128)
            $fatal(1,"3帧强反差未锁存E900和中间调均值8的Q4");
        entry_tests=entry_tests+1;
        for(k=0;k<10;k=k+1) frame(1,W*H);
        if(strength!=0) $fatal(1,"曝光尚未下降便过量补亮");

        for(k=0;k<12;k=k+1) frame(2,W*H);
        if(!triggered || strength!=0 || reference_exposure!=900 || reference_luma!=128)
            $fatal(1,"hold迟滞区错误退出或修改参考");
        // 只改变E而图像未变，不能凭E比例凭空多补。
        steady(450,32,0);
        steady(450,20,16);
        steady(225,12,16);
        steady(900,32,0);
        steady(1200,40,0);
        steady(675,28,4);
        steady(899,32,0);
        steady(800,24,2);
        steady(900,20,0);
        steady(720,28,4);
        steady(600,24,8);
        steady(300,16,16);
        steady(225,4,0);
        steady(675,28,4);

        // 不完整帧不能改变启停状态、触发参考或稳定强度。
        frame(0,W*H-1);
        frame(0,W*H+W);
        if(!triggered || strength!=4 || reference_exposure!=900 || reference_luma!=128)
            $fatal(1,"短帧/长帧污染已触发状态");
        invalid_tests=invalid_tests+2;

        exposure_perturb=1;
        frame(1,W*H);
        exposure_perturb=0;
        if(!triggered || strength!=4 || reference_exposure!=900 || reference_luma!=128)
            $fatal(1,"帧中途曝光短暂改变仍被当作稳定曝光帧");
        invalid_tests=invalid_tests+1;

        exposure_valid=0; exposure=128;
        previous=strength;
        for(k=0;k<12;k=k+1) frame(1,W*H);
        if(strength!=previous || reference_exposure!=900 || reference_luma!=128)
            $fatal(1,"未确认生效的曝光改变强度或参考");
        invalid_tests=invalid_tests+1;
        exposure=675; exposure_valid=1;
        boundary;
        for(k=0;k<3;k=k+1) frame(1,W*H);

        for(k=0;k<7;k=k+1) begin
            frame(5,W*H);
            if(!triggered) $fatal(1,"退出未满8个有效非hold帧");
        end
        frame(5,W*H);
        if(triggered) $fatal(1,"8个有效非hold帧后仍未退出");
        if(strength!=3) $fatal(1,"退出瞬间应从4平滑下降至3");
        for(k=0;k<3;k=k+1) begin
            frame(1,W*H);
            if(triggered || reference_exposure!=0 || reference_luma!=0)
                $fatal(1,"上一场景渐退期间捕获了新参考");
        end
        if(strength!=0) $fatal(1,"剩余3档未按有效帧渐退至0");
        frame(1,W*H); frame(1,W*H); frame(1,W*H);
        if(!triggered || reference_exposure!=675 || reference_luma!=112)
            $fatal(1,"渐退完成后不能正常重建新的参考");
        entry_tests=entry_tests+1;
        for(k=0;k<20;k=k+1) frame(0,W*H);
        if(strength!=0) $fatal(1,"退出后补亮未平滑归零");

        enable=0; frame(1,W*H);
        if(triggered || strength!=0 || reference_exposure!=0 || reference_luma!=0)
            $fatal(1,"关闭未清理触发参考");
        enable=1; exposure=600; shadow_value=24;
        boundary;
        for(k=0;k<14;k=k+1) frame(1,W*H);
        if(!triggered || reference_exposure!=600 || reference_luma!=96 || strength!=0)
            $fatal(1,"重新开启未记录新的E600基线");
        entry_tests=entry_tests+1;
        enable=0; frame(1,W*H);
        enable=1; exposure_valid=0;
        for(k=0;k<8;k=k+1) frame(1,W*H);
        if(triggered || strength!=0 || reference_exposure!=0 || reference_luma!=0)
            $fatal(1,"无效曝光允许新触发");
        invalid_tests=invalid_tests+1;
        exposure_valid=1; exposure=127;
        for(k=0;k<5;k=k+1) frame(1,W*H);
        exposure=1992;
        for(k=0;k<5;k=k+1) frame(1,W*H);
        if(triggered || strength!=0) $fatal(1,"越界曝光允许新触发");
        invalid_tests=invalid_tests+2;
        exposure=600;
        boundary;
        for(k=0;k<8;k=k+1) frame(3,W*H);
        if(triggered || strength!=0 || reference_exposure!=0 || reference_luma!=0)
            $fatal(1,"没有中间调样本的黑白场景不应锁存补亮参考");
        invalid_tests=invalid_tests+1;
        reset;
        // 候选从第一个有效明暗冲突帧保存，参数写入期间暂停证据。
        exposure=900; shadow_value=32; exposure_valid=1; enable=1;
        boundary;
        frame(1,W*H);
        if(triggered) $fatal(1,"候选首帧提前确认触发");
        exposure_valid=0; exposure=675; shadow_value=28;
        for(k=0;k<5;k=k+1) frame(1,W*H);
        if(triggered || strength!=0) $fatal(1,"pending期间累计触发证据");
        exposure_valid=1; boundary;
        frame(1,W*H);
        if(triggered) $fatal(1,"只有两个有效enter帧便确认触发");
        frame(1,W*H);
        if(!triggered || reference_exposure!=900 || reference_luma!=128)
            $fatal(1,"pending后触发未保留第一次冲突帧的参考曝光/亮度");
        for(k=0;k<12;k=k+1) frame(1,W*H);
        if(strength!=target(900,675,128,28))
            $fatal(1,"跨pending触发后未按首帧亮度恢复");
        entry_tests=entry_tests+1;
        reset;
        // 非整数均值Q4需要向下取整，并会改变最终允许的补亮档位。
        exposure=900; shadow_value=32; enable=1; exposure_valid=1;
        boundary;
        frame(4,W*H); frame(4,W*H); frame(4,W*H);
        if(!triggered || reference_exposure!=900 || reference_luma!=127)
            $fatal(1,"非整数参考均值未正确向下取整 ref_luma=%0d",reference_luma);
        steady(675,28,3);
        entry_tests=entry_tests+1;
        reset;
        $display("PASS fusion_control frames=%0d checks=%0d transitions=%0d highest=%0d entry_tests=%0d exposure_tests=%0d invalid_tests=%0d",frames,checks,transitions,highest,entry_tests,exposure_tests,invalid_tests);
        $finish;
    end
    initial begin #10000000; $fatal(1,"融合控制仿真超时"); end
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
    reg [10:0] gains[0:255];
    integer s,p,v,k,last,checks=0,highlight_checks=0,zero_checks=0;
    integer er,eg,eb,rr,rg,rb;
    reg [23:0] expected_envelope, expected;
    reg [31:0] rng=32'h19a7806b;
    fusion_n1_envelope n1(.I_de(de), .I_enable(enable), .I_data(original),
        .I_peak(peak), .O_data(envelope));
    fusion_lift_blend blend(.I_de(de), .I_enable(enable), .I_original(original),
        .I_envelope(envelope), .I_strength(strength), .O_data(actual));

    function integer channel;
        input integer pixel, gain;
        integer value;
        begin
            value=(pixel*gain+128)/256;
            channel=(value>255)?255:value;
        end
    endfunction

    task check;
        input integer r,g,b;
        begin
            original={8'(r),8'(g),8'(b)};
            peak=(r>g)?((r>b)?r:b):((g>b)?g:b);
            er=channel(r,gains[peak]); eg=channel(g,gains[peak]); eb=channel(b,gains[peak]);
            expected_envelope={8'(er),8'(eg),8'(eb)};
            rr=(r*(16-strength)+er*strength+8)/16;
            rg=(g*(16-strength)+eg*strength+8)/16;
            rb=(b*(16-strength)+eb*strength+8)/16;
            expected={8'(rr),8'(rg),8'(rb)};
            if(!de || !enable) begin expected_envelope=original; expected=original; end
            #1;
            if(envelope!==expected_envelope)
                $fatal(1,"N1包络偏离基线 rgb=%06x actual=%06x expected=%06x",original,envelope,expected_envelope);
            if(actual!==expected)
                $fatal(1,"融合混合偏离整数参考 s=%0d rgb=%06x actual=%06x expected=%06x",strength,original,actual,expected);
            if(peak>=192) begin
                if(actual!==original) $fatal(1,"高光非逐位恒等");
                highlight_checks=highlight_checks+1;
            end
            if(strength==0) begin
                if(actual!==original) $fatal(1,"强度0未逐位复用原图");
                zero_checks=zero_checks+1;
            end
            if(de && enable && (actual[23:16]<r || actual[15:8]<g || actual[7:0]<b))
                $fatal(1,"补亮意外降低通道");
            checks=checks+1;
        end
    endtask

    initial begin
        $readmemh("baseline_n1_gains.hex",gains);
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
