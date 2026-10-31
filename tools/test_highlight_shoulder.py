"""Exhaustive shared-RGB shoulder RTL check against an independent integer oracle."""
from pathlib import Path
import subprocess, hashlib, json, argparse

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
out = args.output or root.parent / '_build' / root.name / 'highlight-common-shoulder-20261031' / 'kernel_checks'
out.mkdir(parents=True, exist_ok=True)
hdl = root / 'user_source/hdl_source'
compiler = Path(r'D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin/iverilog.exe')
tb = r'''
`timescale 1ns/1ps
module tb_shoulder_kernel;
reg de=1,en=1;
reg [2:0] sel=0;
reg [26:0] wide=0;
reg [23:0] old_pixel=0;
wire [23:0] actual;
wire [23:0] actual_peak;
wire mask;
wire [8:0] rg_peak = (wide[26:18]>wide[17:9]) ? wide[26:18] : wide[17:9];
wire [8:0] wide_peak = (rg_peak>wide[8:0]) ? rg_peak : wide[8:0];
integer p,v,c,n,checks=0;
reg [8:0] vr,vg,vb;
reg [23:0] expected;
highlight_tone dut(.I_de(de),.I_enable(en),.I_sel(sel),.I_data(old_pixel),
 .I_wide_data(wide),.O_mask(mask),.O_data(actual));
highlight_tone #(.PRECOMPUTED_PEAK_EN(1)) peak_dut (
 .I_de(de),.I_enable(en),.I_sel(sel),.I_data(old_pixel),
 .I_wide_data(wide),.I_peak(wide_peak),.O_mask(),.O_data(actual_peak));
function [7:0] clip;
 input [8:0] x;
 begin clip=(x>255)?255:x[7:0];end
endfunction
function [7:0] reference;
 input [8:0] value,peak;
 input [2:0] candidate;
 reg [63:0] gain,distance,span,num,den,tmp;
 begin
 gain=65536;
 if(candidate[2] && peak<208)begin
  distance=208-peak;gain=65536+distance*256+2*distance*distance;
 end
 if(candidate[1:0]!=0 && peak>208)begin
  span=(candidate[1:0]==1)?128:((candidate[1:0]==2)?64:32);
  distance=peak-208;
  num=208*(span+distance)+span*distance;den=span+distance;
  if(num>255*den)num=255*den;
  den=den*peak;
  gain=(num*65536+den/2)/den;
 end
 tmp=(value*gain+32768)>>16;
 reference=(tmp>255)?255:tmp[7:0];
 end
endfunction
task check;
 reg [8:0] ar,ag,ab,peak;
 reg [9:0] y4;
 reg emask;
 begin
 wide={vr,vg,vb}; old_pixel={clip(vr),clip(vg),clip(vb)};
 ar=(sel[1:0]==0)?{1'b0,old_pixel[23:16]}:vr;
 ag=(sel[1:0]==0)?{1'b0,old_pixel[15:8]}:vg;
 ab=(sel[1:0]==0)?{1'b0,old_pixel[7:0]}:vb;
 peak=(ar>ag)?ar:ag;if(ab>peak)peak=ab;
 expected=(!de||!en)?old_pixel:{reference(ar,peak,sel),reference(ag,peak,sel),reference(ab,peak,sel)};
 y4={2'b0,old_pixel[23:16]}+{1'b0,old_pixel[15:8],1'b0}+{2'b0,old_pixel[7:0]};
 emask=de&&en&&(y4>=832||old_pixel[23:16]>=250||old_pixel[15:8]>=250||old_pixel[7:0]>=250);
 #1;
 if(actual!==expected)$fatal(1,"math mismatch sel%0d wide%h old%h actual%h expected%h",sel,wide,old_pixel,actual,expected);
 if(actual_peak!==expected)$fatal(1,"precomputed peak mismatch sel%0d wide%h actual%h expected%h",sel,wide,actual_peak,expected);
 if(mask!==emask)$fatal(1,"mask changed");
 checks=checks+1;
 end
endtask
initial begin
 for(p=0;p<512;p=p+1)begin
  for(v=0;v<=p;v=v+1)begin
   vr=p;vg=v;vb=p/2;
   for(c=0;c<8;c=c+1)begin sel=c;check;end
  end
 end
 for(n=0;n<20000;n=n+1)begin
  vr=$random&511;vg=$random&511;vb=$random&511;
  sel=n%8;de=(n%3!=0);en=(n%5!=0);check;
 end
 $display("PASS shoulder_kernel checks=%0d",checks);$finish;
end
endmodule
'''
(out/'tb_kernel.v').write_text(tb, encoding='ascii', newline='\n')
files = [hdl/'highlight_tone.v',hdl/'highlight_shoulder_lut.v',hdl/'highlight_region.v']
cmd = [str(compiler), '-g2012', '-s', 'tb_shoulder_kernel', '-o', str(out/'kernel.vvp'),str(out/'tb_kernel.v')]+[str(p) for p in files]
build = subprocess.run(cmd,cwd=root,capture_output=True,text=True,timeout=60)
(out/'compile.log').write_text(build.stdout+build.stderr,encoding='utf-8')
assert build.returncode==0,build.stderr
run=subprocess.run([str(compiler.with_name('vvp.exe')),str(out/'kernel.vvp')],cwd=root,capture_output=True,text=True,timeout=300)
(out/'simulation.log').write_text(run.stdout+run.stderr,encoding='utf-8')
print(run.stdout)
passed=run.returncode==0 and 'PASS shoulder_kernel checks=1070624' in run.stdout
summary={'pass':passed,'scope':'All512 peaks x every component0..peak x8 candidates plus20000 random RGB/control cases; exact rational independent oracle','checks':1070624,'precomputed_peak_branch_checked':True,'source_sha256':{p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files},'oracle':'Exact rational soft shoulder; legacy C3 analytic formula; original H1 predicate','simulation_returncode':run.returncode}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
assert passed,run.stdout+run.stderr
