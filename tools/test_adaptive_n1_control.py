#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""验证4×3分区统计的启动、缓慢退出和均匀场景不触发。"""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
IVERILOG = Path(r"C:\Users\lenovo\AppData\Local\iverilog\bin\iverilog.exe")
VVP = IVERILOG.with_name("vvp.exe")

BENCH = r'''
`timescale 1ns/1ps
module tb;
    localparam integer W=128, H=12, N=24;
    reg clk=0; always #1 clk=~clk;
    reg rst_n=0, vs=0, de=0, enable=1;
    reg [23:0] data=0;
    wire [3:0] strength;
    integer x,y,k,max_strength;
    adaptive_n1_control #(.H_ACTIVE(W),.V_ACTIVE(H),.EXPECTED_SAMPLES(N),.SAMPLE_LOG2(6)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_vs(vs),.I_de(de),.I_enable(enable),
        .I_data(data),.O_strength(strength));
    task frame;
        input integer mixed;
        begin
            @(negedge clk); vs=1; de=0;
            @(posedge clk); #1; vs=0;
            for (y=0; y<H; y=y+1) begin
                for (x=0; x<W; x=x+1) begin
                    @(negedge clk); de=1;
                    if (mixed && x < 64) data=24'h202020;
                    else if (mixed) data=24'he0e0e0;
                    else data=24'h808080;
                    @(posedge clk); #1;
                end
            end
            @(negedge clk); de=0; data=0;
            @(posedge clk); #1;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        max_strength=0;
        for(k=0;k<12;k=k+1) begin frame(1); if(strength>max_strength) max_strength=strength; end
        if(max_strength==0) $fatal(1,"明暗分区连续帧未启动补亮");
        for(k=0;k<9;k=k+1) begin frame(0); if(strength>max_strength) max_strength=strength; end
        if(strength>=max_strength || strength>8) $fatal(1,"均匀场景未缓慢退出或越界");
        enable=0; frame(0); if(strength!==0) $fatal(1,"关闭算法未清零强度");
        $display("PASS adaptive_n1_control: 分区明暗启动、慢速退出、关闭清零");
        $finish;
    end
endmodule
'''


def main() -> int:
    if not IVERILOG.exists() or not VVP.exists():
        raise SystemExit("缺少Icarus Verilog：" + str(IVERILOG))
    with tempfile.TemporaryDirectory(prefix="adaptive_n1_control_") as folder:
        folder = Path(folder)
        tb = folder / "tb.v"
        binary = folder / "tb.vvp"
        tb.write_text(BENCH, encoding="utf-8", newline="\n")
        compiled = subprocess.run(
            [str(IVERILOG), "-g2012", "-Wall", "-s", "tb", "-o", str(binary),
             str(tb), str(ROOT / "user_source/hdl_source/fixed_n1_lift.v")],
            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        if compiled.returncode:
            print(compiled.stdout.decode("mbcs", errors="replace"), end="")
            return compiled.returncode
        run = subprocess.run([str(VVP), str(binary)], cwd=ROOT,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        output = run.stdout.decode("mbcs", errors="replace")
        print(output, end="")
        return run.returncode if run.returncode else (0 if "PASS adaptive_n1_control" in output else 1)


if __name__ == "__main__":
    raise SystemExit(main())
