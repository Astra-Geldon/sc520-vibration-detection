"""Check five-switch exposure selection with the real I2C engine and slave.

Reuses the independent SDA/SCL register-map slave from test_startup_sensor.
The simulated sensor is not a measurement of board registers or image quality.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

from test_startup_sensor import BENCH


DYNAMIC_PROGRAM = r'''
reg inject_nack=0, permanent_nack=0;
integer injected_group=0, completed=0;
reg valid_before=0;
always @(negedge clk) if(rst_n) begin
 if(req && (!protect_pending || protect_valid))
  $fatal(1,"request was prematurely reported applied");
 if(protect_valid && (!ae_done || !cfg))
  $fatal(1,"valid without controller completion");
 if(protect_valid && !valid_before)completed=completed+1;
 valid_before=protect_valid;
end
task stable_no_duplicates;
 input integer expected_requests,expected_groups;
 begin
  repeat(300)@(negedge clk);
  if(requests!=expected_requests || groups!=expected_groups)
   $fatal(1,"duplicates requests%0d/%0d groups%0d/%0d",requests,expected_requests,groups,expected_groups);
 end
endtask
task check_applied;
 input integer desired;
 begin
  // Give combinational pending a delta after an externally changed target.
  #1;wait(protect_valid && !protect_pending && protect_applied==desired[0]);
  repeat(4)@(negedge clk);
  if(protect_applied!==desired[0] || !ae_done || !cfg)
   $fatal(1,"incorrect acknowledged state");
  if(desired) begin
   if(ae!==900 || ag!==128 || mem[16'h3e00]!==0 ||
      mem[16'h3e01]!==8'h38 || mem[16'h3e02]!==8'h40 ||
      mem[16'h3e09]!==8'h0b || mem[16'h3e06]!==0 || mem[16'h3e07]!==8'hc0)
    $fatal(1,"protected parameters differ from accepted E900/G12");
  end else begin
   if(ae!==1991 || ag!==160 || mem[16'h3e00]!==0 ||
      mem[16'h3e01]!==8'h7c || mem[16'h3e02]!==8'h70 ||
      mem[16'h3e09]!==8'h0f || mem[16'h3e06]!==0 || mem[16'h3e07]!==8'hc0)
    $fatal(1,"reference parameters differ from archived E1991/G24");
  end
  if(mem[16'h3812]!==8'h30 || frames-release_frame<2)
   $fatal(1,"status published before held group/frame settling completed");
 end
endtask
initial begin
 for(k=0;k<65536;k=k+1)mem[k]=0;
 mem[16'h3107]=8'hee;mem[16'h3108]=8'h4b;
 #1;rst_n=1;#1;rst_n=0;#100;
 if(ae!==1990 || ag!==17 || protect_valid || !protect_pending)
  $fatal(1,"startup reset contract changed");
 protect_en=(CASE==21)?0:1;
 rst_n=1;
 if(CASE==21) begin
  // An OFF switch at startup must still perform a complete post-init group.
  check_applied(0);stable_no_duplicates(1,1);
 end else if(CASE==22) begin
  // OFF is requested during ON; ON is requested during the queued OFF group.
  wait(groups==1);repeat(30)@(negedge clk);protect_en=0;
  wait(requests==2);wait(groups==2);
  if(ae!==1991 || ag!==160)$fatal(1,"busy request not delivered");
  protect_en=1;repeat(20)@(negedge clk);protect_en=0;
  repeat(20)@(negedge clk);protect_en=1;
  check_applied(1);stable_no_duplicates(3,3);
  if(completed!=3)$fatal(1,"busy changes lost completion");
 end else if(CASE==23) begin
  // A brief departure and return before completion needs no duplicate group.
  wait(groups==1);protect_en=0;
  repeat(30)@(negedge clk);protect_en=1;
  check_applied(1);stable_no_duplicates(1,1);
 end else begin
  check_applied(1);stable_no_duplicates(1,1);
  if(CASE==25 || CASE==26)begin
   inject_nack=1;permanent_nack=(CASE==26);injected_group=2;
  end
  @(negedge clk);protect_en=0;
  if(CASE==26)begin
   wait(dut.state==11);repeat(300)@(negedge clk);
   if(protect_valid || !protect_pending || cfg || ae_done ||
      requests!=2 || groups!=4 || rejected!=3 || !error)
    $fatal(1,"permanent failure falsely acknowledged or retried without bound");
  end else begin
   check_applied(0);
   if(CASE==25)begin
    stable_no_duplicates(2,3);
    if(rejected!=1 || !error)$fatal(1,"transient NACK not exercised");
   end else begin
    stable_no_duplicates(2,2);
    @(negedge clk);protect_en=1;
    check_applied(1);stable_no_duplicates(3,3);
   end
  end
 end
 if(read_count!=2)$fatal(1,"unrequested sensor readback added");
 $display("PASS dynamic case%0d requests%0d groups%0d completed%0d rejected%0d frames%0d",CASE,requests,groups,completed,rejected,frames);
 $finish;
end
'''


HANDSHAKE_BENCH = r'''
`timescale 1ns/1ps
module tb;
reg clk=0,rst=0,protect_en=1,done=0,cfg=0;
always #5 clk=~clk;
wire req,applied,pending,valid;wire[15:0] ae,ag;
integer requests=0;
ae_set dut(.I_auto_en(1'b0),.I_freeze(1'b0),.I_measure(6'b0),.I_measure_valid(1'b0),.I_clk(clk),.I_rst(rst),.I_protect_en(protect_en),
 .I_ae_cfg_done(done),.I_cam_cfg_done(cfg),.O_ae_req(req),.O_ae(ae),.O_ag(ag),
 .O_protect_applied(applied),.O_pending(pending),.O_valid(valid));
always @(negedge clk)if(req)requests=requests+1;
task cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
initial begin
 #1;rst=1;#10;rst=0;cycles(4);
 cfg=1;done=1;cycles(30);
 // Initial done-high, including arbitrary controller acceptance latency,
 // must never be mistaken for completion of our launched group.
 if(valid || !pending || requests!=1 || ae!=900 || ag!=128)
  $fatal(1,"initial high mistaken for request ACK");
 done=0;cycles(30);
 if(valid || !pending)$fatal(1,"busy group published valid");
 cfg=0;done=1;cycles(30);
 if(valid || !pending || requests!=1)$fatal(1,"done without cfg accepted");
 cfg=1;cycles(4);
 if(!valid || pending || !applied)$fatal(1,"legal ACK not published");
 protect_en=0;cycles(10);
 if(valid || !pending || requests!=2 || ae!=1991 || ag!=160)
  $fatal(1,"reference request missing");
 // A stuck-high done signal must not acknowledge a subsequent group either.
 cycles(30);if(valid || requests!=2)$fatal(1,"stuck-high false ACK");
 done=0;cycles(3);done=1;cycles(4);
 if(!valid || pending || applied)$fatal(1,"reference ACK failed");
 cycles(100);if(requests!=2)$fatal(1,"unchanged switch duplicated request");
 $display("PASS request handshake: initial/stuck-high rejection, busy/failure status, real low-high completion");
 $finish;
end
initial begin #100000;$fatal(1,"handshake timeout");end
endmodule
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    hdl = root/'user_source/hdl_source'
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    compiler = Path('C:/iverilog/bin/iverilog.exe')
    names = ['uiisp_beta/ae_set.v', 'uics520_cfg/uicfgcs520.v',
             'uics520_cfg/SC520GainTbl.v', 'uics520_cfg/uics520regAE.v',
             'uics520_cfg/uics520reg_720p60.v', 'uics500_cfg/uii2c.v']
    files = [hdl/name for name in names]
    hashes = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    top = (hdl/'design_top_wrapper.v').read_text(encoding='utf-8')
    start = top.index('    reg S_cam_frame_toggle;')
    cdc = top[start:top.index('\n\t\t', start)]
    bench = BENCH.replace(".I_protect_en(1'b1)", '.I_protect_en(protect_en)')
    bench = bench.replace('wire req,protect_applied', 'reg protect_en=1;\nwire req,protect_applied')
    start = bench.index('initial begin\n for(k=0;')
    end = bench.index('initial begin #350000000;', start)
    bench = bench[:start] + DYNAMIC_PROGRAM + bench[end:]
    start = bench.index('    if((CASE>=1')
    end = bench.index('     address_ok=0;', start)
    bench = bench[:start] + '''    if(inject_nack && pointer==16'h3e01 && groups>=injected_group &&
       (permanent_nack || rejected==0))begin
''' + bench[end:]
    bench = bench.replace('#350000000;', '#750000000;')
    bench = bench.replace('__REAL_FRAME_CDC__', cdc)
    dynamic_file = out/'dynamic_sensor_tb.v'
    dynamic_file.write_text(bench, encoding='utf-8')
    handshake_file = out/'request_handshake_tb.v'
    handshake_file.write_text(HANDSHAKE_BENCH, encoding='utf-8')
    summary = dict(pass_=False, hardware_accessed=False, real_bit_level_I2C_engine=True,
                   source_sha256=hashes, cases=[])

    def run(label, source, parameters=()):
        binary = out/(label+'.vvp')
        compile_run = subprocess.run([str(compiler), '-g2012', '-s', 'tb', *parameters,
            '-o', str(binary), str(source), *[str(p) for p in files]],
            capture_output=True, text=True, errors='replace', timeout=60)
        log = compile_run.stdout+compile_run.stderr
        if compile_run.returncode:
            (out/(label+'.log')).write_text(log, encoding='utf-8')
            raise AssertionError(log)
        result = subprocess.run([str(compiler.with_name('vvp.exe')), str(binary)],
                                capture_output=True, text=True, errors='replace', timeout=300)
        log += result.stdout+result.stderr
        (out/(label+'.log')).write_text(log, encoding='utf-8')
        assert result.returncode == 0 and 'PASS ' in result.stdout, log
        return dict(case=label, pass_=True, result=result.stdout.strip())

    try:
        item = run('handshake', handshake_file)
        summary['cases'].append(item)
        print(item['result'], flush=True)
        with ThreadPoolExecutor(max_workers=3) as pool:
            futures = [pool.submit(run, f'dynamic{case}', dynamic_file, [f'-Ptb.CASE={case}'])
                       for case in [20, 21, 22, 23, 25, 26]]
            for future in as_completed(futures):
                item = future.result()
                summary['cases'].append(item)
                print(item['result'], flush=True)
        assert hashes == {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
        summary['pass_'] = True
    except (AssertionError, OSError, subprocess.SubprocessError) as error:
        summary['error'] = str(error)
        print('FAIL', error, flush=True)
    summary['pass'] = summary.pop('pass_')
    summary['cases'].sort(key=lambda x:x['case'])
    (out/'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    return 0 if summary['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
