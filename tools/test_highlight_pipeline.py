"""Check actual top-level pixel-stage wiring against the original HDMI mixer.

The harness extracts production instances and metadata registers from the top,
then compares a legacy pre-mixer processor with the retimed implementation.
Both must produce identical RGB/sync/read requests, including control changes.
All generated HDL, simulator binaries and logs stay under _build.
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
    output = args.output or root.parent / '_build' / root.name / 'highlight-white-protection-20261031' / 'pipeline_checks'
    output.mkdir(parents=True, exist_ok=True)
    hdl = root / 'user_source/hdl_source'
    top_file = hdl / 'design_top_wrapper.v'
    top = top_file.read_text(encoding='utf-8')
    summary = {'pass': False, 'scope': 'Actual white-prepare/wide-peak/metadata/tone/OSD/mixer versus pre-mixer processor; all11 profiles and4 modes'}
    try:
        def instance(start_text):
            start = top.index(start_text)
            stop = top.index('    );', start) + len('    );')
            return top[start:stop]
        tone_marker = '    highlight_tone #(.PRECOMPUTED_PEAK_EN(1)) u_highlight_tone ('
        peak_start = top.index('    wire [26:0] S_tone_prepared_wide_data;')
        peak_stop = top.index('    reg [8:0] S_tone_stage_peak;', peak_start)
        peak_logic = top[peak_start:peak_stop]
        tone = instance(tone_marker)
        white = instance('    highlight_white_prepare u_highlight_white_prepare (')
        osd = instance('    osd_overlay #(')
        mixer = instance('    hdmi_mixer #(')
        stop = top.index(tone_marker)
        start = top.rfind('    always @(posedge S_hdmi_pixel_clk', 0, stop)
        metadata = top[start:stop]
        assert 'S_tone_stage_mode <= S_img_mode;' in metadata
        assert 'S_tone_stage_peak <= S_tone_input_peak;' in metadata
        assert 'S_tone_stage_wide_data <= S_tone_prepared_wide_data;' in metadata
        assert '.PIXEL_STAGE_EN ( 1 )' in mixer
        assert re.search(r'else if \(S_hdmi_vsync\) S_region_sel <= S_region_sel_req;', top)
        original = subprocess.check_output(['git', 'show', '42b0736:user_source/hdl_source/hdmi_mixer.v'], cwd=root)
        original_file = output / 'hdmi_mixer_original.v'
        original_file.write_bytes(original.replace(b'module hdmi_mixer #(', b'module hdmi_mixer_original #(', 1))
        reference_osd = osd.replace('u_osd_overlay(', 'reference_osd(')
        replacements = {
            'S_tone_stage_de': 'S_hdmi_de', 'S_tone_stage_vs': 'S_hdmi_vsync',
            'S_tone_stage_mode': 'S_img_mode', 'S_tone_stage_raw': 'S_img_src_raw',
            'S_tone_stage_threshold': 'S_img_threshold', 'S_tone_stage_locked': 'S_img_th_locked',
            'S_tone_stage_k': 'S_k_sel', 'S_tone_stage_exp': 'S_exp_sel',
            'S_tone_stage_sel': 'S_region_sel_active',
            'S_region_data': 'reference_tone', 'S_osd_mix': 'reference_osd_data',
        }
        for old, new in replacements.items():
            reference_osd = reference_osd.replace(old, new)
        harness = r'''
`timescale 1ns/1ps
module tb_highlight_pipeline;
reg S_hdmi_pixel_clk=0;
always #6.666667 S_hdmi_pixel_clk=~S_hdmi_pixel_clk;
reg S_hdmi_rst_n=0;
reg S_hdmi_vsync=0,S_hdmi_hsync=0,S_hdmi_de=0,S_hdmi_user=0,S_hdmi_last=0;
reg [23:0] S_imgp_data=0;
reg [26:0] S_csc_wide_data=0;
reg [26:0] S_tone_stage_wide_data;
reg [8:0] S_tone_stage_peak;
reg [2:0] S_img_mode=7;
reg [3:0] S_region_sel_active=7;
reg [1:0] S_exp_sel=2,S_k_sel=2;
reg [7:0] S_img_threshold=48;
reg S_img_src_raw=0,S_img_th_locked=0;
wire [3:0] S_hdmi_debug_status=0;
wire [23:0] S_tone_stage_data,S_region_data,S_osd_mix,S_hdmi_out_data;
wire S_tone_stage_de,S_tone_stage_vs,S_hdmi_window_rd_en;
wire S_hdmi_out_vsync,S_hdmi_out_hsync,S_hdmi_out_de;
reg [2:0] S_tone_stage_mode;
reg [3:0] S_tone_stage_sel;
reg [1:0] S_tone_stage_exp,S_tone_stage_k;
reg [7:0] S_tone_stage_threshold;
reg S_tone_stage_raw,S_tone_stage_locked;
wire [23:0] reference_tone,reference_osd_data,reference_data;
wire [26:0] reference_prepared_wide;
wire reference_vs,reference_hs,reference_de,reference_read;
integer checks=0,reads=0,age=0;
integer f,x,y,m,c,rows,old_reads;
reg [31:0] noise=32'h1a35beef;
always @(posedge S_hdmi_pixel_clk) begin
    // DDR/video_out consume the combinational request AT the edge, before
    // window counters advance. Counting it after NBA loses the final pixel.
    if(S_hdmi_rst_n && age>5 && reference_read) reads=reads+1;
    #1;
    if (!S_hdmi_rst_n) age=0;
    else begin
        age=age+1;
        if (age>5) begin
            if ({S_hdmi_out_vsync,S_hdmi_out_hsync,S_hdmi_out_de,S_hdmi_out_data}
                !== {reference_vs,reference_hs,reference_de,reference_data}) begin
                $display("DEBUG current x/y=%0d/%0d refxy=%0d/%0d dutxy=%0d/%0d pix=%06x pre=%06x refosd=%06x dutpix=%06x dutosd=%06x",
                         x,y,reference_osd.S_x,reference_osd.S_y,u_osd_overlay.S_x,u_osd_overlay.S_y,
                         S_imgp_data,reference_tone,reference_osd_data,S_tone_stage_data,S_osd_mix);
                $fatal(1,"Retiming mismatch at cycle%0d mode%0d candidate%0d: actual=%b/%b/%b/%06x ref=%b/%b/%b/%06x",
                       checks,S_img_mode,S_region_sel_active,S_hdmi_out_vsync,S_hdmi_out_hsync,S_hdmi_out_de,S_hdmi_out_data,
                       reference_vs,reference_hs,reference_de,reference_data);
            end
            if (S_hdmi_window_rd_en !== reference_read)
                $fatal(1,"DDR request changed at cycle%0d",checks);
            checks=checks+1;
        end
    end
end
highlight_white_prepare reference_white (
 .I_enable(S_hdmi_de && S_img_mode==0),.I_white_sel(S_white_sel_active),
 .I_wide_data(S_csc_wide_data),.O_wide_data(reference_prepared_wide));
highlight_tone #(.PRECOMPUTED_PEAK_EN(1)) reference_processor (
 .I_de(S_hdmi_de),.I_enable(S_img_mode==0),
 .I_sel(S_region_sel_active>=8 ? 3'd7 : S_region_sel_active[2:0]),
 .I_data(S_imgp_data),.I_wide_data(reference_prepared_wide),
 .I_peak(S_tone_input_peak),.O_mask(),.O_data(reference_tone));
hdmi_mixer_original #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.DEBUG_MODE(0)) reference_mixer (
 .I_clk(S_hdmi_pixel_clk),.I_rst_n(S_hdmi_rst_n),
 .I_video_vsync(S_hdmi_vsync),.I_video_hsync(S_hdmi_hsync),.I_video_de(S_hdmi_de),
 .I_video_user(S_hdmi_user),.I_video_last(S_hdmi_last),.I_debug_status(4'd0),
 .O_video_rd_en(reference_read),.I_video_rd_data(reference_osd_data),
 .O_hdmi_vsync(reference_vs),.O_hdmi_hsync(reference_hs),.O_hdmi_de(reference_de),.O_hdmi_data(reference_data));
'''
        harness += peak_logic + white + metadata + tone + osd + mixer + reference_osd
        harness += r'''
task blank;
 input integer cycles;
 integer n;
 begin
  for(n=0;n<cycles;n=n+1) begin
   @(negedge S_hdmi_pixel_clk);
   S_hdmi_de=0;S_hdmi_last=0;S_imgp_data=24'h987654;
  end
 end
endtask
initial begin
 #1 S_hdmi_rst_n=1; #1 S_hdmi_rst_n=0;
 blank(8); @(negedge S_hdmi_pixel_clk);S_hdmi_rst_n=1;
 blank(10);
 // Two complete720p moving/random frames, plus all44 mode/candidate pairs.
 for(f=0;f<46;f=f+1) begin
  @(negedge S_hdmi_pixel_clk);
  S_hdmi_vsync=1;S_hdmi_user=1;
  S_img_mode=(f<2)?0:((f-2)/11);
  S_region_sel_active=(f<2)?(f+7):((f-2)%11);
  S_exp_sel=f%4;
  blank(8);
  @(negedge S_hdmi_pixel_clk);S_hdmi_vsync=0;S_hdmi_user=0;
  rows=(f<2)?720:96;
  old_reads=reads;
  for(y=0;y<rows;y=y+1) begin
   if(y%120==0) $display("PROGRESS frame%0d row%0d/%0d",f,y,rows);
   S_hdmi_hsync=1;blank(8);S_hdmi_hsync=0;
   for(x=0;x<1280;x=x+1) begin
    @(negedge S_hdmi_pixel_clk);
    S_hdmi_de=1;S_hdmi_last=(x==1279);
    noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
    S_csc_wide_data = {9'(noise[8:0]%283),9'(noise[17:9]%256),9'(noise[26:18]%276)};
    S_imgp_data=(S_img_mode==0) ? {(S_csc_wide_data[26:18]>255 ? 8'hff : S_csc_wide_data[25:18]),
                                 S_csc_wide_data[16:9],
                                 (S_csc_wide_data[8:0]>255 ? 8'hff : S_csc_wide_data[7:0])} : noise[23:0];
    if ((x>f*7+200 && x<f*7+320 && y<40) || x==0 || x==1279)
      begin S_imgp_data=24'hffffff; S_csc_wide_data={9'd282,9'd255,9'd275}; end
    // Control transitions within active video must retime with their pixel.
    if (f==1 && x%103==0) S_region_sel_active=(x/103)%11;
   end
   blank(5);
  end
  blank(12);
  if(reads-old_reads!=1280*rows)
    $fatal(1,"Frame%0d consumed%0d expected%0d",f,reads-old_reads,1280*rows);
  $display("PASS pipeline frame%0d: rows%0d RGB/sync/request equivalent",f,rows);
 end
 blank(12);
 @(negedge S_hdmi_pixel_clk);S_hdmi_rst_n=0;blank(4);
 @(negedge S_hdmi_pixel_clk);S_hdmi_rst_n=1;blank(12);
 $display("PASS highlight_pipeline: %0d cycles, %0d identical DDR reads; total video latency unchanged",checks,reads);
 $finish;
end
endmodule
'''
        test_file = output / 'tb_highlight_pipeline.v'
        test_file.write_text(harness, encoding='utf-8')
        files = [top_file, hdl/'hdmi_mixer.v', hdl/'highlight_tone.v', hdl/'highlight_region.v', hdl/'highlight_shoulder_lut.v',
                 hdl/'highlight_white_prepare.v',
                 hdl/'osd_overlay.v', hdl/'osd_font_rom.v', hdl/'osd_logo_rom.v']
        files = [path for path in files if path.is_file()]
        summary['source_sha256'] = {path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
        compiler = Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin/iverilog.exe')
        compiled = output/'pipeline.vvp'
        command = [str(compiler), '-g2012', '-I', str(hdl), '-s', 'tb_highlight_pipeline', '-o', str(compiled),
                   str(test_file), str(original_file)] + [str(path) for path in files if path!=top_file]
        build = subprocess.run(command, cwd=root, capture_output=True, text=True, errors='replace', timeout=60)
        (output/'compile.log').write_text(build.stdout+build.stderr, encoding='utf-8')
        assert build.returncode==0, build.stdout+build.stderr
        with (output/'simulation.log').open('w', encoding='utf-8', buffering=1) as logfile:
            run = subprocess.Popen([str(compiler.with_name('vvp.exe')), '-i', str(compiled)], cwd=root, stdout=logfile, stderr=subprocess.STDOUT, text=True, errors='replace')
            try:
                exit_code = run.wait(timeout=1800)
            except subprocess.TimeoutExpired:
                run.kill()
                run.wait()
                raise
        simulation = (output/'simulation.log').read_text(encoding='utf-8')
        print(simulation, end='')
        assert exit_code==0, simulation
        matched=re.search(r'PASS highlight_pipeline: (\d+) cycles, (\d+) identical DDR reads',simulation)
        assert matched, simulation
        summary.update(pass_=True, cycles=int(matched[1]), identical_ddr_reads=int(matched[2]),
                       full_720p_frames=2, extra_mode_candidate_frames=44, original_mixer_ref='42b0736',
                       production_top_instances_extracted=True, pixel_latency_unchanged=True)
        summary['pass']=summary.pop('pass_')
    except (OSError,AssertionError,subprocess.SubprocessError,ValueError) as error:
        summary['error']=str(error)
        print('FAIL highlight_pipeline:',error)
    finally:
        (output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return 0 if summary['pass'] else 1


if __name__=='__main__':
    raise SystemExit(main())
