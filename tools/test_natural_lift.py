"""Check the natural profiles against an archived L1 and an independent target.

This runs production gain8_lift RTL, the archived L1 RTL, and the real UI/AE
controllers in Icarus. Generated HDL, vectors, logs and binaries stay in --output.
It does not test a physical sensor or claim that a curve is visually accepted.
"""

from fractions import Fraction
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess


ANCHORS = [(0, 0), (24, -2), (64, -8), (128, -4), (168, 0),
           (200, 4), (220, 3), (237, 0), (255, 0)]


def nearest(value):
    return (2 * value.numerator + value.denominator) // (2 * value.denominator)


def offset(value):
    for (x0, y0), (x1, y1) in zip(ANCHORS, ANCHORS[1:]):
        if x0 <= value <= x1:
            return Fraction(y0) + Fraction((value - x0) * (y1 - y0), x1 - x0)
    raise AssertionError(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reference', default='6882d41')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    hdl = root / 'user_source/hdl_source'
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    iv = Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin/iverilog.exe')
    files = [hdl / name for name in ['highlight_tone.v', 'img_mode_sel.v', 'uiisp_beta/ae_set.v']]
    bound_files = files + [hdl / 'design_top_wrapper.v']
    summary = {'pass': False, 'scope': 'Real natural-profile RTL versus archived L1 and independent piecewise target; UI/reset/mode regression',
               'source_sha256': {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in bound_files}, 'tests': {}}

    def run(name, bench, extra_files=()):
        tb = out / (name + '.v')
        tb.write_text(bench, encoding='utf-8', newline='\n')
        binary = out / (name + '.vvp')
        build = subprocess.run([str(iv), '-g2012', '-s', 'tb', '-o', str(binary), str(tb)]
                               + [str(p) for p in files + list(extra_files)],
                               capture_output=True, text=True, errors='replace', timeout=60)
        (out / (name + '_compile.log')).write_text(build.stdout + build.stderr, encoding='utf-8')
        assert build.returncode == 0, build.stdout + build.stderr
        result = subprocess.run([str(iv.with_name('vvp.exe')), str(binary)],
                                capture_output=True, text=True, errors='replace', timeout=300)
        (out / (name + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        print(result.stdout + result.stderr, flush=True)
        assert result.returncode == 0 and 'PASS ' in result.stdout, name
        summary['tests'][name] = {'pass': True, 'log': name + '.log'}
        return result.stdout

    try:
        legacy_bytes = subprocess.check_output(
            ['git', 'show', args.reference + ':user_source/hdl_source/highlight_tone.v'], cwd=root)
        legacy = legacy_bytes.decode('utf-8')
        summary['reference_commit'] = subprocess.check_output(
            ['git', 'rev-parse', args.reference], cwd=root, text=True).strip()
        summary['reference_tone_sha256'] = hashlib.sha256(legacy_bytes).hexdigest()
        legacy_gain_text = legacy.split('module gain8_lift_gain(', 1)[1].split('endmodule', 1)[0]
        packed = {int(p): int(value, 16) for p, value in
                  re.findall(r"8'd(\d+):\s*values=33'h([0-9a-fA-F]+)", legacy_gain_text)}
        assert sorted(packed) == list(range(256))
        l1_gains = [(packed[p] >> 22) & 2047 for p in range(256)]
        l1_peaks = [(p * l1_gains[p] + 128) >> 8 for p in range(256)]
        targets = list(range(256)) + l1_peaks
        for strength in [Fraction(1, 2), Fraction(1)]:
            candidate = [q if p >= 208 else nearest(Fraction(q) + strength * offset(q))
                         for p, q in enumerate(l1_peaks)]
            assert all(a <= b for a, b in zip(candidate, candidate[1:]))
            targets.extend(candidate)
        target_file = out / 'independent_peak_targets.hex'
        target_file.write_text('\n'.join(f'{target:02x}' for target in targets) + '\n', encoding='ascii')
        legacy_modules = legacy[legacy.index('module gain8_lift_gain('):]
        legacy_modules = re.sub(r'\bgain8_lift(?:_gain|_channel)?\b', lambda m: 'legacy_' + m[0], legacy_modules)
        legacy_file = out / 'archived_l1.v'
        legacy_file.write_text(legacy_modules, encoding='utf-8', newline='\n')
        numeric = r'''
`timescale 1ns/1ps
module tb;
reg[7:0] peak=0;reg[1:0] sel=0;reg[23:0] data=0;reg de=1,en=1;
wire[10:0] gain,old_gain;wire[23:0] result,old_result;
reg[7:0] targets[0:1023];
integer s,p,v,c,n=0,peak_checks=0,highlights=0,bypasses=0,previous;
integer r,g,b,expected_r,expected_g,expected_b,actual,channel,err,ratio_err;
gain8_lift_gain lut(.I_peak(peak),.I_sel(sel),.O_gain(gain));
legacy_gain8_lift_gain old_lut(.I_peak(peak),.I_sel(2'd1),.O_gain(old_gain));
gain8_lift dut(.I_de(de),.I_enable(en),.I_sel(sel),.I_data(data),.I_peak(peak),.O_data(result));
legacy_gain8_lift reference_l1(.I_de(de),.I_enable(en),.I_sel(2'd1),.I_data(data),.I_peak(peak),.O_data(old_result));
initial begin
 $readmemh("TARGETS",targets);
 for(s=0;s<4;s=s+1)begin
  previous=-1;
  for(p=0;p<256;p=p+1)begin
   sel=s;peak=p;data={8'(p),8'(p),8'(p)};#1;
   if(result!=={targets[s*256+p],targets[s*256+p],targets[s*256+p]})
    $fatal(1,"independent target mismatch s%0d p%0d got%h expected%0d",s,p,result,targets[s*256+p]);
   if(p>0&&result[23:16]<previous)$fatal(1,"nonmonotone s%0d p%0d",s,p);
   previous=result[23:16];peak_checks=peak_checks+1;
   if(s==0&&gain!==256)$fatal(1,"L0 coefficient not identity");
   if(s==1&&gain!==old_gain)$fatal(1,"archived L1 coefficient changed p%0d",p);
   if(s>0&&p>=208&&gain!==old_gain)$fatal(1,"highlight coefficient changed s%0d p%0d",s,p);
   // Every possible subordinate intensity occupies each of R,G,B in turn.
   for(v=0;v<=p;v=v+1)for(c=0;c<3;c=c+1)begin
    case(c)
     0:data={8'(p),8'(v),8'(v/2)};
     1:data={8'(v),8'(v/2),8'(p)};
     2:data={8'(v/2),8'(p),8'(v)};
    endcase
    #1;r=data[23:16];g=data[15:8];b=data[7:0];
    expected_r=(r*gain+128)>>8;expected_g=(g*gain+128)>>8;expected_b=(b*gain+128)>>8;
    if(expected_r>255||expected_g>255||expected_b>255)$fatal(1,"preclamp overflow");
    if(result!=={8'(expected_r),8'(expected_g),8'(expected_b)})$fatal(1,"common RGB product mismatch");
    if(s==0&&result!==data)$fatal(1,"L0 RGB bypass changed");
    if(s==1&&result!==old_result)$fatal(1,"L1 archived RGB mismatch");
    if(s>0&&p>=208)begin
     if(result!==old_result)$fatal(1,"highlight archived RGB mismatch");
     highlights=highlights+1;
    end
    for(channel=0;channel<3;channel=channel+1)begin
     case(channel)
      0:begin actual=result[23:16];err=actual*256-r*gain;ratio_err=actual*p-r*targets[s*256+p];end
      1:begin actual=result[15:8];err=actual*256-g*gain;ratio_err=actual*p-g*targets[s*256+p];end
      2:begin actual=result[7:0];err=actual*256-b*gain;ratio_err=actual*p-b*targets[s*256+p];end
     endcase
     if(err>128||err< -128)$fatal(1,"rounding bound exceeded");
     if(ratio_err>p||ratio_err< -p)$fatal(1,"RGB ratio bound exceeded");
    end
    if((r<255&&result[23:16]==255)||(g<255&&result[15:8]==255)||(b<255&&result[7:0]==255))
     $fatal(1,"new255 mapping");
    n=n+1;
   end
   de=0;#1;if(result!==data)$fatal(1,"blanking bypass");de=1;
   en=0;#1;if(result!==data)$fatal(1,"noncolour bypass");en=1;bypasses=bypasses+2;
  end
 end
 $display("PASS natural numeric: RGB%0d peaks%0d exact_highlight_RGB%0d bypass%0d",n,peak_checks,highlights,bypasses);$finish;
end
endmodule
'''.replace('TARGETS', target_file.as_posix())
        log = run('numeric', numeric, [legacy_file])
        result = re.search(r'RGB(\d+) peaks(\d+) exact_highlight_RGB(\d+) bypass(\d+)', log)
        assert result
        summary.update(rgb_rotation_cases=int(result[1]), independent_peak_targets=int(result[2]),
                       highlight_rgb_equivalence_cases=int(result[3]), bypass_cases=int(result[4]),
                       l0_identity=True, l1_archived_coefficients_and_rgb_exact=True,
                       highlight_ge208_archived_l1_exact=True, monotone_peak_targets=True,
                       no_new255_mapping_or_overflow=True, common_rgb_rounding_bound_code=0.5,
                       common_rgb_ratio_bound_code=1,
                       exhaustive_multiplier_domain_repeated=False)
        top = (hdl / 'design_top_wrapper.v').read_text(encoding='utf-8')
        assert re.search(r'ae_set\s*#\(\.EXP_RST\(3\),\s*\.GAIN_COMPARE_EN\(1\),\s*\.GAIN_RST\(1\),\s*\.GAIN12_EN\(1\)\)', top)
        assert re.search(r'\.REGION_RST\s*\(\s*1\s*\)', top)
        assert re.search(r'\.REGION_N\s*\(\s*4\s*\)', top)
        run('controls', r'''
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rstn=0;reg[3:0] keys=15;wire[2:0] mode;wire[3:0] lift;
wire[15:0] ae,ag;wire req;
img_mode_sel #(.CLK_HZ(1000),.DB_MS(1),.REGION_RST(1),.REGION_N(4)) ui(
 .I_clk(clk),.I_rst_n(rstn),.I_key_n(keys),.O_mode(mode),.O_region_sel(lift));
ae_set #(.EXP_RST(3),.GAIN_COMPARE_EN(1),.GAIN_RST(1),.GAIN12_EN(1)) sensor(
 .I_clk(clk),.I_rst(!rstn),.I_btn(4'b1111),.I_exp_key_n(1'b1),
 .I_ae_cfg_done(1'b1),.I_cam_cfg_done(1'b1),.O_ae_req(req),.O_ae(ae),.O_ag(ag));
task press;input integer bitno;begin
 @(negedge clk);keys[bitno]=0;repeat(15)@(negedge clk);
 keys[bitno]=1;repeat(15)@(negedge clk);
end endtask
integer k;
initial begin
 #1;rstn=1;#1;rstn=0;repeat(4)@(negedge clk);rstn=1;
 repeat(12)@(negedge clk);
 if(lift!==1||mode!==0||ae!==900||ag!==128)$fatal(1,"wrong startup");
 for(k=0;k<8;k=k+1)begin
  press(3);if(lift!==((k+2)%4))$fatal(1,"KEY4 wrap");
  if(ae!==900||ag!==128)$fatal(1,"KEY4 changed sensor");
 end
 press(1);if(mode!==1)$fatal(1,"gray");press(1);if(mode!==2)$fatal(1,"binary");
 press(1);if(mode!==3)$fatal(1,"Sobel");press(0);if(mode!==0)$fatal(1,"colour");
 if(lift!==1)$fatal(1,"mode key changed lift");
 $display("PASS controls: L1 reset,8 KEY4 presses,4 modes; sensor E900/code128 independent");$finish;
end
endmodule
''')
        summary['controls'] = {'default_nominal_gain': 12, 'default_exposure': 900,
                               'default_profile_index': 1, 'key4_presses': 8, 'image_modes': 4,
                               'key4_does_not_change_sensor': True}
        summary['pass'] = True
    except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
        summary['error'] = str(error)
        print('FAIL natural lift:', error, flush=True)
    finally:
        (out / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return 0 if summary['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
