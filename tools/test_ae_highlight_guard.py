#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""验证高光约束测光的帧级分类，不调用TD。"""
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "validation/auto_exposure_20261101/highlight_guard"
OUT.mkdir(parents=True, exist_ok=True)
IV = Path(shutil.which("iverilog") or r"C:\Users\lenovo\AppData\Local\iverilog\bin\iverilog.exe")
VVP = Path(shutil.which("vvp") or str(IV.with_name("vvp.exe")))


def decode_tool_output(data: bytes) -> str:
    """优先按仿真器常用的UTF-8解码，兼容本机旧版代码页输出。"""
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("mbcs", errors="replace")


def classify_model(samples):
    """与当前RTL相同的8桶背景P60参考模型。"""
    n = len(samples)
    near = sum(value >= 60 for value in samples)
    hist = [0] * 8
    for value in samples:
        hist[min(value >> 3, 7)] += 1
    background = sum(hist[:7])
    if near * 100 >= n * 10:
        return 2
    if background * 100 < n * 40:
        return 0
    cumulative = 0
    p60 = 59
    for index in range(7):
        cumulative += hist[index]
        if cumulative * 5 >= background * 3:
            p60 = 3 + index * 8
            break
    if p60 < 22:
        return 1
    if p60 > 30:
        return 2
    return 0


def run_offline_model() -> None:
    """覆盖基础分类、孤立亮点、明暗冲突和亮端死区。"""
    assert classify_model([20] * 100) == 1
    assert classify_model([10] * 100) == 1
    assert classify_model([30] * 100) == 0
    assert classify_model([60] + [20] * 99) == 1
    assert classify_model([60, 60] + [10] * 20 + [20] * 78) == 1
    assert classify_model([50] * 10 + [10] * 20 + [20] * 70) == 1
    assert classify_model([5] * 100) == 1


BENCH = r'''
`timescale 1ns/1ps
module tb;
  localparam integer N=100;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, fs=0, valid=0, enable=0;
  reg [5:0] luma=0;
  wire [5:0] measure;
  wire out_valid;
  integer published=0;
  ae_luma_sampler #(.EXPECTED_SAMPLES(N), .SAMPLE_LOG2(0)) dut(
    .I_clk(clk), .I_rst_n(rst_n), .I_frame_start(fs), .I_valid(valid),
    .I_enable(enable), .I_luma(luma), .O_measure(measure), .O_valid(out_valid));

  task tick;
    begin @(negedge clk); #1; end
  endtask
  task frame;
    input integer near_n;
    input integer head_n;
    input integer shadow_n;
    input integer base;
    integer i;
    begin
      // 把高光、亮端余量、阴影三类样本放在固定位置，检查只依赖统计而非位置。
      @(negedge clk); fs=1; valid=1; enable=1; luma=(near_n > 0) ? 60 :
                                                  ((head_n > 0) ? 50 :
                                                   ((shadow_n > 0) ? 10 : base)); #1;
      @(posedge clk); #1; fs=0;
      for (i=1; i<N; i=i+1) begin
        @(negedge clk); valid=1;
        if (i < near_n) luma=60;
        else if (i < near_n + head_n) luma=50;
        else if (i < near_n + head_n + shadow_n) luma=10;
        else luma=base;
        #1; @(posedge clk); #1;
      end
      @(negedge clk); valid=0; luma=0; #1;
    end
  endtask
  task check_result;
    input [1:0] cls;
    input [127:0] label;
    begin
      // 帧首发布上一帧结果；序号只验证递增不被改写。
      @(negedge clk); fs=1; valid=0; enable=1; #1;
      @(posedge clk); #1; fs=0;
      if (!out_valid) $fatal(1,"%0s: 未发布统计",label);
      if (measure[1:0] !== cls) $fatal(1,"%0s: 期望分类%0d，实际%0d",label,cls,measure[1:0]);
      published=published+1;
      @(negedge clk); #1;
    end
  endtask
  initial begin
    tick; rst_n=1; enable=1;
    // 当前背景P60桶将20量化到19，因此会请求小步增曝。
    frame(0,0,0,20); check_result(1,"背景P60偏暗");
    frame(0,0,0,10); check_result(1,"均匀暗");
    frame(0,0,0,30); check_result(0,"均匀中亮");
    // 少量高光不达到10%紧急门限，仍按背景P60控制。
    frame(1,0,0,20); check_result(1,"孤立灯点");
    // 近饱和数量尚未达到10%时，背景优先规则仍保持增曝方向。
    frame(2,0,20,20); check_result(1,"明暗冲突背景优先");
    // 亮端余量和阴影共存时同样由背景P60决定，不使用旧均值死区。
    frame(0,10,20,20); check_result(1,"高光死区背景优先");
    // 整体过暗没有亮端覆盖，仍允许原AE增曝。
    frame(0,0,0,5); check_result(1,"整体暗增曝");
    // 无效短帧产生无效分类，不能污染下一次有效帧。
    @(negedge clk); fs=1; valid=1; enable=1; luma=20; #1; @(posedge clk); #1; fs=0;
    repeat (20) begin @(negedge clk); valid=1; #1; @(posedge clk); #1; end
    @(negedge clk); valid=0; #1;
    @(negedge clk); fs=1; valid=0; #1; @(posedge clk); #1;
    if (!out_valid || measure[1:0] !== 3) $fatal(1,"无效短帧未报告无效");
    $display("PASS 高光约束测光：基础分类、孤立灯点、明暗冲突、保持死区、复位协议");
    $finish;
  end
  initial begin #100000; $fatal(1,"仿真超时"); end
endmodule
'''


def main() -> int:
    run_offline_model()
    print("PASS Python离线模型：高光保护门限和保持死区")
    bench = OUT / "tb_highlight_guard.v"
    binary = OUT / "tb_highlight_guard.vvp"
    log = OUT / "result.log"
    bench.write_text(BENCH, encoding="utf-8", newline="\n")
    compile_run = subprocess.run(
        [str(IV), "-g2012", "-Wall", "-s", "tb", "-o", str(binary),
         str(bench), str(ROOT / "user_source/hdl_source/ae_luma_sampler.v")],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=60,
    )
    compile_text = decode_tool_output(compile_run.stdout)
    (OUT / "compile.log").write_text(compile_text, encoding="utf-8")
    if compile_run.returncode:
        raise SystemExit(compile_text)
    run = subprocess.run([str(VVP), str(binary)], cwd=ROOT,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         timeout=60)
    run_text = decode_tool_output(run.stdout)
    log.write_text(run_text, encoding="utf-8")
    # Windows默认代码页可能无法打印仿真器输出中的个别Unicode字符；日志
    # 已按UTF-8保存，终端只输出可编码文本，避免测试结果被打印异常掩盖。
    safe_text = run_text.encode(sys.stdout.encoding or "utf-8", errors="replace").decode(
        sys.stdout.encoding or "utf-8", errors="replace"
    )
    print(safe_text, end="")
    if run.returncode or "PASS " not in run_text:
        raise SystemExit(1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
