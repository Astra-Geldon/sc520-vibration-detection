"""Compare fixed E900/G12 sensor initialization with archived b8407f8.

The real config FSM/tables and AE controller run against an I2C transaction
model. Every initialization/grouped write and its acceptance cycle must match;
only the six experimental post-group readbacks are removed. No hardware access.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys


MODEL = r'''
`timescale 1ns/1ps
module uii2c #(parameter WMEN_LEN=4,RMEN_LEN=1,CLK_DIV=239)(
 input I_clk,I_rstn,output O_iic_scl,inout IO_iic_sda,
 input[WMEN_LEN*8-1:0] I_wr_data,input[7:0] I_wr_cnt,
 output reg[RMEN_LEN*8-1:0] O_rd_data,input[7:0] I_rd_cnt,
 input I_iic_req,I_iic_mode,output reg O_iic_busy,output reg O_iic_bus_error,
 output IO_iic_sda_dg);
 assign O_iic_scl=1;assign IO_iic_sda=1'bz;assign IO_iic_sda_dg=IO_iic_sda;
 reg[15:0] sensor_id=16'hee4b;
 integer error_transaction=-1,stall_transaction=-1;
 reg[7:0] mem[0:65535];
 reg[31:0] trace_data[0:255];reg trace_mode[0:255];integer trace_cycle[0:255];
 integer cycles=0,left=0,transactions=0,writes=0,reads=0,groups=0;
 integer reset_release_cycle=-1,second_write_cycle=-1;
 reg[15:0] address;reg[7:0] value;reg mode;integer active_transaction,k;
 initial for(k=0;k<65536;k=k+1)mem[k]=0;
 always @(posedge I_clk or negedge I_rstn)begin
  if(!I_rstn)begin
   O_iic_busy<=0;O_iic_bus_error<=0;O_rd_data<=0;left<=0;
   cycles<=0;transactions<=0;writes<=0;reads<=0;groups<=0;
   reset_release_cycle<=-1;second_write_cycle<=-1;
  end else begin
   cycles<=cycles+1;O_iic_bus_error<=0;
   if(!O_iic_busy&&I_iic_req)begin
    if(I_wr_data[7:0]!==8'h6c)$fatal(1,"sensor device address");
    if(I_iic_mode?(I_wr_cnt!==3||I_rd_cnt!==1):(I_wr_cnt!==4||I_rd_cnt!==0))
     $fatal(1,"transaction lengths");
    trace_data[transactions]<=I_wr_data;trace_mode[transactions]<=I_iic_mode;
    trace_cycle[transactions]<=cycles;active_transaction=transactions;
    address={I_wr_data[15:8],I_wr_data[23:16]};value=I_wr_data[31:24];mode=I_iic_mode;
    transactions<=transactions+1;O_iic_busy<=1;
    left<=7+(transactions%5)+((transactions==stall_transaction)?300:0);
    if(I_iic_mode)reads<=reads+1;
    else begin
     writes<=writes+1;
     if(writes==1)second_write_cycle<=cycles;
     if(address==16'h3812&&value==0)groups<=groups+1;
    end
   end else if(O_iic_busy)begin
    if(left==0)begin
     O_iic_busy<=0;
     if(active_transaction==error_transaction)O_iic_bus_error<=1;
     if(mode)begin
      case(address)
       16'h3107:O_rd_data<=sensor_id[15:8];
       16'h3108:O_rd_data<=sensor_id[7:0];
       default:O_rd_data<=mem[address];
      endcase
     end else begin
      mem[address]<=value;
      if(address==16'h0103&&value==1)reset_release_cycle<=cycles;
     end
    end else left<=left-1;
   end
  end
 end
endmodule
'''


INTEGRATED = r'''
`timescale 1ns/1ps
module tb;
parameter integer CASE=0;
reg clk=0,rstn=0;always #5 clk=~clk;
wire[1:0] req,cfg,done,error,idok;
wire[15:0] ae[0:1],ag[0:1],id[0:1];wire[1:0] scl;tri1 sda0,sda1;
wire[1:0] gray;wire verified;
integer cycles=0,requests0=0,requests1=0,k;
ae_set control(.I_auto_en(1'b0),.I_freeze(1'b0),.I_measure(6'b0),.I_measure_valid(1'b0),.I_clk(clk),.I_rst(!rstn),.I_ae_cfg_done(done[0]),.I_cam_cfg_done(cfg[0]),
 .O_ae_req(req[0]),.O_ae(ae[0]),.O_ag(ag[0]));
ae_set_legacy #(.EXP_RST(3),.GAIN_COMPARE_EN(1),.GAIN_RST(1),.GAIN12_EN(1)) old_control(
 .I_clk(clk),.I_rst(!rstn),.I_btn(4'b1111),.I_exp_key_n(1'b1),
 .I_ae_cfg_done(done[1]),.I_cam_cfg_done(cfg[1]),.O_ae_req(req[1]),.O_ae(ae[1]),.O_ag(ag[1]));
uicfgcs520 camera(.I_clk(clk),.I_rst_n(rstn),.I_ae_req(req[0]),.I_ae(ae[0]),.I_ag(ag[0]),
 .O_cam_scl(scl[0]),.IO_cam_sda(sda0),.O_cfg_done(cfg[0]),.O_ae_cfg_done(done[0]),
 .O_sensor_id(id[0]),.O_sensor_id_ok(idok[0]),.O_iic_error(error[0]));
uicfgcs520_legacy #(.AE_VERIFY_EN(1)) old_camera(.I_clk(clk),.I_rst_n(rstn),
 .I_ae_req(req[1]),.I_ae(ae[1]),.I_ag(ag[1]),.O_cam_scl(scl[1]),.IO_cam_sda(sda1),
 .O_cfg_done(cfg[1]),.O_ae_cfg_done(done[1]),.O_sensor_id(id[1]),
 .O_sensor_id_ok(idok[1]),.O_iic_error(error[1]),.O_gain_sel_gray(gray),.O_gain_verified(verified));
always @(negedge clk)if(rstn)begin
 cycles=cycles+1;
 if({req[0],ae[0],ag[0]}!=={req[1],ae[1],ag[1]})$fatal(1,"AE controller changed cycle%0d",cycles);
 if(cfg[0]!==cfg[1]||idok[0]!==idok[1]||id[0]!==id[1])$fatal(1,"initialization status changed");
 if(req[0])requests0=requests0+1;if(req[1])requests1=requests1+1;
 if(cycles>1500000)$fatal(1,"timeout");
end
initial begin
 if(CASE==1)begin camera.u_i2c.sensor_id=16'h9e4b;old_camera.u_i2c.sensor_id=16'h9e4b;end
 if(CASE==2)begin camera.u_i2c.sensor_id=16'h1234;old_camera.u_i2c.sensor_id=16'h1234;end
 if(CASE==3)begin camera.u_i2c.error_transaction=2;old_camera.u_i2c.error_transaction=2;end
 if(CASE==4)begin camera.u_i2c.stall_transaction=77;old_camera.u_i2c.stall_transaction=77;end
 #1;rstn=1;#1;rstn=0;repeat(4)@(negedge clk);rstn=1;
 if(CASE==2)begin
  repeat(1000)@(negedge clk);
  if(cfg!==0||idok!==0||done!==0||requests0||requests1)$fatal(1,"bad ID accepted");
  if(camera.u_i2c.writes||old_camera.u_i2c.writes)$fatal(1,"wrote after bad ID");
  if(camera.u_i2c.reads!==2||old_camera.u_i2c.reads!==2)$fatal(1,"bad ID reads");
 end else begin
  wait(old_camera.u_i2c.reads==8);wait(done[1]);repeat(30)@(negedge clk);
  if(cfg!==3||done!==3||idok!==3)$fatal(1,"configuration not complete");
  if(requests0!==1||requests1!==1||ae[0]!==900||ag[0]!==128)$fatal(1,"mandatory grouped startup request missing/repeated");
  if(camera.u_i2c.writes!==173||old_camera.u_i2c.writes!==173)$fatal(1,"165 init +8 group writes required");
  if(camera.u_i2c.groups!==1||old_camera.u_i2c.groups!==1)$fatal(1,"group write repeated/missing");
  if(camera.u_i2c.reads!==2||old_camera.u_i2c.reads!==8)$fatal(1,"removed only6 verification reads");
  for(k=0;k<175;k=k+1)begin
   if(camera.u_i2c.trace_data[k]!==old_camera.u_i2c.trace_data[k]||
      camera.u_i2c.trace_mode[k]!==old_camera.u_i2c.trace_mode[k]||
      camera.u_i2c.trace_cycle[k]!==old_camera.u_i2c.trace_cycle[k])
    $fatal(1,"transaction data/order/timing changed index%0d",k);
  end
  if(camera.u_i2c.second_write_cycle-camera.u_i2c.reset_release_cycle<119048)
   $fatal(1,"5ms software reset wait removed");
  if(camera.u_i2c.mem[16'h3e00]!==0||camera.u_i2c.mem[16'h3e01]!==8'h38||
     camera.u_i2c.mem[16'h3e02]!==8'h40||camera.u_i2c.mem[16'h3e09]!==8'h0b||
     camera.u_i2c.mem[16'h3e06]!==0||camera.u_i2c.mem[16'h3e07]!==8'hc0||
     camera.u_i2c.mem[16'h3812]!==8'h30)$fatal(1,"actual E900/G12 registers wrong");
  if(CASE==3)begin if(error!==3||verified!==0)$fatal(1,"I2C error not sticky");end
  else if(error!==0||verified!==1)$fatal(1,"unexpected error");
 end
 $display("PASS fixed_sensor case%0d cycles%0d writes%0d reads_new%0d reads_old%0d startup_requests%0d",CASE,cycles,camera.u_i2c.writes,camera.u_i2c.reads,old_camera.u_i2c.reads,requests0);$finish;
end
endmodule
'''


HANDSHAKE = r'''
`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,cam=0,done=0;always #5 clk=~clk;
wire req,newreq;wire[15:0] ae,ag,newae,newag;integer n=0,pulses=0,k;
ae_set uut(.I_auto_en(1'b0),.I_freeze(1'b0),.I_measure(6'b0),.I_measure_valid(1'b0),.I_clk(clk),.I_rst(rst),.I_ae_cfg_done(done),.I_cam_cfg_done(cam),
 .O_ae_req(newreq),.O_ae(newae),.O_ag(newag));
ae_set_legacy #(.EXP_RST(3),.GAIN_COMPARE_EN(1),.GAIN_RST(1),.GAIN12_EN(1)) refu(
 .I_clk(clk),.I_rst(rst),.I_btn(4'b1111),.I_exp_key_n(1'b1),
 .I_ae_cfg_done(done),.I_cam_cfg_done(cam),.O_ae_req(req),.O_ae(ae),.O_ag(ag));
always @(negedge clk)begin
 n=n+1;if({req,ae,ag}!=={newreq,newae,newag})$fatal(1,"handshake mismatch cycle%0d",n);
 if(newreq)begin if(!done||!cam||newae!==900||newag!==128)$fatal(1,"early/malformed startup request");pulses=pulses+1;end
end
initial begin
 #1;rst=0;#1;rst=1;repeat(4)@(negedge clk);rst=0;
 repeat(50)@(negedge clk);cam=1;repeat(50)@(negedge clk);
 if(pulses)$fatal(1,"request before AE ready");done=1;
 repeat(30)@(negedge clk);if(pulses!==1)$fatal(1,"startup pulse count");
 for(k=0;k<20;k=k+1)begin @(posedge clk);cam=~cam;done=~done;repeat(10)@(negedge clk);end
 if(pulses!==1)$fatal(1,"duplicate request on cfg/done toggles");
 rst=1;cam=0;done=0;repeat(4)@(negedge clk);rst=0;
 repeat(20)@(negedge clk);if(newae!==1990||newag!==17)$fatal(1,"reset output changed");
 cam=1;done=1;repeat(10)@(negedge clk);if(pulses!==2)$fatal(1,"no request after reset");
 $display("PASS fixed_handshake cycles%0d startup_pulses%0d",n,pulses);$finish;
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
    iv = Path('C:/iverilog/bin/iverilog.exe')
    hdl = root / 'user_source/hdl_source'
    if 'I_frame_tick' in (hdl/'uics520_cfg/uicfgcs520.v').read_text(encoding='utf-8'):
        # The old same-cycle comparison predates the intentional startup wait.
        # Exercise the current real bit engine instead of hanging without FS.
        return subprocess.call([sys.executable, str(root/'tools/test_startup_sensor.py'),
                                '--output', str(out)])
    names = ['uiisp_beta/ae_set.v', 'uics520_cfg/uicfgcs520.v',
             'uics520_cfg/SC520GainTbl.v', 'uics520_cfg/uics520regAE.v',
             'uics520_cfg/uics520reg_720p60.v']
    files = [hdl/name for name in names]
    summary = {'pass': False, 'scope': 'Fixed E900/G12 initialization/group write equivalence; only6 test readbacks removed',
               'reference_commit': 'b8407f8', 'source_sha256': {}, 'tests': {},
               'hardware_accessed': False, 'bit_level_I2C_signalling_tested': False}
    try:
        summary['source_sha256'] = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
        for rel in ['uics520_cfg/SC520GainTbl.v', 'uics520_cfg/uics520regAE.v',
                    'uics520_cfg/uics520reg_720p60.v', 'uics500_cfg/uii2c.v']:
            data = subprocess.check_output(['git','show','b8407f8:user_source/hdl_source/'+rel], cwd=root)
            assert data == (hdl/rel).read_bytes(), 'Required table/I2C engine changed: '+rel
        summary['required_tables_and_bit_level_engine_unchanged'] = True
        legacy = []
        for rel, name in zip(names[:2], ['ae_set','uicfgcs520']):
            data = subprocess.check_output(['git','show','b8407f8:user_source/hdl_source/'+rel], cwd=root)
            data = re.sub(rb'\bmodule\s+'+name.encode()+rb'\b', b'module '+name.encode()+b'_legacy', data, count=1)
            path = out/(name+'_legacy.v');path.write_bytes(data);legacy.append(path)
        (out/'i2c_model.v').write_text(MODEL, encoding='utf-8')
        def run(name, body, case=None):
            tb = out/(name+'.v');tb.write_text(body, encoding='utf-8')
            command = [str(iv),'-g2012','-s','tb','-o',str(out/(name+'.vvp'))]
            if case is not None:command += ['-Ptb.CASE='+str(case)]
            command += [str(tb),str(out/'i2c_model.v')]+[str(p) for p in files+legacy]
            build = subprocess.run(command,capture_output=True,text=True,errors='replace',timeout=60)
            (out/(name+'_compile.log')).write_text(build.stdout+build.stderr, encoding='utf-8')
            assert build.returncode == 0,build.stdout+build.stderr
            result = subprocess.run([str(iv.with_name('vvp.exe')),str(out/(name+'.vvp'))],capture_output=True,text=True,errors='replace',timeout=180)
            (out/(name+'.log')).write_text(result.stdout+result.stderr,encoding='utf-8')
            print(result.stdout+result.stderr,flush=True)
            assert result.returncode == 0 and 'PASS ' in result.stdout,name
            summary['tests'][name] = {'pass':True,'log':name+'.log'}
        run('handshake',HANDSHAKE)
        for case in range(5):run('integrated_case'+str(case),INTEGRATED,case)
        assert summary['source_sha256'] == {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
        summary.update(pass_=True, init_writes=165,group_writes=8,
                       exact_transaction_data_order_and_cycle_cases=4,
                       exact_transactions_per_success_case=175,
                       required_sensor_id_reads=2,removed_test_register_reads=6,
                       fixed_exposure=900,fixed_gain_code=128,nominal_gain=12,
                       fixed_sensor_registers={'3e00':'00','3e01':'38','3e02':'40','3e09':'0b','3e06':'00','3e07':'c0','3812':'30'})
        summary['pass'] = summary.pop('pass_')
    except (AssertionError,OSError,subprocess.SubprocessError) as error:
        summary['error'] = str(error)
        print('FAIL fixed sensor:',error,flush=True)
    (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    return 0 if summary['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
