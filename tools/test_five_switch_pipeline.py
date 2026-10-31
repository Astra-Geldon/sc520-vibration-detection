"""Prove all-ON five-switch N1/mixer matches the accepted candidate.

The status panel is independently checked against archived baseline pixels.
Here both paths use the same final overlay to compare the extracted lift/mixer
against the archived numerical processor and original mixer at every cycle.

Uses committed b8407f8 as the pixel reference and the original 42b0736 mixer
as the independent pre-stage timing reference. The cleaned production top's
actual peak logic, metadata, lift, OSD and mixer instances are extracted.
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
    hdl = root/'user_source/hdl_source'
    out = args.output.resolve()
    numeric_out = out.parent/'numeric-checks'
    out.mkdir(parents=True, exist_ok=True)
    numeric_out.mkdir(parents=True, exist_ok=True)
    compiler = Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin/iverilog.exe')
    files = [hdl/name for name in ['design_top_wrapper.v', 'fixed_n1_lift.v',
             'hdmi_mixer.v', 'osd_overlay.v', 'osd_font_rom.v', 'osd_logo_rom.v']]
    hashes = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    summary = {'pass': False, 'scope': 'Actual fixed N1 top instances versus archived N1 pre-stage processor and original mixer',
               'source_sha256': hashes, 'accepted_reference': 'b8407f8', 'original_mixer_ref': '42b0736'}
    numeric_summary = {'pass': False, 'scope': 'Fixed N1 real RTL versus archived b8407f8 candidate2; complete peak/subordinate RGB rotations',
                       'source_sha256': {k:v for k,v in hashes.items() if k.endswith('fixed_n1_lift.v')}}

    def run(name, bench, folder, dependencies, timeout):
        tb = folder/(name+'.v')
        tb.write_text(bench, encoding='utf-8', newline='\n')
        binary = folder/(name+'.vvp')
        built = subprocess.run([str(compiler), '-g2012', '-s', 'tb', '-o', str(binary), str(tb)]
                               + [str(p) for p in dependencies], capture_output=True, text=True, errors='replace', timeout=60)
        (folder/'compile.log').write_text(built.stdout+built.stderr, encoding='utf-8')
        assert built.returncode == 0, built.stdout+built.stderr
        with (folder/'simulation.log').open('w', encoding='utf-8', buffering=1) as log:
            child = subprocess.Popen([str(compiler.with_name('vvp.exe')), '-i', str(binary)],
                                     cwd=root, stdout=log, stderr=subprocess.STDOUT, text=True, errors='replace')
            try:
                code = child.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
                raise
        text = (folder/'simulation.log').read_text(encoding='utf-8')
        print(text, end='', flush=True)
        assert code == 0 and 'PASS ' in text, text
        return text

    try:
        archived = subprocess.check_output(['git','show','b8407f8:user_source/hdl_source/highlight_tone.v'], cwd=root).decode('utf-8')
        archived = archived[archived.index('module gain8_lift_gain('):]
        archived = re.sub(r'\bgain8_lift(?:_gain|_channel)?\b', lambda m: 'legacy_'+m[0], archived)
        legacy = numeric_out/'archived_N1.v'
        legacy.write_text(archived, encoding='utf-8', newline='\n')
        numeric_summary['archived_N1_module_sha256'] = hashlib.sha256(legacy.read_bytes()).hexdigest()
        log = run('tb_fixed_n1_numeric', r'''
`timescale 1ns/1ps
module tb;
reg [7:0] peak=0;
reg [23:0] data=0;
reg de=1,en=1;
wire [23:0] result,reference;
wire [10:0] gain,old_gain;
integer p,v,c,n=0,highlights=0,bypasses=0,last=-1;
fixed_n1_gain lut(.I_peak(peak),.O_gain(gain));
legacy_gain8_lift_gain old_lut(.I_peak(peak),.I_sel(2'd2),.O_gain(old_gain));
fixed_n1_lift dut(.I_de(de),.I_enable(en),.I_data(data),.I_peak(peak),.O_data(result));
legacy_gain8_lift old_dut(.I_de(de),.I_enable(en),.I_sel(2'd2),.I_data(data),.I_peak(peak),.O_data(reference));
initial begin
 for(p=0;p<256;p=p+1)begin
  peak=p;data={8'(p),8'(p),8'(p)};#1;
  if(gain!==old_gain)$fatal(1,"N1 gain mismatch p%0d",p);
  if(result!==reference)$fatal(1,"N1 gray mismatch p%0d",p);
  if(p>0&&result[23:16]<last)$fatal(1,"nonmonotone peak");
  last=result[23:16];
  if(p>=192&&gain!==256)$fatal(1,"high-peak gain not unity");
  for(v=0;v<=p;v=v+1)for(c=0;c<3;c=c+1)begin
   case(c)
    0:data={8'(p),8'(v),8'(v/2)};
    1:data={8'(v),8'(v/2),8'(p)};
    2:data={8'(v/2),8'(p),8'(v)};
   endcase
   #1;if(result!==reference)$fatal(1,"N1 RGB mismatch p%0d v%0d c%0d",p,v,c);
   if(p>=192)begin
    if(result!==data)$fatal(1,"high-peak RGB changed");
    highlights=highlights+1;
   end
   n=n+1;
  end
  de=0;#1;if(result!==data)$fatal(1,"blanking bypass");de=1;
  en=0;#1;if(result!==data)$fatal(1,"other-mode bypass");en=1;
  bypasses=bypasses+2;
 end
 $display("PASS fixed_numeric RGB%0d high_RGB%0d bypass%0d",n,highlights,bypasses);$finish;
end
endmodule
''', numeric_out, [hdl/'fixed_n1_lift.v', legacy], 300)
        match = re.search(r'PASS fixed_numeric RGB(\d+) high_RGB(\d+) bypass(\d+)',log)
        assert match
        numeric_summary.update({'pass': True, 'rgb_rotation_cases': int(match[1]),
                                'highlight_rgb_identity_cases': int(match[2]), 'bypass_cases': int(match[3]),
                                'all_256_gain_coefficients_exact': True, 'monotone_peak_targets': True,
                                'highlight_ge192_input_identity': True})
        (numeric_out/'summary.json').write_text(json.dumps(numeric_summary,indent=2)+'\n',encoding='utf-8')

        top = (hdl/'design_top_wrapper.v').read_text(encoding='utf-8')
        def instance(marker):
            start = top.index(marker)
            return top[start:top.index('    );',start)+len('    );')]
        tone = instance('    fixed_n1_lift u_n1_lift (')
        osd = instance('    osd_overlay #(')
        mixer = instance('    hdmi_mixer #(')
        start = top.rfind('    always @(posedge S_hdmi_pixel_clk',0,top.index('    fixed_n1_lift u_n1_lift ('))
        metadata = top[start:top.index('    fixed_n1_lift u_n1_lift (')]
        assert "S_tone_stage_mode <= S_img_mode;" in metadata
        assert "S_tone_stage_peak <= S_tone_input_peak;" in metadata
        assert '.PIXEL_STAGE_EN ( 1 )' in mixer
        start = top.index('    wire [7:0] S_lift_rg_max')
        peak_logic = top[start:top.index('    reg [7:0] S_tone_stage_peak;',start)]
        original = subprocess.check_output(['git','show','42b0736:user_source/hdl_source/hdmi_mixer.v'],cwd=root)
        original_file = out/'hdmi_mixer_original.v'
        original_file.write_bytes(original.replace(b'module hdmi_mixer #(',b'module hdmi_mixer_original #(',1))
        reference_osd = osd.replace('u_osd_overlay(','reference_osd(')
        for old,new in {'S_tone_stage_de':'S_hdmi_de','S_tone_stage_vs':'S_hdmi_vsync',
                        'S_tone_stage_mode':'S_img_mode','S_lift_data':'reference_tone','S_osd_mix':'reference_osd_data'}.items():
            reference_osd=reference_osd.replace(old,new)
        harness=r'''
`timescale 1ns/1ps
module tb;
reg S_hdmi_pixel_clk=0;
always #6.666667 S_hdmi_pixel_clk=~S_hdmi_pixel_clk;
reg S_hdmi_rst_n=0;
reg S_hdmi_vsync=0,S_hdmi_hsync=0,S_hdmi_de=0,S_hdmi_user=0,S_hdmi_last=0;
reg [23:0] S_imgp_data=0;
reg [2:0] S_img_mode=7;
wire [4:0] S_demo_hdmi=5'b11111;
wire S_demo_raw=1'b0;
wire [5:0] S_demo_alg_state=6'b111111, S_demo_alg_pending=6'b000000;
reg [7:0] S_tone_stage_peak;
reg [2:0] S_tone_stage_mode;
wire [23:0] S_tone_stage_data,S_lift_data,S_osd_mix,S_hdmi_out_data;
wire S_tone_stage_de,S_tone_stage_vs,S_hdmi_window_rd_en;
wire S_hdmi_out_vsync,S_hdmi_out_hsync,S_hdmi_out_de;
wire [23:0] reference_tone,reference_osd_data,reference_data;
wire reference_vs,reference_hs,reference_de,reference_read;
integer checks=0,reads=0,age=0;
integer f,x,y,rows,old_reads;
reg [31:0] noise=32'h1a35beef;
always @(posedge S_hdmi_pixel_clk)begin
 if(S_hdmi_rst_n&&age>5&&reference_read)reads=reads+1;
 #1;
 if(!S_hdmi_rst_n)age=0;
 else begin
  age=age+1;
  if(age>5)begin
   if({S_hdmi_out_vsync,S_hdmi_out_hsync,S_hdmi_out_de,S_hdmi_out_data} !==
      {reference_vs,reference_hs,reference_de,reference_data})
      $fatal(1,"fixed pipeline mismatch cycle%0d mode%0d xy%0d/%0d actual%06x ref%06x",checks,S_img_mode,x,y,S_hdmi_out_data,reference_data);
   if(S_hdmi_window_rd_en!==reference_read)$fatal(1,"DDR read changed");
   checks=checks+1;
  end
 end
end
legacy_gain8_lift reference_processor(
 .I_de(S_hdmi_de),.I_enable(S_img_mode==0),.I_sel(2'd2),
 .I_data(S_imgp_data),.I_peak(S_tone_input_peak),.O_data(reference_tone));
hdmi_mixer_original #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.DEBUG_MODE(0)) reference_mixer(
 .I_clk(S_hdmi_pixel_clk),.I_rst_n(S_hdmi_rst_n),
 .I_video_vsync(S_hdmi_vsync),.I_video_hsync(S_hdmi_hsync),.I_video_de(S_hdmi_de),
 .I_video_user(S_hdmi_user),.I_video_last(S_hdmi_last),.I_debug_status(4'd0),
 .O_video_rd_en(reference_read),.I_video_rd_data(reference_osd_data),
 .O_hdmi_vsync(reference_vs),.O_hdmi_hsync(reference_hs),.O_hdmi_de(reference_de),.O_hdmi_data(reference_data));
'''+peak_logic+metadata+tone+osd+mixer+reference_osd+r'''
task blank;
 input integer cycles;
 integer n;
 begin
  for(n=0;n<cycles;n=n+1)begin
   @(negedge S_hdmi_pixel_clk);S_hdmi_de=0;S_hdmi_last=0;S_imgp_data=24'h987654;
  end
 end
endtask
initial begin
 #1 S_hdmi_rst_n=1;#1 S_hdmi_rst_n=0;
 blank(8);@(negedge S_hdmi_pixel_clk);S_hdmi_rst_n=1;blank(10);
 for(f=0;f<6;f=f+1)begin
  @(negedge S_hdmi_pixel_clk);S_hdmi_vsync=1;S_hdmi_user=1;
  S_img_mode=(f<2)?0:f-2;
  blank(8);@(negedge S_hdmi_pixel_clk);S_hdmi_vsync=0;S_hdmi_user=0;
  rows=(f<2)?720:96;old_reads=reads;
  for(y=0;y<rows;y=y+1)begin
   if(y%120==0)$display("PROGRESS frame%0d row%0d/%0d",f,y,rows);
   S_hdmi_hsync=1;blank(8);S_hdmi_hsync=0;
   for(x=0;x<1280;x=x+1)begin
    @(negedge S_hdmi_pixel_clk);S_hdmi_de=1;S_hdmi_last=(x==1279);
    noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
    S_imgp_data=noise[23:0];
    if((x>f*7+200&&x<f*7+320&&y<40)||x==0||x==1279)S_imgp_data=24'hffffff;
    if(f==1&&x%103==0)S_img_mode=(x/103)%4;
   end
   blank(5);
  end
  blank(12);
  if(reads-old_reads!=1280*rows)$fatal(1,"frame%0d read count %0d",f,reads-old_reads);
  $display("PASS fixed pipeline frame%0d rows%0d",f,rows);
 end
 blank(12);@(negedge S_hdmi_pixel_clk);S_hdmi_rst_n=0;blank(4);
 @(negedge S_hdmi_pixel_clk);S_hdmi_rst_n=1;blank(12);
 $display("PASS fixed_pipeline cycles%0d reads%0d",checks,reads);$finish;
end
endmodule
'''
        log=run('tb_fixed_n1_pipeline',harness,out,
                [legacy,original_file]+[p for p in files if p.name!='design_top_wrapper.v'],1800)
        match=re.search(r'PASS fixed_pipeline cycles(\d+) reads(\d+)',log)
        assert match
        # The coordinator may tidy unrelated comments while the long simulation
        # runs. Rebind only if every tested fragment is still exactly the same
        # RTL after removing comments/whitespace; other dependencies must match.
        def compact(value):
            return re.sub(r'\s+', '', re.sub(r'/\*.*?\*/|//[^\n]*', '', value, flags=re.S))
        current_top = files[0].read_text(encoding='utf-8')
        compact_top = compact(current_top)
        for fragment in [peak_logic, metadata, tone, osd, mixer]:
            assert compact(fragment) in compact_top, 'Tested top RTL changed during simulation'
        for path in files[1:]:
            assert hashlib.sha256(path.read_bytes()).hexdigest() == hashes[path.relative_to(root).as_posix()], path
        summary['top_source_updated_outside_tested_RTL'] = current_top != top
        hashes[files[0].relative_to(root).as_posix()] = hashlib.sha256(files[0].read_bytes()).hexdigest()
        summary.update({'pass':True,'cycles':int(match[1]),'identical_ddr_reads':int(match[2]),
                        'full_720p_frames':2,'extra_mode_frames':4,'production_top_instances_extracted':True,
                        'pixel_latency_unchanged':True,'archived_N1_pixels_exact':True,
                        'OSD_scope':'Current final algorithm name/Logo; removed test labels intentionally excluded from acceptance'})
    except (AssertionError,OSError,ValueError,subprocess.SubprocessError) as error:
        summary['error']=str(error)
        print('FAIL fixed N1 pipeline:',error,flush=True)
    finally:
        (numeric_out/'summary.json').write_text(json.dumps(numeric_summary,indent=2)+'\n',encoding='utf-8')
        (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    return 0 if summary['pass'] else 1


if __name__=='__main__':
    raise SystemExit(main())
