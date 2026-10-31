"""Check production KEY1/KEY2 controls and normal name/Logo RTL.

The normal OSD is compared with the archived A+Logo implementation; the
accepted N1 candidate is also checked outside the deliberately removed label
areas. All simulator files and logs go under --output, never the workspace root.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    hdl = root / 'user_source/hdl_source'
    iv = Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin/iverilog.exe')
    files = [hdl / name for name in ['img_mode_sel.v', 'osd_overlay.v',
                                     'osd_font_rom.v', 'osd_logo_rom.v']]
    summary = {'pass': False, 'scope': 'Real KEY1/KEY2 debounce and normal-mode priority; archived A+Logo name/Logo equivalence, removed experiment labels and unchanged coordinate timing',
               'source_sha256': {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in files}, 'tests': {}}

    def run(name, bench, extra=()):
        tb = out / (name + '.v')
        tb.write_text(bench, encoding='utf-8', newline='\n')
        binary = out / (name + '.vvp')
        result = subprocess.run([str(iv), '-g2012', '-s', 'tb', '-o', str(binary), str(tb)]
                                + [str(p) for p in files + list(extra)],
                                capture_output=True, text=True, errors='replace', timeout=60)
        (out / (name + '_compile.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        assert result.returncode == 0, result.stdout + result.stderr
        result = subprocess.run([str(iv.with_name('vvp.exe')), str(binary)],
                                capture_output=True, text=True, errors='replace', timeout=180)
        (out / (name + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        assert result.returncode == 0 and 'PASS ' in result.stdout, result.stdout + result.stderr
        summary['tests'][name] = {'pass': True, 'log': name + '.log'}
        print(result.stdout, flush=True)
        return result.stdout

    try:
        refs = []
        for commit, suffix in [('ee675b6', 'baseline'), ('b8407f8', 'accepted')]:
            text = subprocess.check_output(['git', 'show', commit + ':user_source/hdl_source/osd_overlay.v'], cwd=root).decode('utf-8')
            for module in ['osd_overlay', 'osd_gain_line', 'osd_region_line', 'osd_threshold_line']:
                text = re.sub(r'\b' + module + r'\b', module + '_' + suffix, text)
            path = out / ('osd_' + suffix + '.v')
            path.write_text(text, encoding='utf-8', newline='\n')
            refs.append(path)
        for name in ['osd_font_rom.v', 'osd_logo_rom.v']:
            before = subprocess.check_output(['git', 'show', 'ee675b6:user_source/hdl_source/' + name], cwd=root)
            assert (hdl/name).read_bytes() == before, name + ' asset changed'
        summary['font_and_logo_assets_equal_A_logo'] = True
        run('controls', r'''
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rstn=0;reg[1:0] keys=3;wire[2:0] mode,alt;
img_mode_sel #(.CLK_HZ(1000),.DB_MS(4)) dut(.I_clk(clk),.I_rst_n(rstn),.I_key_n(keys),.O_mode(mode));
img_mode_sel #(.MODE_RST(3),.CLK_HZ(1000),.DB_MS(4)) startup(.I_clk(clk),.I_rst_n(rstn),.I_key_n(keys),.O_mode(alt));
task cycles;input integer count;begin repeat(count)@(negedge clk);end endtask
task press;input[1:0] mask;input integer hold;begin
 @(negedge clk);keys=~mask;cycles(hold);keys=3;cycles(20);
end endtask
integer n;
initial begin
 #1;rstn=1;#1;rstn=0;cycles(3);rstn=1;cycles(12);
 if(mode!==0||alt!==3)$fatal(1,"reset modes");
 // A low pulse shorter than the stable-count threshold must not press KEY2.
 press(2'b10,2);if(mode!==0||alt!==3)$fatal(1,"short bounce accepted");
 press(2'b10,20);if(mode!==1||alt!==1)$fatal(1,"enter gray");
 press(2'b10,80);if(mode!==2)$fatal(1,"hold repeated or failed binary");
 cycles(40);if(mode!==2)$fatal(1,"release changed mode");
 press(2'b10,20);if(mode!==3)$fatal(1,"Sobel");
 press(2'b10,20);if(mode!==1)$fatal(1,"gray wrap");
 press(2'b01,20);if(mode!==0)$fatal(1,"KEY1 color");
 press(2'b11,30);if(mode!==0)$fatal(1,"simultaneous priority");
 for(n=0;n<6;n=n+1)begin
  press(2'b10,20);if(mode!==((n%3)+1))$fatal(1,"mode cycle %0d",n);
 end
 rstn=0;#1;if(mode!==0||alt!==3)$fatal(1,"asynchronous reset");
 $display("PASS fixed UI: reset0/3,short bounce rejection,long hold single event,KEY1 priority,10 KEY2 transitions");$finish;
end
endmodule
''')
        log = run('osd', r'''
`timescale 1ns/1ps
module tb;
reg[10:0] x=0;reg[9:0] y=0;reg[2:0] mode=7;
reg[23:0] data=24'h79532b;wire[23:0] actual[0:2],baseline[0:1],accepted;
integer m,gx,gy,n=0,same_accepted=0,removed=0,colours=0,width;
genvar i;
generate for(i=0;i<3;i=i+1)begin:prod
 osd_overlay #(.OSD_EN(i!=2),.LOGO_EN(i!=1)) dut(
 .I_clk(1'b0),.I_rst_n(1'b0),.I_de(1'b1),.I_vs(1'b0),.I_mode(mode),.I_data(data),.O_data(actual[i]));
 initial begin force dut.S_x=x;force dut.S_y=y;end
end
for(i=0;i<2;i=i+1)begin:original
 osd_overlay_baseline #(.LOGO_EN(i==0)) dut(
 .I_clk(1'b0),.I_rst_n(1'b0),.I_de(1'b1),.I_vs(1'b0),.I_mode(mode),.I_src_raw(1'b0),
 .I_k_sel(2'd2),.I_threshold(8'd128),.I_th_locked(1'b0),.I_data(data),.O_data(baseline[i]));
 initial begin force dut.S_x=x;force dut.S_y=y;end
end endgenerate
osd_overlay_accepted #(.GAIN_DEBUG_EN(1),.LIFT_DEBUG_EN(1),.NATURAL_LIFT_EN(1),.GAIN12_EN(1)) old(
 .I_clk(1'b0),.I_rst_n(1'b0),.I_de(1'b1),.I_vs(1'b0),.I_mode(mode),.I_src_raw(1'b0),
 .I_k_sel(2'd2),.I_exp_sel(2'd3),.I_region_sel(4'd2),.I_gain_sel(2'd1),.I_gain_verified(1'b0),
 .I_lift_sel(2'd2),.I_threshold(8'd128),.I_th_locked(1'b0),.I_data(data),.O_data(accepted));
initial begin force old.S_x=x;force old.S_y=y;end
initial begin
 #1;mode=7;#1;
 for(m=0;m<4;m=m+1)begin
  mode=m;width=(m==2)?48:32;
  // All coordinates in the full-width top104 lines cover every name/Logo,
  // removed suffix/debug row, their borders and background pixels.
  for(gy=0;gy<104;gy=gy+1)for(gx=0;gx<1280;gx=gx+1)begin
   x=gx;y=gy;data=24'h79532b^(gx+gy*1280);#1;
   if(actual[0]!==baseline[0]||actual[1]!==baseline[1])$fatal(1,"A+Logo mismatch mode%0d x%0d y%0d actual%h baseline%h",m,gx,gy,actual[0],baseline[0]);
   if(actual[2]!==data)$fatal(1,"disabled OSD not bypass");
   if(!((gx>=24+width&&gx<24+width+24&&gy>=16&&gy<48)||
        (gx>=20&&gx<244&&gy>=52&&gy<74)))begin
    if(actual[0]!==accepted)$fatal(1,"accepted area changed mode%0d x%0d y%0d",m,gx,gy);
    same_accepted=same_accepted+1;
   end
   if(gx>=20&&gx<244&&gy>=52&&gy<74)begin
    if(actual[0]!==data)$fatal(1,"diagnostic row remains");removed=removed+1;
   end
   if(actual[0]==24'h1b3a66||actual[0]==24'he8382f)colours=colours+1;
   n=n+1;
  end
  for(gy=650;gy<720;gy=gy+1)for(gx=0;gx<128;gx=gx+1)begin
   x=gx;y=gy;#1;if(actual[0]!==data)$fatal(1,"old k row remains");n=n+1;
  end
 end
 if(colours!=4*4198)$fatal(1,"Logo colored pixels %0d",colours);
 $display("PASS fixed OSD: vectors%0d accepted_area%0d removed_debug%0d Logo_coloured%0d modes4,Logo_off,OSD_off",n,same_accepted,removed,colours);$finish;
end
endmodule
''', refs)
        match = re.search(r'vectors(\d+) accepted_area(\d+) removed_debug(\d+) Logo_coloured(\d+)', log)
        assert match
        summary.update(osd_coordinates=int(match[1]), accepted_unchanged_coordinates=int(match[2]),
                       removed_diagnostic_coordinates=int(match[3]), logo_coloured_pixels_per_mode=int(match[4])//4,
                       image_modes=4, normal_OSD_reference='ee675b6', accepted_reference='b8407f8',
                       only_normal_key1_key2_ports=True, normal_mode_priority_and_debounce_pass=True)
        run('coordinates', r'''
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rstn=0,de=0,vs=0;wire[23:0] value,oldvalue;
osd_overlay dut(.I_clk(clk),.I_rst_n(rstn),.I_de(de),.I_vs(vs),.I_mode(3'd0),.I_data(24'h79532b),.O_data(value));
osd_overlay_baseline old(.I_clk(clk),.I_rst_n(rstn),.I_de(de),.I_vs(vs),.I_mode(3'd0),.I_src_raw(1'b0),
 .I_k_sel(2'd2),.I_threshold(8'd128),.I_th_locked(1'b0),.I_data(24'h79532b),.O_data(oldvalue));
integer line,p,checks=0;
task check;begin
 @(posedge clk);#1;
 if(dut.S_x!==old.S_x||dut.S_y!==old.S_y||value!==oldvalue)$fatal(1,"coordinate/overlay clock alignment");checks=checks+1;
end endtask
initial begin
 #1;rstn=1;#1;rstn=0;check;@(negedge clk);rstn=1;
 vs=1;check;@(negedge clk);vs=0;
 for(line=0;line<100;line=line+1)begin
  for(p=0;p<1280;p=p+1)begin de=1;check;@(negedge clk);end
  for(p=0;p<8;p=p+1)begin de=0;check;@(negedge clk);end
 end
 vs=1;check;@(negedge clk);vs=0;check;
 rstn=0;#1;if(dut.S_x!==0||dut.S_y!==0)$fatal(1,"OSD asynchronous reset");
 $display("PASS fixed OSD coordinates: checks%0d,100 complete lines,VS andreset exact archived alignment",checks);$finish;
end
endmodule
''', [refs[0]])
        summary['coordinate_checks'] = 128804
        summary['pass'] = True
    except (AssertionError, OSError, subprocess.SubprocessError) as error:
        summary['error'] = str(error)
        print('FAIL fixed UI/OSD:', error, flush=True)
    finally:
        (out/'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    return 0 if summary['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
