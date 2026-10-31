"""Check white preparation and its original-peak shoulder against integer math.

The independent reference uses a nonnegative convex-combination numerator,
not the signed-delta implementation. Physical near-white pixels are exhausted;
generic nine-bit edges/random inputs exercise rounding and overflow separately.
All simulator products remain under the project _build stage directory.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = args.output or root.parent / '_build' / root.name / 'highlight-white-protection-20261031' / 'white_checks'
    out.mkdir(parents=True, exist_ok=True)
    hdl = root / 'user_source/hdl_source'
    files = [hdl / name for name in ('highlight_white_prepare.v', 'highlight_tone.v', 'highlight_shoulder_lut.v', 'highlight_region.v')]
    tb = r'''
`timescale 1ns/1ps
module tb_highlight_white;
reg enable=1,de=1;
reg [1:0] strength=0;
reg [2:0] sel=7;
reg [8:0] r=0,g=0,b=0;
wire [26:0] source={r,g,b};
wire [26:0] prepared;
wire [8:0] rg=(r>g)?r:g;
wire [8:0] peak=(rg>b)?rg:b;
wire [23:0] clipped={clip(r),clip(g),clip(b)};
wire [23:0] actual_tone,old_tone;
integer checks=0,applied=0,max_pre_y4=0,max_post_y4=0;
integer rv,gv,bv,w,p,n,k,old_y,new_y,change,conf,q,mean_excess;
reg [26:0] expected_pre;
reg [23:0] expected_tone;
reg [8:0] er,eg,eb;
reg [8:0] reference_peak;
highlight_white_prepare dut(.I_enable(enable),.I_white_sel(strength),.I_wide_data(source),.O_wide_data(prepared));
highlight_tone #(.PRECOMPUTED_PEAK_EN(1)) tone(
 .I_de(de),.I_enable(enable),.I_sel(sel),.I_data(clipped),
 .I_wide_data(prepared),.I_peak(peak),.O_mask(),.O_data(actual_tone));
highlight_tone #(.PRECOMPUTED_PEAK_EN(1)) old(
 .I_de(de),.I_enable(enable),.I_sel(sel),.I_data(clipped),
 .I_wide_data(source),.I_peak(peak),.O_mask(),.O_data(old_tone));
function [7:0] clip;
 input [8:0] value;
 begin clip=value>255?255:value;end
endfunction
function [8:0] blend;
 input integer value,excess_y,denominator;
 integer target;
 begin
  target=(value>255?255:value)+excess_y;
  // Nonnegative convex combination, independently rounded to nearest.
  blend=((denominator-1)*value+target+denominator/2)/denominator;
 end
endfunction
function [7:0] shoulder;
 input [8:0] value,original_peak;
 input [2:0] profile;
 reg [63:0] gain,distance,span,num,den,tmp;
 begin
  gain=65536;
  if(profile[2] && original_peak<208)begin
   distance=208-original_peak;gain=65536+distance*256+2*distance*distance;
  end
  if(profile[1:0]!=0 && original_peak>208)begin
   span=(profile[1:0]==1)?128:((profile[1:0]==2)?64:32);
   distance=original_peak-208;
   num=208*(span+distance)+span*distance;den=span+distance;
   if(num>255*den)num=255*den;
   den=den*original_peak;gain=(num*65536+den/2)/den;
  end
  tmp=(value*gain+32768)>>16;
  shoulder=tmp>255?255:tmp;
 end
endfunction
task check;
 begin
  reference_peak=(r>g)?r:g;
  if(b>reference_peak)reference_peak=b;
  conf=(r>=248&&g>=248&&b>=248)?3:
       (r>=244&&g>=244&&b>=244)?2:
       (r>=240&&g>=240&&b>=240)?1:0;
  k=(strength<conf)?strength:conf;
  er=r>255?r-255:0;eg=g>255?g-255:0;eb=b>255?b-255:0;
  mean_excess=(er+2*eg+eb+2)/4;
  if(enable && k!=0 && (er!=0||eg!=0||eb!=0))begin
   q=(k==1)?4:((k==2)?2:1);
   expected_pre={blend(r,mean_excess,q),blend(g,mean_excess,q),blend(b,mean_excess,q)};
   applied=applied+1;
  end else expected_pre={r,g,b};
  if(!enable||!de)expected_tone={clip(r),clip(g),clip(b)};
  else if(sel[1:0]==0)expected_tone={shoulder(clip(r),reference_peak,sel),shoulder(clip(g),reference_peak,sel),shoulder(clip(b),reference_peak,sel)};
  else expected_tone={shoulder(expected_pre[26:18],reference_peak,sel),shoulder(expected_pre[17:9],reference_peak,sel),shoulder(expected_pre[8:0],reference_peak,sel)};
  #1;
  if(prepared!==expected_pre)$fatal(1,"prepare mismatch RGB=%d/%d/%d W%0d en%b expected%h got%h",r,g,b,strength,enable,expected_pre,prepared);
  if(actual_tone!==expected_tone)$fatal(1,"combined mismatch RGB=%d/%d/%d W%0d C/P%0d expected%h got%h",r,g,b,strength,sel,expected_tone,actual_tone);
  if(prepared[26:18]>peak||prepared[17:9]>peak||prepared[8:0]>peak)$fatal(1,"correction exceeded original peak");
  old_y=r+2*g+b;
  new_y=prepared[26:18]+2*prepared[17:9]+prepared[8:0];
  change=(new_y>old_y)?new_y-old_y:old_y-new_y;
  if(change>max_pre_y4)max_pre_y4=change;
  if(change>4)$fatal(1,"preparation luma changed >1 code: deltaY4=%0d",change);
  if(de&&enable&&sel[1:0]!=0)begin
   old_y=old_tone[23:16]+2*old_tone[15:8]+old_tone[7:0];
   new_y=actual_tone[23:16]+2*actual_tone[15:8]+actual_tone[7:0];
   change=(new_y>old_y)?new_y-old_y:old_y-new_y;
   if(change>max_post_y4)max_post_y4=change;
   if(change>8)$fatal(1,"post shoulder luma changed >2 codes: deltaY4=%0d",change);
  end
  if((!enable||strength==0||conf==0||peak<=255)&&prepared!==source)$fatal(1,"bypass altered");
  if(sel[1:0]==0 && actual_tone!==old_tone)$fatal(1,"P0 reference altered");
  checks=checks+1;
 end
endtask
initial begin
 // Exhaust all physically possible selected pixels from the current shading
 // bounds R<=282/G<=255/B<=275. Four W settings x every original C/P profile.
 for(rv=240;rv<=282;rv=rv+1)
  for(gv=240;gv<=255;gv=gv+1)
   for(bv=240;bv<=275;bv=bv+1)begin
    r=rv;g=gv;b=bv;
    for(w=0;w<4;w=w+1)begin strength=w;
     for(p=0;p<8;p=p+1)begin sel=p;check;end
    end
   end
 // Saturated endpoints and swapped channel roles across the full 9-bit port.
 for(rv=0;rv<512;rv=rv+1)
  for(w=0;w<4;w=w+1)begin
   strength=w;sel=7;r=rv;g=511;b=248;check;
   r=248;g=rv;b=511;check;
   r=511;g=248;b=rv;check;
   r=rv;g=rv;b=rv;check;
   if(prepared!==source)$fatal(1,"neutral RGB9 acquired chroma");
  end
 // Independent deterministic random controls include off, blanking and P0.
 for(n=0;n<20000;n=n+1)begin
  r=$random&511;g=$random&511;b=$random&511;
  strength=n%4;sel=(n/4)%8;de=(n%3!=0);enable=(n%5!=0);check;
 end
 // Exact review example; using an original peak rather than corrected peak
 // is essential to keep current P3 highlight brightness.
 enable=1;de=1;strength=3;sel=7;r=282;g=255;b=275;check;
 if(prepared!=={9'd267,9'd267,9'd267}||actual_tone!==24'hdadada)$fatal(1,"review example changed");
 $display("PASS highlight_white checks=%0d applied=%0d max_pre_Y4=%0d max_post_Y4=%0d",checks,applied,max_pre_y4,max_post_y4);
 $finish;
end
endmodule
'''
    tb_file = out / 'tb_highlight_white.v'
    tb_file.write_text(tb, encoding='ascii', newline='\n')
    compiler = Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin/iverilog.exe')
    build = subprocess.run([str(compiler), '-g2012', '-s', 'tb_highlight_white', '-o', str(out / 'white.vvp'), str(tb_file)] + [str(p) for p in files], cwd=root, capture_output=True, text=True, timeout=60)
    (out / 'compile.log').write_text(build.stdout + build.stderr, encoding='utf-8')
    assert build.returncode == 0, build.stdout + build.stderr
    run = subprocess.run([str(compiler.with_name('vvp.exe')), str(out / 'white.vvp')], cwd=root, capture_output=True, text=True, timeout=300)
    (out / 'simulation.log').write_text(run.stdout + run.stderr, encoding='utf-8')
    print(run.stdout)
    match = re.search(r'PASS highlight_white checks=(\d+) applied=(\d+) max_pre_Y4=(\d+) max_post_Y4=(\d+)', run.stdout)
    summary = {
        'pass': run.returncode == 0 and match is not None,
        'scope': 'All physically selected shading RGB combinations x4 white strengths x8 C/P profiles; generic 9-bit edges and random controls; independent nonnegative integer oracle',
        'source_sha256': {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
        'simulation_returncode': run.returncode,
        'original_peak_used_after_preparation': True,
    }
    if match:
        summary.update(checks=int(match[1]), correction_enabled_checks=int(match[2]), maximum_preparation_proxy_Y_error=int(match[3])/4, maximum_post_shoulder_proxy_Y_error=int(match[4])/4)
    (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    assert summary['pass'], run.stdout + run.stderr
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
