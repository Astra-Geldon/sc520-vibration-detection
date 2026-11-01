"""Exercise real SDA/SCL for frame-aligned boot parameters and bounded NACK recovery.

The independent open-drain register-map slave is a simulation, not a measured
SC520. It deliberately rejects selected bytes instead of silently storing them.
No FPGA, serial port or capture device is accessed.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

BENCH = r'''
`timescale 1ns/1ps
module tb;
parameter integer CASE=0;
reg clk=0,rst_n=0,byteclk=0;
always #21 clk=~clk;
always #5 byteclk=~byteclk;
wire req,protect_applied,protect_pending,protect_valid;wire[15:0] ae,ag;
wire scl,cfg,ae_done,error;wire[15:0] id;
tri1 sda;
reg slave_low=0;
assign sda=slave_low?1'b0:1'bz;
wire S_csi_rx_clk=byteclk,S_24m_clk=clk,S_rst_n=rst_n,S_cam_i2c_ready=rst_n;
reg S_csi_frame_start=0;
__REAL_FRAME_CDC__
ae_set control(.I_auto_en(1'b0),.I_freeze(1'b0),.I_measure(6'b0),.I_measure_valid(1'b0),.I_clk(clk),.I_rst(!rst_n),.I_protect_en(1'b1),.I_ae_cfg_done(ae_done),
 .I_cam_cfg_done(cfg),.O_ae_req(req),.O_ae(ae),.O_ag(ag),
 .O_protect_applied(protect_applied),.O_pending(protect_pending),.O_valid(protect_valid));
uicfgcs520 #(.CLK_DIV(237)) dut(
 .I_clk(clk),.I_rst_n(rst_n),.I_frame_tick(S_cam_frame_tick),
 .I_ae_req(req),.I_ae(ae),.I_ag(ag),.O_cam_scl(scl),.IO_cam_sda(sda),
 .O_cfg_done(cfg),.O_ae_cfg_done(ae_done),.O_sensor_id(id),
 .O_sensor_id_ok(),.O_iic_error(error));
integer st=0,bits=0,ack_half=0,phase=0,read_mode=0,address_ok=0;
integer tx_byte=0,write_count=0,read_count=0,groups=0,rejected=0;
integer frames=0,ticks=0,first_group_frame=-1,release_frame=-1,group_writes=0;
integer requests=0,k;
reg[7:0] rx=0;reg[15:0] pointer=0;
reg[7:0] mem[0:65535];
reg stream_on=0;
time stream_time=0,hold_time=0;
function[15:0] fault_address;
 input integer n;
 begin case(n)
  1:fault_address=16'h3812;2:fault_address=16'h3e00;
  3:fault_address=16'h3e01;4:fault_address=16'h3e02;
  5:fault_address=16'h3e09;6:fault_address=16'h3e06;
  7:fault_address=16'h3e07;8:fault_address=16'h3812;
  9:fault_address=16'h3306;10:fault_address=16'h3e01;
  default:fault_address=16'hffff;
 endcase end
endfunction
initial begin
 wait(stream_on);
 // Start the real video source after stream-on; FS is shorter than I_clk.
 #2000000;
 forever begin
  if(CASE!=11)begin
   @(negedge byteclk);S_csi_frame_start=1;frames=frames+1;
   @(negedge byteclk);S_csi_frame_start=0;
  end
  #16666657;
 end
end
always @(negedge clk)if(rst_n)begin
 if(S_cam_frame_tick)ticks=ticks+1;
 if(req)requests=requests+1;
end
initial begin
 for(k=0;k<65536;k=k+1)mem[k]=0;
 mem[16'h3107]=8'hee;mem[16'h3108]=8'h4b;
 #1;rst_n=1;#1;rst_n=0;#100;rst_n=1;
 wait(cfg);wait(!ae_done);
 if(CASE==10)begin
  wait(dut.state==11);repeat(1000)@(negedge clk);
  if(cfg||ae_done||groups!=3||rejected!=3||!error)$fatal(1,"permanent fault not bounded");
  if(protect_valid||!protect_pending)$fatal(1,"failed group reported applied");
 end else if(CASE==11)begin
  #100000000;
  if(groups||ae_done||frames||ticks)$fatal(1,"wrote without a real frame");
  if(protect_valid||!protect_pending)$fatal(1,"unsettled request reported applied");
 end else begin
  wait(ae_done);repeat(30)@(negedge clk);
  if(id!==16'hee4b||ae!==900||ag!==128||!cfg)$fatal(1,"bad requested parameters");
  if(!protect_applied||!protect_valid||protect_pending)$fatal(1,"settled protection status missing");
  if(mem[16'h3e00]!==0||mem[16'h3e01]!==8'h38||mem[16'h3e02]!==8'h40||
     mem[16'h3e09]!==8'h0b||mem[16'h3e06]!==0||mem[16'h3e07]!==8'hc0||
     mem[16'h3812]!==8'h30)$fatal(1,"wrong actual register map");
  if(first_group_frame<3||frames-release_frame<2)$fatal(1,"frame placement/settling missing");
  if(read_count!=2||requests!=1)$fatal(1,"extra readback/request");
  if(CASE==0)begin
   if(groups!=1||rejected||error||write_count!=173)$fatal(1,"clean startup changed");
  end else if(CASE==9)begin
   if(groups!=1||rejected!=1||!error||write_count!=174)$fatal(1,"init retry failed");
  end else if(groups!=2||rejected!=1||!error||write_count!=181)
   $fatal(1,"group retry failed groups%0d writes%0d reject%0d",groups,write_count,rejected);
  if(ticks!=frames)$fatal(1,"CDC lost/duplicated frame event");
 end
 $display("PASS case%0d writes%0d groups%0d rejected%0d frames%0d ticks%0d first_group_frame%0d stream_to_hold_ns%0t",CASE,write_count,groups,rejected,frames,ticks,first_group_frame,hold_time-stream_time);
 $finish;
end
initial begin #350000000;$fatal(1,"timeout case%0d cfg%b done%b state%0d",CASE,cfg,ae_done,dut.state);end
// Independent slave decodes the real external wires; a rejected byte is not
// stored. Neither the wrapper's busy nor its internal byte counters are mocked.
always @(negedge sda) if(scl===1'b1&&rst_n)begin
 st=1;bits=0;rx=0;phase=0;address_ok=0;ack_half=0;slave_low=0;
end
always @(posedge sda)if(scl===1'b1&&rst_n)begin st=0;slave_low=0;end
always @(posedge scl)if(rst_n)begin
 if(st==1)begin
  rx={rx[6:0],sda};
  if(bits==7)begin
   if(phase==0)begin address_ok=(rx==8'h6c||rx==8'h6d);read_mode=rx[0];phase=1;end
   else if(phase==1)begin pointer[15:8]=rx;phase=2;end
   else if(phase==2)begin pointer[7:0]=rx;phase=3;end
   else begin
    write_count=write_count+1;
    if(pointer==16'h3812&&rx==0)begin
     groups=groups+1;group_writes=0;
     if(groups==1)begin first_group_frame=frames;hold_time=$time;end
    end
    if((CASE>=1&&CASE<=8&&groups==1&&rejected==0&&pointer==fault_address(CASE)&&
         ((CASE==1&&rx==0)||(CASE==8&&rx==8'h30)||(CASE!=1&&CASE!=8)))||
       (CASE==9&&pointer==16'h3306&&rejected==0)||
       (CASE==10&&groups>0&&pointer==16'h3e01))begin
     address_ok=0;rejected=rejected+1;
     $display("NACK case%0d group%0d %h=%h",CASE,groups,pointer,rx);
    end else begin
     mem[pointer]=rx;
     if(pointer==16'h0100&&rx==1)begin stream_on=1;stream_time=$time;end
     if(pointer==16'h3812&&rx==8'h30)release_frame=frames;
    end
    pointer=pointer+1;
   end
   st=2;ack_half=0;bits=0;
  end else bits=bits+1;
 end else if(st==3)begin
  if(bits==7)begin st=4;bits=0;read_count=read_count+1;end
  else bits=bits+1;
 end else if(st==4)begin
  if(sda===0)begin pointer=pointer+1;tx_byte=mem[pointer];st=3;bits=0;end
  else st=5;
 end
end
always @(negedge scl)if(rst_n)begin
 if(st==2)begin
  if(!ack_half)begin slave_low=address_ok;ack_half=1;end
  else begin
   slave_low=0;ack_half=0;
   if(read_mode&&phase==1)begin tx_byte=mem[pointer];st=3;bits=0;slave_low=!tx_byte[7];end
   else begin st=1;bits=0;rx=0;end
  end
 end else if(st==3)slave_low=!tx_byte[7-bits];
 else slave_low=0;
end
endmodule
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    hdl = root / 'user_source/hdl_source'
    top = (hdl/'design_top_wrapper.v').read_text(encoding='utf-8')
    start = top.index('    reg S_cam_frame_toggle;')
    end = top.index('\n\t\t', start)
    cdc = top[start:end]
    assert 'S_cam_frame_sync[2] ^ S_cam_frame_sync[1]' in cdc
    names = ['uiisp_beta/ae_set.v','uics520_cfg/uicfgcs520.v',
             'uics520_cfg/SC520GainTbl.v','uics520_cfg/uics520regAE.v',
             'uics520_cfg/uics520reg_720p60.v','uics500_cfg/uii2c.v']
    files = [hdl/name for name in names]
    bound = files + [hdl/'design_top_wrapper.v']
    hashes = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
    bench = out/'startup_bit_tb.v'
    bench.write_text(BENCH.replace('__REAL_FRAME_CDC__', cdc), encoding='utf-8')
    iv = Path('C:/iverilog/bin/iverilog.exe')

    def run(case):
        binary = out/f'case{case}.vvp'
        compiled = subprocess.run([str(iv),'-g2012','-s','tb',f'-Ptb.CASE={case}',
            '-o',str(binary),str(bench)]+[str(p) for p in files],
            capture_output=True, text=True, errors='replace', timeout=60)
        assert compiled.returncode == 0, compiled.stderr
        result = subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],
            capture_output=True, text=True, errors='replace', timeout=300)
        (out/f'case{case}.log').write_text(compiled.stdout+compiled.stderr+result.stdout+result.stderr,encoding='utf-8')
        assert result.returncode == 0 and 'PASS ' in result.stdout, result.stdout+result.stderr
        return dict(case=case, passed=True, result=result.stdout.strip())

    summary = dict(pass_=False, hardware_accessed=False, real_bit_level_I2C_engine=True,
        limitation='Independent simulated register-map slave; real sensor internals, ACKs and applied image not measured',
        source_sha256=hashes, cases=[])
    try:
        with ThreadPoolExecutor(max_workers=3) as pool:
            for future in as_completed([pool.submit(run,n) for n in range(12)]):
                item = future.result()
                summary['cases'].append(item)
                print(item['result'], flush=True)
        assert hashes == {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in bound}
        summary['pass_'] = True
    except (AssertionError, OSError, subprocess.SubprocessError) as error:
        summary['error'] = str(error)
        print('FAIL', error, flush=True)
    summary['pass'] = summary.pop('pass_')
    summary['cases'].sort(key=lambda x:x['case'])
    (out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return 0 if summary['pass'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
