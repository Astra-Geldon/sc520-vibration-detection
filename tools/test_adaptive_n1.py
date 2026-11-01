#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""验证自适应N1的基线、单调性和高光旁路，不调用TD。"""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
IVERILOG = Path(r"C:\Users\lenovo\AppData\Local\iverilog\bin\iverilog.exe")
VVP = IVERILOG.with_name("vvp.exe")

BENCH = r'''
`timescale 1ns/1ps
module tb;
    reg de=1, en=1;
    reg [23:0] data=0;
    reg [7:0] peak=0;
    reg [3:0] strength=0;
    wire [23:0] baseline, adaptive;
    integer p, s, v, last;
    fixed_n1_lift u_baseline(.I_de(de), .I_enable(en), .I_data(data),
        .I_peak(peak), .I_extra_strength(4'd0), .O_data(baseline));
    fixed_n1_lift #(.ADAPTIVE(1)) u_adaptive(.I_de(de), .I_enable(en), .I_data(data),
        .I_peak(peak), .I_extra_strength(strength), .O_data(adaptive));
    initial begin
        for (s=0; s<=8; s=s+1) begin
            strength=s; last=0;
            for (p=0; p<256; p=p+1) begin
                peak=p; data={8'(p),8'(p),8'(p)}; #1;
                if (s==0 && adaptive!==baseline) $fatal(1,"strength0基线改变 peak=%0d",p);
                if (p>0 && adaptive[23:16] < last) $fatal(1,"灰阶反转 strength=%0d peak=%0d",s,p);
                if (adaptive[23:16] > 192 && p<192) $fatal(1,"中暗部越过高光上限");
                last=adaptive[23:16];
            end
        end
        for (p=192; p<256; p=p+1) begin
            peak=p; strength=8;
            for (v=0; v<=p; v=v+17) begin
                data={8'(p),8'(v),8'(v/2)}; #1;
                if (adaptive!==data) $fatal(1,"高光旁路改变 peak=%0d sub=%0d",p,v);
            end
        end
        de=0; data=24'h123456; peak=8'd64; strength=8; #1;
        if (adaptive!==data) $fatal(1,"消隐未旁路");
        en=0; de=1; #1;
        if (adaptive!==data) $fatal(1,"关闭未旁路");
        $display("PASS adaptive_n1: strength0基线、0..8单调、高光恒等、旁路");
        $finish;
    end
endmodule
'''


def main() -> int:
    if not IVERILOG.exists() or not VVP.exists():
        raise SystemExit("缺少Icarus Verilog：" + str(IVERILOG))
    with tempfile.TemporaryDirectory(prefix="adaptive_n1_") as folder:
        folder = Path(folder)
        tb = folder / "tb.v"
        binary = folder / "tb.vvp"
        tb.write_text(BENCH, encoding="utf-8", newline="\n")
        compile_run = subprocess.run(
            [str(IVERILOG), "-g2012", "-Wall", "-s", "tb", "-o", str(binary),
             str(tb), str(ROOT / "user_source/hdl_source/fixed_n1_lift.v")],
            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        if compile_run.returncode:
            print(compile_run.stdout.decode("mbcs", errors="replace"), end="")
            return compile_run.returncode
        run = subprocess.run([str(VVP), str(binary)], cwd=ROOT,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        output = run.stdout.decode("mbcs", errors="replace")
        print(output, end="")
        return run.returncode if run.returncode else (0 if "PASS adaptive_n1" in output else 1)


if __name__ == "__main__":
    raise SystemExit(main())
