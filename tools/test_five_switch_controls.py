"""Exercise physical-switch bounce, mailbox backpressure and stopped clocks."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

BENCH = r'''
`timescale 1ns/1ps
module tb;
reg src=0,dst=0,rst=0,run_dst=1,frames=1;
always #5 src=~src;
always #7 if(run_dst)dst=~dst;
reg[4:0] pins=31;
wire[4:0] stable,received;wire ready,valid;
reg[5:0] phase=0;
always @(posedge dst or negedge rst)
 if(!rst)phase<=0;else if(phase==22)phase<=0;else phase<=phase+1'b1;
wire apply=frames&&(phase==0);
demo_switch_debounce #(.DEBOUNCE_CYCLES(5)) debounce(
 .I_clk(src),.I_rst_n(rst),.I_async(pins),.O_state(stable),.O_valid(ready));
demo_control_cdc mailbox(.I_src_clk(src),.I_src_rst_n(rst),
 .I_src_data(stable),.I_src_valid(ready),.I_dst_clk(dst),.I_dst_rst_n(rst),
 .I_dst_apply(apply),.O_dst_data(received),.O_dst_valid(valid));
reg[4:0] before_data;
reg before_valid,can_apply;
integer commits=0,n,k;
always @(posedge dst)begin
 before_data=received;before_valid=valid;can_apply=apply;
 #1;
 if(rst&&((before_data!==received)||(before_valid!==valid)))begin
  if(!can_apply)$fatal(1,"control changed inside active frame");
  commits=commits+1;
 end
end
task cycles;input integer c;begin repeat(c)@(negedge src);end endtask
task expect_value;input[4:0] wanted;integer c;begin
 c=0;
 while((!valid||received!==wanted)&&c<300)begin cycles(1);c=c+1;end
 if(!valid||received!==wanted)$fatal(1,"latest stable request lost wanted%0d got%0d",wanted,received);
end endtask
initial begin
 #1;rst=1;#1;rst=0;cycles(4);rst=1;
 expect_value(31);
 // A brief excursion must not replace a stable mechanical position.
 pins=0;cycles(2);pins=31;cycles(12);
 if(stable!==31)$fatal(1,"bounce was accepted");
 for(n=0;n<32;n=n+1)begin
  pins=n;cycles(12);expect_value(n);
 end
 // Do not acknowledge while there are no frame boundaries.
 frames=0;cycles(30);before_data=received;
 pins=5;cycles(25);pins=28;cycles(25);
 if(received!==31)$fatal(1,"committed without a frame");
 frames=1;expect_value(28);
 // Destination clock may stop altogether; latest user request must survive.
 run_dst=0;cycles(10);pins=3;cycles(25);pins=18;cycles(25);
 if(received!==28)$fatal(1,"stopped destination changed");
 run_dst=1;expect_value(18);
 // A reset during backpressure resets both handshake endpoints cleanly.
 frames=0;pins=9;cycles(15);rst=0;cycles(4);
 if(valid||ready||received!==31)$fatal(1,"reset mismatch");
 pins=21;frames=1;rst=1;cycles(15);expect_value(21);
 $display("PASS controls: all32vectors bounce frame-boundary stopped-clock latest-request reset commits%0d",commits);
 $finish;
end
initial begin #200000;$fatal(1,"timeout");end
endmodule
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    rtl = root/'user_source/hdl_source/demo_switch_control.v'
    tb, binary = out/'controls_tb.v', out/'controls.vvp'
    tb.write_text(BENCH, encoding='utf-8')
    iv = Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin/iverilog.exe')
    build = subprocess.run([str(iv), '-g2012', '-s', 'tb', '-o', str(binary), str(tb), str(rtl)],
                           capture_output=True, text=True, errors='replace', timeout=60)
    (out/'compile.log').write_text(build.stdout+build.stderr, encoding='utf-8')
    assert build.returncode == 0, build.stderr
    run = subprocess.run([str(iv.with_name('vvp.exe')), str(binary)], capture_output=True,
                         text=True, errors='replace', timeout=60)
    (out/'simulation.log').write_text(run.stdout+run.stderr, encoding='utf-8')
    passed = run.returncode == 0 and 'PASS controls:' in run.stdout
    summary = dict(passed=passed, source_sha256=hashlib.sha256(rtl.read_bytes()).hexdigest(),
                   hardware_accessed=False, result=run.stdout.strip())
    (out/'summary.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
    print(run.stdout, flush=True)
    assert passed, run.stderr


if __name__ == '__main__':
    main()
