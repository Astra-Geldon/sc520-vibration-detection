"""Focused automatic-exposure/key protocol regression; no TD invocation."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess

CONTROL_BENCH = r'''
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,protect=1,auto_en=1,freeze=0,done=1,cfg=0,mvalid=0;
reg[5:0] measure=0;
wire req,applied,auto_applied,pending,valid;
wire[15:0] ae,ag;
integer requests=0,seq=0,wanted=0,expected=0,i=0,delta=0;
ae_set dut(.I_clk(clk),.I_rst(rst),.I_protect_en(protect),
 .I_auto_en(auto_en),.I_freeze(freeze),.I_measure(measure),.I_measure_valid(mvalid),
 .I_ae_cfg_done(done),.I_cam_cfg_done(cfg),.O_ae_req(req),.O_ae(ae),.O_ag(ag),
 .O_protect_applied(applied),.O_auto_applied(auto_applied),.O_pending(pending),.O_valid(valid));
reg[15:0] held_ae,held_ag;
reg was_waiting=0;
always @(negedge clk) if(!rst)begin
 if(req)begin
  requests=requests+1;
  if(valid || !pending)$fatal(1,"request incorrectly published as valid");
  held_ae=ae;held_ag=ag;was_waiting=1;
 end else if(was_waiting && !valid)begin
  if(ae!==held_ae || ag!==held_ag)$fatal(1,"payload changed in flight");
 end
 if(valid)was_waiting=0;
end
task cycles;input integer n;begin repeat(n)@(negedge clk);#1;end endtask
task packet;input[1:0] cls;begin
 seq=(seq+1)%16;measure={seq[3:0],cls};mvalid=1;cycles(4);
end endtask
task quiet;input integer n;begin
 cycles(12);if(requests!=n)$fatal(1,"unexpected request %0d expected%0d",requests,n);
end endtask
task ack;begin
 done=0;cycles(5);if(valid || !pending)$fatal(1,"busy group accepted");
 done=1;cycles(5);if(!valid || pending)$fatal(1,"real completion unacknowledged");
end endtask
task settling;begin packet(0);packet(0);packet(0);end endtask
task demand;
 input[1:0] cls;input integer value;input integer count;
 begin packet(cls);quiet(count-1);packet(cls);quiet(count);
  if(ae!=value || ag!=128)$fatal(1,"AE step %0d/%0d gain%0d",ae,value,ag);
 end
endtask
initial begin
 cycles(4);if(ae!=1990 || ag!=17 || valid || !pending)$fatal(1,"reset contract");
 rst=0;cycles(4);quiet(0);cfg=1;cycles(5);quiet(1);
 if(ae!=900 || ag!=128 || auto_applied || valid)$fatal(1,"auto startup");
 // A done signal which has never fallen cannot acknowledge the group.
 for(i=0;i<10;i=i+1)packet(1);
 quiet(1);if(valid)$fatal(1,"stuck-high done falsely acknowledged");
 ack();if(!auto_applied)$fatal(1,"auto mode not acknowledged");
 // Held measurement and stale busy packets cannot trigger exposure changes.
 quiet(1);settling();quiet(1);
 packet(1);packet(2);packet(0);packet(1);quiet(1);packet(3);packet(1);quiet(1);
 packet(1);quiet(2);if(ae!=956)$fatal(1,"dark increase expected956 got%0d",ae);
 ack();
 // Invalid/neutral samples reset direction; exact deadband does not drift.
 settling();for(i=0;i<10;i=i+1)begin packet(0);packet(3);end quiet(2);
 demand(2,897,3);ack();
 // Sweep real outputs through both clamps without forcing internal state.
 expected=897;wanted=3;
 while(expected<1991)begin
  settling();delta=expected/16;if(delta<1)delta=1;
  expected=expected+delta;if(expected>1991)expected=1991;
  wanted=wanted+1;demand(1,expected,wanted);ack();
 end
 settling();for(i=0;i<20;i=i+1)packet(1);quiet(wanted);
 while(expected>128)begin
  settling();delta=expected/16;if(delta<1)delta=1;
  expected=expected-delta;if(expected<128)expected=128;
  wanted=wanted+1;demand(2,expected,wanted);ack();
 end
 settling();for(i=0;i<20;i=i+1)packet(2);quiet(wanted);
 // Freeze consumes sequences; release requires three entirely new packets.
 freeze=1;for(i=0;i<20;i=i+1)packet(1);quiet(wanted);
 freeze=0;cycles(5);quiet(wanted);settling();quiet(wanted);
 wanted=wanted+1;demand(1,136,wanted);
 // Changes during a group do not mutate its parameter payload.
 auto_en=0;protect=0;packet(2);cycles(8);
 if(ae!=136 || ag!=128 || valid)$fatal(1,"in-flight mode change mutated payload");
 done=0;cycles(5);done=1;cycles(12);wanted=wanted+1;quiet(wanted);
 if(ae!=1991 || ag!=160 || auto_applied!==1)$fatal(1,"OFF target not queued after ACK");
 ack();if(auto_applied || applied)$fatal(1,"manual OFF ack");
 // Manual SW5 legacy semantics, including requesting latest mode while busy.
 protect=1;cycles(8);wanted=wanted+1;quiet(wanted);
 if(ae!=900 || ag!=128)$fatal(1,"manual protect target");
 auto_en=1;freeze=1;done=0;cycles(5);done=1;cycles(12);wanted=wanted+1;quiet(wanted);
 if(ae!=900 || ag!=128 || auto_applied)$fatal(1,"auto entry normalization while frozen");
 ack();if(!auto_applied)$fatal(1,"auto entry ack");
 protect=0;for(i=0;i<10;i=i+1)packet(1);quiet(wanted);
 freeze=0;cycles(4);settling();wanted=wanted+1;demand(1,956,wanted);
 // A failed/stuck controller cannot fabricate validity or spawn retries.
 done=0;cfg=0;for(i=0;i<40;i=i+1)packet(1);quiet(wanted);
 done=1;cycles(10);if(valid || !pending)$fatal(1,"done without camera config accepted");
 cfg=1;cycles(6);if(!valid || pending)$fatal(1,"recovered legal completion rejected");
 quiet(wanted);
 $display("PASS automatic exposure: %0d real requests, handshake, step/clamps, feedback settling, freeze, modes and failure",requests);
 $finish;
end
initial begin #1000000;$fatal(1,"controller timeout");end
endmodule
'''

KEY_BENCH = r'''
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,key_n=0;wire enable;
integer changes=0;reg old=1;
ae_key_toggle #(.DEBOUNCE_CYCLES(5)) dut(.I_clk(clk),.I_rst_n(rst_n),.I_key_n(key_n),.O_enable(enable));
always @(negedge clk)if(rst_n)begin if(enable!=old)changes=changes+1;old=enable;end
task cycles;input integer n;begin repeat(n)@(negedge clk);#1;end endtask
initial begin
 cycles(4);if(enable!==1)$fatal(1,"default AE must be on");
 rst_n=1;cycles(100);if(enable!==1 || changes!=0)$fatal(1,"held startup key toggled");
 key_n=1;cycles(20);
 repeat(8)begin key_n=0;cycles(2);key_n=1;cycles(2);end
 cycles(20);if(changes!=0)$fatal(1,"bounce toggled");
 key_n=0;cycles(30);if(enable!==0 || changes!=1)$fatal(1,"first press failed");
 cycles(200);if(changes!=1)$fatal(1,"held press repeated");
 key_n=1;cycles(2);key_n=0;cycles(30);if(changes!=1)$fatal(1,"release bounce armed press");
 key_n=1;cycles(20);key_n=0;cycles(20);
 if(enable!==1 || changes!=2)$fatal(1,"second press failed");
 $display("PASS K3: default ON, startup-held inhibition, bounce, release debounce and long press");$finish;
end
initial begin #100000;$fatal(1,"key timeout");end
endmodule
'''


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('validation/auto_exposure_20261101/control'))
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    iv=Path(shutil.which('iverilog') or 'C:/iverilog/bin/iverilog.exe')
    vvp=Path(shutil.which('vvp') or iv.with_name('vvp.exe'))
    cases=[]
    for name,source,rtl in [('control',CONTROL_BENCH,'uiisp_beta/ae_set.v'),('key',KEY_BENCH,'ae_key_toggle.v')]:
        bench=out/(name+'_tb.v');bench.write_text(source,encoding='utf-8')
        binary=out/(name+'.vvp')
        compiled=subprocess.run([str(iv),'-g2012','-s','tb','-o',str(binary),str(bench),str(root/'user_source/hdl_source'/rtl)],capture_output=True,text=True,timeout=60)
        log=compiled.stdout+compiled.stderr
        if compiled.returncode:raise AssertionError(log)
        run=subprocess.run([str(vvp),str(binary)],capture_output=True,text=True,timeout=60)
        log+=run.stdout+run.stderr;(out/(name+'.log')).write_text(log,encoding='utf-8')
        if run.returncode or 'PASS ' not in run.stdout:raise AssertionError(log)
        cases.append(dict(name=name,passed=True,result=run.stdout.strip()));print(run.stdout.strip(),flush=True)
    (out/'summary.json').write_text(json.dumps(dict(passed=True,td_run=False,cases=cases),indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
