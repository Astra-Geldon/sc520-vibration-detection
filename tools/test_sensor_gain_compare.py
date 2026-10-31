"""Exercise gain selection and grouped sensor writes/readback with a register-map slave.

Uses unmodified production debounce counts and the actual AE/gain lookup tables.
The transaction model deliberately replaces only the bit-level I2C engine; this
suite tests control sequencing and data integrity, not physical I2C signalling.
Simulator outputs and extracted legacy references stay under _build.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess


MODEL = r'''
`timescale 1ns/1ps
module uii2c #(parameter WMEN_LEN=4, RMEN_LEN=1, CLK_DIV=239)(
 input I_clk,I_rstn, output O_iic_scl, inout IO_iic_sda,
 input [WMEN_LEN*8-1:0] I_wr_data, input [7:0] I_wr_cnt,
 output reg [RMEN_LEN*8-1:0] O_rd_data,
 input [7:0] I_rd_cnt,input I_iic_req,I_iic_mode,
 output reg O_iic_busy,output reg O_iic_bus_error, output IO_iic_sda_dg);
 assign O_iic_scl=1'b1; assign IO_iic_sda=1'bz; assign IO_iic_sda_dg=IO_iic_sda;
 reg [7:0] mem[0:65535];
 integer cycles_left=0,write_count=0,read_count=0,groups=0,completed_reads=0;
 integer ae_write_index=-1,ae_read_index=-1,delay_once=0;
 integer corrupt_index=-1,error_index=-1;
 integer transaction_read_index=-1;
 integer cycle_count=0,release_cycle=0;
 reg check_settle=0,reserved_noise=0;
 reg enforce_gain=1;
 reg [15:0] address;
 reg [7:0] value;
 reg mode;
 integer k;
 initial for(k=0;k<65536;k=k+1) mem[k]=0;
 function [15:0] expected_address;
 input integer index;
 begin case(index)
  0:expected_address=16'h3812; 1:expected_address=16'h3e00;
  2:expected_address=16'h3e01; 3:expected_address=16'h3e02;
  4:expected_address=16'h3e09; 5:expected_address=16'h3e06;
  6:expected_address=16'h3e07; 7:expected_address=16'h3812;
  default:expected_address=16'hffff;
 endcase end endfunction
 always @(posedge I_clk or negedge I_rstn) begin
  if(!I_rstn) begin
   O_iic_busy<=0;O_iic_bus_error<=0;O_rd_data<=0;cycles_left<=0;
   write_count<=0;read_count<=0;groups<=0;completed_reads<=0;
   ae_write_index<=-1;ae_read_index<=-1;transaction_read_index<=-1;
   cycle_count<=0;release_cycle<=0;
   mem[16'h3107]<=8'hee;mem[16'h3108]<=8'h4b;
  end else begin
   cycle_count<=cycle_count+1;
   O_iic_bus_error<=0;
   if(!O_iic_busy && I_iic_req) begin
    if(I_wr_data[7:0]!==8'h6c) $fatal(1,"Wrong sensor address");
    if((I_iic_mode && (I_wr_cnt!==3 || I_rd_cnt!==1)) ||
       (!I_iic_mode && (I_wr_cnt!==4 || I_rd_cnt!==0)))
      $fatal(1,"Invalid transaction lengths mode%0d wr%0d rd%0d",I_iic_mode,I_wr_cnt,I_rd_cnt);
    address={I_wr_data[15:8],I_wr_data[23:16]};
    value=I_wr_data[31:24];mode=I_iic_mode;
    O_iic_busy<=1;cycles_left<=7+delay_once;delay_once=0;
    transaction_read_index<=-1;
    if(!I_iic_mode) begin
     write_count<=write_count+1;
     if(address==16'h3812 && value==0) begin
      groups<=groups+1;ae_write_index<=1;ae_read_index<=-1;
     end else if(ae_write_index>=1 && ae_write_index<=7) begin
      if(address!==expected_address(ae_write_index))
       $fatal(1,"AE write order index%0d address%04x",ae_write_index,address);
      if(enforce_gain) begin
       if(ae_write_index==1 && value!==0) $fatal(1,"Exposure high byte changed");
       if(ae_write_index==2 && value!==8'h38) $fatal(1,"Exposure middle byte changed");
       if(ae_write_index==3 && value!==8'h40) $fatal(1,"Exposure low byte changed");
       if(ae_write_index==5 && value!==0) $fatal(1,"Digital coarse gain changed");
       if(ae_write_index==7 && value!==8'h30) $fatal(1,"Group release changed");
      end
      if(ae_write_index==7) begin
       ae_write_index<=-1;ae_read_index<=0;
      end else ae_write_index<=ae_write_index+1;
     end
    end else begin
     read_count<=read_count+1;
     if(ae_read_index>=0 && ae_read_index<6) begin
      if(check_settle && ae_read_index==0 && cycle_count-release_cycle<1190477)
       $fatal(1,"Readback began before50ms sensor settling interval");
      if(address!==expected_address(ae_read_index+1))
       $fatal(1,"AE read order index%0d address%04x",ae_read_index,address);
      transaction_read_index<=ae_read_index;
      ae_read_index<=ae_read_index+1;
     end
    end
   end else if(O_iic_busy) begin
    if(cycles_left==0) begin
     O_iic_busy<=0;
     if(mode) begin
      O_rd_data<=mem[address] ^
       ((transaction_read_index==corrupt_index && transaction_read_index>=0)?
         ((transaction_read_index==2)?8'h10:8'h01):8'h00) ^
       (reserved_noise?((address==16'h3e00)?8'hf0:(address==16'h3e02)?8'h0f:8'h00):8'h00);
      if(transaction_read_index==error_index && transaction_read_index>=0) O_iic_bus_error<=1;
      if(transaction_read_index>=0) completed_reads<=completed_reads+1;
     end else begin
      mem[address]<=value;
      if(address==16'h3812 && value==8'h30) release_cycle<=cycle_count;
     end
    end else cycles_left<=cycles_left-1;
   end
  end
 end
endmodule
'''


SENSOR_TB = r'''
`timescale 1ns/1ps
module tb_sensor_gain_compare;
 parameter integer TEST_CASE=0;
 reg clk=0,rst_n=0,key_n=1;
 always #21 clk=~clk;
 reg [3:0] buttons=4'b1111;
 wire req,cfg,done,verified,error,idok;
 wire [15:0] ae,ag,id;
 wire [1:0] gray;
 wire scl;tri1 sda;
 integer clock_count=0,req_count=0,verified_count=0;
 integer previous_req_count,previous_groups,before_reads,n;
 reg verified_prev=0;
 reg [31:0] held_request;
 reg was_busy=0;
 ae_set #(.EXP_RST(3),.GAIN_COMPARE_EN(1)) control(
  .I_clk(clk),.I_rst(!rst_n),.I_btn(buttons),.I_exp_key_n(key_n),
  .I_ae_cfg_done(done),.I_cam_cfg_done(cfg),.O_ae_req(req),.O_ae(ae),.O_ag(ag));
 uicfgcs520 #(.AE_VERIFY_EN(1)) camera(
  .I_clk(clk),.I_rst_n(rst_n),.I_ae_req(req),.I_ae(ae),.I_ag(ag),
  .O_cam_scl(scl),.IO_cam_sda(sda),.O_cfg_done(cfg),.O_ae_cfg_done(done),
  .O_sensor_id(id),.O_sensor_id_ok(idok),.O_iic_error(error),
  .O_gain_sel_gray(gray),.O_gain_verified(verified));
 always @(posedge clk) begin
  clock_count=clock_count+1;
  if(clock_count>30000000) $fatal(1,"Watchdog case%0d",TEST_CASE);
  if(!rst_n) begin req_count=0;verified_count=0;was_busy=0;verified_prev=0;end
  else begin
   if(req) begin
    req_count=req_count+1;
    if(!cfg || !done) $fatal(1,"Request emitted before configuration done");
    if(ae!==900) $fatal(1,"Exposure is not fixed900");
    if(ag!==160 && ag!==144 && ag!==112 && ag!==80) $fatal(1,"Unexpected gain%0d",ag);
   end
   if(was_busy && cfg && !done && {ae,ag}!==held_request)
    $fatal(1,"AE/gain mutated in active write/read sequence");
   was_busy=cfg && !done;held_request={ae,ag};
   if(verified && !verified_prev) begin
    verified_count=verified_count+1;
    if(error || !done || camera.u_i2c.completed_reads<6)
     $fatal(1,"False or early verification");
    if(camera.u_i2c.ae_read_index!==6) $fatal(1,"Verification before sixth read");
   end
   verified_prev=verified;
  end
 end
 task tick;input integer count;begin repeat(count) @(negedge clk);end endtask
 task reset_all;begin
  rst_n=0;key_n=1;buttons=15;tick(8);rst_n=1;tick(8);
 end endtask
 task wait_complete;
  input [15:0] gain;input [1:0] expected_gray;
  integer guard;
  begin
   guard=0;
   while(!(verified && done && ag==gain && gray==expected_gray)) begin
    tick(1);guard=guard+1;if(guard>5000000) $fatal(1,"No verified gain%0d gray%0d ae%0d ag%0d state%0d err%0d",gain,gray,ae,ag,camera.state,error);
   end
   tick(16);
   if(ae!==900 || camera.u_i2c.mem[16'h3e00]!==0 || camera.u_i2c.mem[16'h3e01]!==8'h38 || camera.u_i2c.mem[16'h3e02]!==8'h40)
    $fatal(1,"Actual register exposure not900");
   case(gain)
    160:if({camera.u_i2c.mem[16'h3e09],camera.u_i2c.mem[16'h3e06],camera.u_i2c.mem[16'h3e07]}!==24'h0f00c0)$fatal(1,"24x table wrong");
    144:if({camera.u_i2c.mem[16'h3e09],camera.u_i2c.mem[16'h3e06],camera.u_i2c.mem[16'h3e07]}!==24'h0f0080)$fatal(1,"16x table wrong");
    112:if({camera.u_i2c.mem[16'h3e09],camera.u_i2c.mem[16'h3e06],camera.u_i2c.mem[16'h3e07]}!==24'h0b0080)$fatal(1,"8x table wrong");
    80:if({camera.u_i2c.mem[16'h3e09],camera.u_i2c.mem[16'h3e06],camera.u_i2c.mem[16'h3e07]}!==24'h090080)$fatal(1,"4x table wrong");
   endcase
   $display("PASS applied gain%0d gray%02b groups%0d reads%0d",gain,gray,camera.u_i2c.groups,camera.u_i2c.completed_reads);
  end
 endtask
 task press;begin key_n=0;tick(238115);key_n=1;tick(238115);end endtask
 initial begin
  #1 rst_n=1;#1 rst_n=0;
  if(TEST_CASE>=1 && TEST_CASE<=6) camera.u_i2c.corrupt_index=TEST_CASE-1;
  if(TEST_CASE==7) camera.u_i2c.error_index=5;
  camera.u_i2c.check_settle=1;
  if(TEST_CASE==8) camera.u_i2c.reserved_noise=1;
  reset_all;
  if(TEST_CASE>=1 && TEST_CASE<=7) begin
   wait(cfg);wait(req);wait(!done);wait(done);tick(20);
   if(!error || verified || camera.u_i2c.completed_reads!==6)
    $fatal(1,"Readback error case%0d not detected err%0d verified%0d reads%0d",TEST_CASE,error,verified,camera.u_i2c.completed_reads);
   $display("PASS negative case%0d: corrupt/readbuserror blocks verification",TEST_CASE);
   // The old error latch is deliberately sticky across later good transactions.
   camera.u_i2c.corrupt_index=-1;camera.u_i2c.error_index=-1;
   press;wait(done);tick(1000);
   if(verified || !error) $fatal(1,"Sticky failure falsely cleared");
   $display("PASS sticky failure case%0d",TEST_CASE);
  end else if(TEST_CASE==8) begin
   wait_complete(160,0);
   if(error)$fatal(1,"Reserved exposure bits incorrectly treated as requested data");
   $display("PASS exposure reserved-bit differences accepted; valid-field corruptions tested separately");
  end else begin
   wait_complete(160,0);
   previous_req_count=req_count;
   for(n=0;n<20;n=n+1) begin key_n=0;tick(100);key_n=1;tick(100);end
   tick(1000);if(req_count!==previous_req_count)$fatal(1,"Bounce accepted");
   key_n=0;tick(238115);wait_complete(144,1);
   previous_req_count=req_count;tick(600000);
   if(req_count!==previous_req_count)$fatal(1,"Long hold repeated");
   key_n=1;tick(238115);
   press;wait_complete(112,3);press;wait_complete(80,2);press;wait_complete(160,0);
   previous_req_count=req_count;buttons=0;tick(3300000);buttons=15;tick(20);
   if(req_count!==previous_req_count || ae!==900 || ag!==160)$fatal(1,"Legacy input affected comparison");
   $display("PASS bounce/hold/wrap and ignored N2/J14 inputs");
   // Hold the first transaction busy across two further debounced key events.
   camera.u_i2c.delay_once=1500000;
   previous_groups=camera.u_i2c.groups;
   press;
   if(done || ag!==144)$fatal(1,"Delayed first request not in flight");
   press;press;
   if(done || ag!==144)$fatal(1,"In-flight target changed under rapid key events");
   wait_complete(80,2);
   if(camera.u_i2c.groups!==previous_groups+2)$fatal(1,"Expected in-flight and latest requests only");
   if(camera.u_i2c.completed_reads!==camera.u_i2c.groups*6)$fatal(1,"Missing/extra read transactions");
   if(error)$fatal(1,"Unexpected sensor error");
   $display("PASS busy coalescing: stable first group then latest selection");
   reset_all;wait_complete(160,0);
   if(req_count!==1 || camera.u_i2c.groups!==1)$fatal(1,"Reset did not restore reference");
   $display("PASS reset reference");
  end
  $display("PASS sensor_gain_compare case%0d cycles%0d requests%0d",TEST_CASE,clock_count,req_count);
  $finish;
 end
endmodule
'''


LEGACY_TB = r'''
`timescale 1ns/1ps
module tb_sensor_gain_legacy;
 reg clk=0,rst_n=0,key_n=1;
 always #21 clk=~clk;
 reg [3:0] buttons=15;
 wire [1:0] req,cfg,done,idok,error;
 wire [15:0] ae[0:1],ag[0:1],id[0:1];
 wire [1:0] scl;tri1 sda0,sda1;
 integer checks=0,n;
 ae_set #(.EXP_RST(3)) new_control(.I_clk(clk),.I_rst(!rst_n),.I_btn(buttons),.I_exp_key_n(key_n),
  .I_ae_cfg_done(done[0]),.I_cam_cfg_done(cfg[0]),.O_ae_req(req[0]),.O_ae(ae[0]),.O_ag(ag[0]));
 ae_set_legacy #(.EXP_RST(3)) old_control(.I_clk(clk),.I_rst(!rst_n),.I_btn(buttons),.I_exp_key_n(key_n),
  .I_ae_cfg_done(done[1]),.I_cam_cfg_done(cfg[1]),.O_ae_req(req[1]),.O_ae(ae[1]),.O_ag(ag[1]));
 uicfgcs520 new_camera(.I_clk(clk),.I_rst_n(rst_n),.I_ae_req(req[0]),.I_ae(ae[0]),.I_ag(ag[0]),
  .O_cam_scl(scl[0]),.IO_cam_sda(sda0),.O_cfg_done(cfg[0]),.O_ae_cfg_done(done[0]),
  .O_sensor_id(id[0]),.O_sensor_id_ok(idok[0]),.O_iic_error(error[0]),.O_gain_sel_gray(),.O_gain_verified());
 uicfgcs520_legacy old_camera(.I_clk(clk),.I_rst_n(rst_n),.I_ae_req(req[1]),.I_ae(ae[1]),.I_ag(ag[1]),
  .O_cam_scl(scl[1]),.IO_cam_sda(sda1),.O_cfg_done(cfg[1]),.O_ae_cfg_done(done[1]),
  .O_sensor_id(id[1]),.O_sensor_id_ok(idok[1]),.O_iic_error(error[1]));
 always @(posedge clk) begin
  #1;
  if(rst_n) begin
   if({req[0],cfg[0],done[0],ae[0],ag[0],id[0],idok[0],error[0]} !==
      {req[1],cfg[1],done[1],ae[1],ag[1],id[1],idok[1],error[1]})
    $fatal(1,"Legacy output behaviour changed atcycle%0d",checks);
   if({new_camera.iic_req,new_camera.iic_mode,new_camera.wr_data,new_camera.wr_cnt,new_camera.rd_cnt} !==
      {old_camera.iic_req,old_camera.iic_mode,old_camera.wr_data,old_camera.wr_cnt,old_camera.rd_cnt})
    $fatal(1,"Legacy I2C transaction timing changed atcycle%0d",checks);
   checks=checks+1;
  end
 end
 task tick;input integer count;begin repeat(count)@(negedge clk);end endtask
 initial begin
  new_camera.u_i2c.enforce_gain=0;old_camera.u_i2c.enforce_gain=0;
  #1 rst_n=1;#1 rst_n=0;tick(8);rst_n=1;tick(125000);
  for(n=0;n<5;n=n+1)begin key_n=0;tick(238115);key_n=1;tick(238115);end
  buttons=4'b1011;tick(3300000);buttons=15;tick(16);
  buttons=4'b1110;tick(200010);buttons=15;tick(16);
  rst_n=0;tick(8);rst_n=1;tick(125000);
  if(new_camera.u_i2c.read_count!==2 || old_camera.u_i2c.read_count!==2)
   $fatal(1,"Legacy mode unexpectedly added readback");
  $display("PASS sensor_gain_legacy: %0d cycle-by-cycle output/I2C checks",checks);
  $finish;
 end
endmodule
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--skip-osd', action='store_true')
    parser.add_argument('--osd-only', action='store_true', help='Reuse passed sensor results only if production hashes still match')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = args.output or root.parent / '_build' / root.name / 'sensor-gain-compare-20261031/validation'
    out.mkdir(parents=True, exist_ok=True)
    hdl = root / 'user_source/hdl_source'
    compiler = Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin/iverilog.exe')
    files = [hdl / x for x in ('uiisp_beta/ae_set.v', 'uics520_cfg/uicfgcs520.v', 'uics520_cfg/SC520GainTbl.v',
                               'uics520_cfg/uics520regAE.v', 'uics520_cfg/uics520reg_720p60.v')]
    summary = {'pass': False, 'scope': 'Production debounce, fixed900 gain candidates, real tables, grouped writes, six readbacks, injected failures and legacy cycle equivalence',
               'bit_level_I2C_signalling_tested': False, 'hardware_accessed': False,
               'legacy_reference_commit': '1d96bb8', 'tests': {}}
    def hash_files(paths):
        return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    def run_tb(name, top, text, extra=(), parameter=None):
        tbfile = out / (name + '.v')
        tbfile.write_text(text, encoding='utf-8')
        compiled = out / (name + '.vvp')
        command = [str(compiler), '-g2012', '-s', top, '-o', str(compiled)]
        if parameter:
            command += ['-P' + top + '.' + parameter]
        command += [str(tbfile), str(out / 'i2c_register_model.v')] + [str(p) for p in files] + [str(p) for p in extra]
        build = subprocess.run(command, capture_output=True, text=True, errors='replace', timeout=60)
        (out / (name + '_compile.log')).write_text(build.stdout + build.stderr, encoding='utf-8')
        assert build.returncode == 0, name + ': ' + build.stdout + build.stderr
        result = subprocess.run([str(compiler.with_name('vvp.exe')), str(compiled)], capture_output=True, text=True, errors='replace', timeout=240)
        log = result.stdout + result.stderr
        (out / (name + '.log')).write_text(log, encoding='utf-8')
        print(log, end='', flush=True)
        assert result.returncode == 0 and 'PASS ' in log, name + ': ' + log
        summary['tests'][name] = {'pass': True, 'simulation_exit_code': result.returncode, 'log': name + '.log'}
        return log
    try:
        summary['source_sha256'] = hash_files(files)
        if args.osd_only:
            previous = json.loads((out / 'summary.json').read_text(encoding='utf-8'))
            assert previous['pass'] and all(previous['tests'][n]['pass'] for n in ['sensor_case0', 'sensor_case1', 'sensor_case2', 'sensor_case3', 'sensor_case4', 'sensor_case5', 'sensor_case6', 'sensor_case7', 'legacy'])
            assert all(previous['source_sha256'][n] == digest for n, digest in summary['source_sha256'].items()), 'Sensor sources changed since earlier tests'
            summary = previous
            summary['pass'] = False
            check_osd(root, out, compiler, summary)
            summary['pass'] = True
            return 0
        (out / 'i2c_register_model.v').write_text(MODEL, encoding='utf-8')
        for case in range(9):
            log = run_tb('sensor_case' + str(case), 'tb_sensor_gain_compare', SENSOR_TB, parameter='TEST_CASE=' + str(case))
            m = re.search(r'PASS sensor_gain_compare case\d+ cycles(\d+) requests(\d+)', log)
            assert m, log
            summary['tests']['sensor_case' + str(case)].update(cycles=int(m[1]), final_requests=int(m[2]))
        legacy_files = []
        for filename, oldmodule in [('uiisp_beta/ae_set.v', 'ae_set'), ('uics520_cfg/uicfgcs520.v', 'uicfgcs520')]:
            data = subprocess.check_output(['git', 'show', '1d96bb8:user_source/hdl_source/' + filename], cwd=root)
            data = re.sub(rb'\bmodule\s+' + oldmodule.encode() + rb'\b', b'module ' + oldmodule.encode() + b'_legacy', data, count=1)
            target = out / (oldmodule + '_legacy.v')
            target.write_bytes(data)
            legacy_files.append(target)
        log = run_tb('legacy', 'tb_sensor_gain_legacy', LEGACY_TB, extra=legacy_files)
        summary['legacy_equivalence_cycles'] = int(re.search(r'PASS sensor_gain_legacy: (\d+)', log)[1])
        assert summary['source_sha256'] == hash_files(files), 'Sensor RTL changed during validation'
        summary['osd_checked'] = False
        if not args.skip_osd:
            check_osd(root, out, compiler, summary)
        summary['pass'] = True
    except (OSError, AssertionError, subprocess.SubprocessError, ValueError) as error:
        summary['error'] = str(error)
        print('FAIL sensor_gain_compare:', error, flush=True)
    finally:
        (out / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return 0 if summary['pass'] else 1


def check_osd(root, out, compiler, summary):
    hdl = root / 'user_source/hdl_source'
    paths = [hdl / x for x in ['osd_overlay.v', 'osd_font_rom.v', 'osd_logo_rom.v', 'design_top_wrapper.v']]
    hashes = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    top = paths[-1].read_text(encoding='utf-8')
    for pattern in [r'\.GAIN_COMPARE_EN\(1\)', r'\.AE_VERIFY_EN\(1\)',
                    r'assign\s+S_exp_sel\s*=\s*2\x27d3', r'assign\s+S_region_sel_req\s*=\s*4\x27d0',
                    r'\.O_exp_sel\s*\(\s*\)', r'\.O_region_sel\s*\(\s*\)',
                    r'\.GAIN_DEBUG_EN\s*\(\s*1\s*\)', r'\.REGION_DEBUG_EN\s*\(\s*0\s*\)',
                    r'\.SHOULDER_DEBUG_EN\s*\(\s*0\s*\)', r'\.LOGO_EN\s*\(\s*1\s*\)',
                    r'\.O_gain_sel_gray\s*\(\s*S_cam_gain_sel_gray\s*\)',
                    r'\.O_gain_verified\s*\(\s*S_cam_gain_verified\s*\)',
                    r'\.I_gain_sel\s*\(\s*S_tone_stage_gain\s*\)',
                    r'\.I_gain_verified\s*\(\s*S_tone_stage_gain_verified\s*\)']:
        assert re.search(pattern, top), 'Top wiring assertion: ' + pattern
    glyphs = {
        '0': ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
        '1': ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
        '2': ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
        '4': ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
        '6': ['01110', '10000', '10000', '11110', '10001', '10001', '01110'],
        '8': ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
        '9': ['01110', '10001', '10001', '01111', '00001', '00001', '01110'],
        'E': ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
        'G': ['01110', '10001', '10000', '10111', '10001', '10001', '01110'],
        'V': ['10001', '10001', '10001', '10001', '10001', '01010', '00100'],
        '=': ['00000', '11111', '00000', '11111', '00000', '00000', '00000'],
        ' ': ['00000'] * 7,
    }
    vectors = []
    for enable in range(2):
        for sel, gain in enumerate([24, 16, 8, 4]):
            for verified in range(2):
                text = 'E=900 G=' + str(gain).rjust(2) + ' V=' + str(verified)
                assert len(text) == 14
                for y in range(49, 77):
                    for x in range(17, 200):
                        box = enable and 20 <= x < 196 and 52 <= y < 74
                        white = 0
                        if enable and 24 <= x < 192 and 56 <= y < 70:
                            cell, col = divmod(x - 24, 12)
                            if col < 10:
                                white = glyphs[text[cell]][(y - 56) // 2][col // 2] == '1'
                        word = ((((((enable << 2) | sel) << 1 | verified) << 11 | x) << 10 | y) << 2) | (int(box) << 1) | int(white)
                        vectors.append(f'{word:07x}')
    vector_file = out / 'gain_glyph_vectors.hex'
    vector_file.write_text('\n'.join(vectors) + '\n', encoding='ascii')
    legacy = subprocess.check_output(['git', 'show', '1d96bb8:user_source/hdl_source/osd_overlay.v'], cwd=root)
    for name in ['osd_overlay', 'osd_region_line', 'osd_threshold_line']:
        legacy = re.sub(rb'\b' + name.encode() + rb'\b', b'legacy_' + name.encode(), legacy)
    old_file = out / 'osd_overlay_legacy.v'
    old_file.write_bytes(legacy)
    tb = r'''
`timescale 1ns/1ps
module tb_sensor_gain_osd;
 reg [26:0] vectors[0:VECTOR_COUNT-1];
 reg enable=0,verified=0;
 reg [1:0] sel=0;
 reg [10:0] x=0;reg [9:0] y=0;
 reg expected_box=0,expected_white=0;
 wire box,white;
 reg [2:0] mode=0;
 reg [23:0] pixel=24'had7329;
 wire [23:0] new_pixel,disabled_pixel,legacy_pixel;
 integer n,m,gx,gy,checked=0,logo_colours=0;
 osd_gain_line line(.I_x(x),.I_y(y),.I_enable(enable),.I_sel(sel),.I_verified(verified),.O_box(box),.O_white(white));
 osd_overlay #(.GAIN_DEBUG_EN(1),.LOGO_EN(1)) overlay(
  .I_clk(1'b0),.I_rst_n(1'b0),.I_de(enable),.I_vs(1'b0),.I_mode(mode),.I_src_raw(1'b0),
  .I_k_sel(2'd2),.I_exp_sel(2'd3),.I_gain_sel(sel),.I_gain_verified(verified),.I_region_sel(4'd0),
  .I_threshold(8'd128),.I_th_locked(1'b0),.I_data(pixel),.O_data(new_pixel));
 osd_overlay #(.LOGO_EN(1)) disabled(
  .I_clk(1'b0),.I_rst_n(1'b0),.I_de(enable),.I_vs(1'b0),.I_mode(mode),.I_src_raw(1'b0),
  .I_k_sel(2'd2),.I_exp_sel(2'd3),.I_gain_sel(2'bxx),.I_gain_verified(1'bx),.I_region_sel(4'd0),
  .I_threshold(8'd128),.I_th_locked(1'b0),.I_data(pixel),.O_data(disabled_pixel));
 legacy_osd_overlay #(.LOGO_EN(1)) legacy(
  .I_clk(1'b0),.I_rst_n(1'b0),.I_de(enable),.I_vs(1'b0),.I_mode(mode),.I_src_raw(1'b0),
  .I_k_sel(2'd2),.I_exp_sel(2'd3),.I_region_sel(4'd0),
  .I_threshold(8'd128),.I_th_locked(1'b0),.I_data(pixel),.O_data(legacy_pixel));
 initial begin
  $readmemh("VECTOR_PATH",vectors);
  force overlay.S_x=x;force overlay.S_y=y;
  force disabled.S_x=x;force disabled.S_y=y;
  force legacy.S_x=x;force legacy.S_y=y;
  for(m=0;m<4;m=m+1) begin
   mode=m;
   for(n=0;n<VECTOR_COUNT;n=n+1)begin
    {enable,sel,verified,x,y,expected_box,expected_white}=vectors[n];#1;
    if({box,white}!=={expected_box,expected_white})
     $fatal(1,"Glyph mismatch mode%0d sel%0d V%0d x%0d y%0d actual%b%b expected%b%b",m,sel,verified,x,y,box,white,expected_box,expected_white);
    if(disabled_pixel!==legacy_pixel)$fatal(1,"Default parameter changed old OSD at x%0d y%0d",x,y);
    if(new_pixel!==(expected_box?(expected_white?24'hffffff:24'h000000):legacy_pixel))
     $fatal(1,"Gain label composition mismatch mode%0d x%0d y%0d",m,x,y);
    checked=checked+1;
   end
  end
  enable=1;
  for(m=0;m<4;m=m+1)begin
   mode=m;sel=m;verified=m%2;
   for(gy=12;gy<100;gy=gy+1)for(gx=1132;gx<1268;gx=gx+1)begin
    x=gx;y=gy;#1;
    if(new_pixel!==legacy_pixel || disabled_pixel!==legacy_pixel)$fatal(1,"Logo changed");
    if(new_pixel==24'h1b3a66 || new_pixel==24'he8382f)logo_colours=logo_colours+1;
    checked=checked+1;
   end
  end
  if(logo_colours==0)$fatal(1,"Logo never emitted colours");
  $display("PASS sensor_gain_osd: %0d points, %0d Logo coloured pixels; 4 gains x2 verification states x4 modes",checked,logo_colours);
  $finish;
 end
endmodule
'''.replace('VECTOR_COUNT', str(len(vectors))).replace('VECTOR_PATH', vector_file.as_posix())
    tb_file = out / 'tb_sensor_gain_osd.v'
    tb_file.write_text(tb, encoding='utf-8')
    compiled = out / 'gain_osd.vvp'
    command = [str(compiler), '-g2012', '-s', 'tb_sensor_gain_osd', '-o', str(compiled), str(tb_file), str(old_file)] + [str(p) for p in paths[:-1]]
    build = subprocess.run(command, capture_output=True, text=True, errors='replace', timeout=60)
    (out / 'gain_osd_compile.log').write_text(build.stdout + build.stderr, encoding='utf-8')
    assert build.returncode == 0, build.stdout + build.stderr
    result = subprocess.run([str(compiler.with_name('vvp.exe')), str(compiled)], capture_output=True, text=True, errors='replace', timeout=120)
    log = result.stdout + result.stderr
    (out / 'gain_osd.log').write_text(log, encoding='utf-8')
    print(log, end='', flush=True)
    assert result.returncode == 0, log
    count = re.search(r'PASS sensor_gain_osd: (\d+) points, (\d+) Logo coloured pixels', log)
    assert count, log
    assert hashes == {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}, 'UI sources changed while verifying'
    summary['source_sha256'].update(hashes)
    summary['osd_checked'] = True
    summary['osd_pixel_checks'] = int(count[1])
    summary['logo_colour_checks'] = int(count[2])
    summary['top_gain_wiring_checks'] = True
    summary['tests']['gain_osd'] = {'pass': True, 'simulation_exit_code': result.returncode, 'log': 'gain_osd.log'}


if __name__ == '__main__':
    raise SystemExit(main())
