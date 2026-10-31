"""Independent numerical, UI and reset checks for the RGB8 lift candidate."""
from pathlib import Path
import argparse, hashlib, json, subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    hdl = root / 'user_source/hdl_source'
    out = args.output
    out.mkdir(parents=True, exist_ok=True)
    iv = Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin/iverilog.exe')
    files = [hdl / x for x in ['highlight_tone.v', 'osd_overlay.v', 'osd_font_rom.v',
                              'osd_logo_rom.v', 'img_mode_sel.v', 'uiisp_beta/ae_set.v']]
    summary = dict(pass_=False, tests={}, source_sha256={p.relative_to(root).as_posix():
        hashlib.sha256(p.read_bytes()).hexdigest() for p in files + [hdl/'design_top_wrapper.v']})

    def run(name, bench):
        tb = out / (name + '.v')
        tb.write_text(bench, encoding='utf-8')
        vvp = out / (name + '.vvp')
        r = subprocess.run([str(iv), '-g2012', '-s', 'tb', '-o', str(vvp), str(tb)] +
                           [str(p) for p in files], capture_output=True, text=True, errors='replace')
        (out/(name+'_compile.log')).write_text(r.stdout+r.stderr, encoding='utf-8')
        assert r.returncode == 0, r.stdout+r.stderr
        r = subprocess.run([str(iv.with_name('vvp.exe')), str(vvp)], capture_output=True,
                           text=True, errors='replace', timeout=240)
        (out/(name+'.log')).write_text(r.stdout+r.stderr, encoding='utf-8')
        print(r.stdout+r.stderr, flush=True)
        assert r.returncode == 0 and 'PASS ' in r.stdout, name
        summary['tests'][name] = {'pass': True, 'log': name+'.log'}

    try:
        # Integer target from the rational curve, independent of stored gains.
        targets = []
        for sel in range(4):
            values = []
            for p in range(256):
                a = sel+1
                n, d = 255*(a+1)*p, 255+a*p
                t = p if sel == 0 else (n+d//2)//d
                if sel and p < 255:
                    t = min(t, 254)
                values.append(t)
            assert all(a <= b for a,b in zip(values,values[1:]))
            targets.extend(values)
        target_file = out/'targets.hex'
        target_file.write_text('\n'.join(f'{v:02x}' for v in targets)+'\n', encoding='ascii')
        bench = r'''
`timescale 1ns/1ps
module tb;
reg[7:0] pixel=0,peak=0;reg[10:0] coefficient=0;wire[7:0] channel;
reg[1:0] sel=0;wire[10:0] gain;
reg[23:0] data=0;wire[23:0] result;reg de=1,en=1;
reg[7:0] targets[0:1023];integer g,v,p,s,c,n=0,expected,gr,gg,gb;
gain8_lift_channel mul(.I_pixel(pixel),.I_gain(coefficient),.O_pixel(channel));
gain8_lift_gain lut(.I_peak(peak),.I_sel(sel),.O_gain(gain));
gain8_lift dut(.I_de(de),.I_enable(en),.I_sel(sel),.I_data(data),.I_peak(peak),.O_data(result));
initial begin
 $readmemh("TARGETS",targets);
 // Complete 8x11-bit product domain, including unused large coefficients.
 for(g=0;g<2048;g=g+1) for(v=0;v<256;v=v+1)begin
  coefficient=g;pixel=v;#1;expected=(g*v+128)>>8;if(expected>255)expected=255;
  if(channel!==expected[7:0])$fatal(1,"partial-product error g%0d v%0d",g,v);
  n=n+1;
 end
 for(s=0;s<4;s=s+1)for(p=0;p<256;p=p+1)begin
  sel=s;peak=p;data={8'(p),8'(p),8'(p)};#1;
  if(result!=={targets[s*256+p],targets[s*256+p],targets[s*256+p]})
   $fatal(1,"curve error s%0d p%0d result%h target%h",s,p,result,targets[s*256+p]);
  // Every subordinate channel at every peak, in three channel rotations.
  for(v=0;v<=p;v=v+1)for(c=0;c<3;c=c+1)begin
   case(c)
    0:data={8'(p),8'(v),8'(v/2)};
    1:data={8'(v),8'(v/2),8'(p)};
    2:data={8'(v/2),8'(p),8'(v)};
   endcase
   #1;gr=(data[23:16]*gain+128)>>8;gg=(data[15:8]*gain+128)>>8;gb=(data[7:0]*gain+128)>>8;
   if(result!=={8'(gr),8'(gg),8'(gb)})$fatal(1,"RGB scaling mismatch");
   if(gr>255||gg>255||gb>255)$fatal(1,"new clipping");
   de=0;#1;if(result!==data)$fatal(1,"blanking bypass");de=1;
   en=0;#1;if(result!==data)$fatal(1,"other mode bypass");en=1;
   n=n+1;
  end
 end
 $display("PASS lift numeric: %0d checks, all products, all peaks, all subordinate channels, bypass",n);$finish;
end
endmodule
'''.replace('TARGETS', target_file.as_posix())
        run('numeric', bench)
        summary['exhaustive_product_pairs'] = 524288
        summary['monotone_peak_targets'] = 1024
        summary['rgb_subordinate_cases'] = 394752
        run('controls', r'''
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rstn=0;reg[3:0] keys=15;wire[2:0] mode;wire[3:0] lift;
wire[15:0] ae,ag;wire req;
img_mode_sel #(.CLK_HZ(1000),.DB_MS(1),.REGION_RST(1),.REGION_N(4)) ui(
 .I_clk(clk),.I_rst_n(rstn),.I_key_n(keys),.O_mode(mode),.O_region_sel(lift));
ae_set #(.EXP_RST(3),.GAIN_COMPARE_EN(1),.GAIN_RST(2)) sensor(
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
 if(lift!==1||mode!==0||ae!==900||ag!==112)$fatal(1,"wrong startup");
 for(k=0;k<8;k=k+1)begin
  press(3);if(lift!==((k+2)%4))$fatal(1,"KEY4 wrap");
  if(ae!==900||ag!==112)$fatal(1,"KEY4 changed sensor");
 end
 press(1);if(mode!==1)$fatal(1,"gray");press(1);if(mode!==2)$fatal(1,"binary");
 press(1);if(mode!==3)$fatal(1,"Sobel");press(0);if(mode!==0)$fatal(1,"colour");
 if(lift!==1)$fatal(1,"mode key changed lift");
 $display("PASS controls: L1 reset,8 KEY4 presses,4 modes; sensor E900/code112 independent");$finish;
end
endmodule
''')
        summary['pass_'] = True
    except (AssertionError,OSError,subprocess.SubprocessError) as exc:
        summary['error'] = str(exc)
        print('FAIL',exc,flush=True)
    finally:
        summary['pass'] = summary.pop('pass_')
        (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    return 0 if summary['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
