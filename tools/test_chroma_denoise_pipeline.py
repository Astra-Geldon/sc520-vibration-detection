"""Verify production C3/denoise/OSD wiring without accessing the board.

Extract the actual top-level pipeline instances and registers. Compare against
the previous C3-before-OSD-before-mixer topology at a measured fixed latency;
also check the unchanged DDR request and the real key/VS commit logic. This
test starts at img_proc's output: upstream ISP/algorithm equivalence is outside
its scope. The synchronous ERAM model is shared with the numerical stream test.
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
    parser.add_argument('--iverilog-bin', type=Path,
                        default=Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output or root.parent / '_build' / root.name / 'c3-chroma-denoise-20261031' / 'pipeline'
    output.mkdir(parents=True, exist_ok=True)
    hdl = root / 'user_source/hdl_source'
    top_path = hdl / 'design_top_wrapper.v'
    top = top_path.read_text(encoding='utf-8')
    summary = dict(pass_=False, scope='Actual post-img_proc production wiring, C3/DDR/denoise/OSD/UI',
                   board_access=False, output=str(output))
    try:
        def instance(marker):
            start = top.index(marker)
            stop = top.index('    );', start) + len('    );')
            return top[start:stop]

        def always_before(marker):
            stop = top.index(marker)
            start = top.rfind('    always @(posedge S_hdmi_pixel_clk', 0, stop)
            return top[start:top.index('\n    end', start)+len('\n    end')]

        ui = instance('    img_mode_sel #(')
        assert re.search(r'\.REGION_RST\s*\(\s*0\s*\)', ui)
        assert re.search(r'\.REGION_N\s*\(\s*4\s*\)', ui)
        assert re.search(r'\.EXP_RST\s*\(\s*3\s*\)', ui)
        # Shorten only debounce time; production logic and reset choices remain.
        ui = re.sub(r'(\.CLK_HZ\s*\(\s*)75000000', r'\g<1>1000', ui)
        ui = re.sub(r'(\.DB_MS\s*\(\s*)10', r'\g<1>1', ui)
        commit = always_before('    assign S_region_sel_active')
        commit += '\n' + top[top.index('    assign S_region_sel_active'):top.index(';', top.index('    assign S_region_sel_active'))+1]
        metadata = always_before('    highlight_tone u_highlight_tone (')
        tone = instance('    highlight_tone u_highlight_tone (')
        osd = instance('    osd_overlay #(')
        mixer = instance('    hdmi_mixer #(')
        denoise = instance('    chroma_denoise_stream #(')
        carry = always_before('    chroma_denoise_stream #(')
        decl_start = top.index('    wire [23:0] S_tone_stage_data;')
        decl_stop = top.index('\n', top.index('    wire [19:0] S_denoise_out_meta;', decl_start))
        declarations = top[decl_start:decl_stop]
        assert re.search(r'\.I_sel\s*\(\s*3\x27d3\s*\)', tone)
        assert '.I_stage_result  ( S_region_data' in mixer
        assert '.DENOISE_DEBUG_EN ( 1 )' in osd
        assert '.I_meta(S_denoise_meta_3d)' in denoise

        # Current OSD art used on both sides, so the changed candidate label
        # does not mask pixel/coordinate errors. Glyph content is checked below
        # against independent 5x7 bitmaps.
        reference_osd = osd.replace('u_osd_overlay(', 'reference_osd(')
        replacements = {
            'S_hdmi_out_de': 'S_hdmi_de', 'S_hdmi_out_vsync': 'S_hdmi_vsync',
            'S_denoise_out_meta[19:17]': 'S_img_mode',
            'S_denoise_out_meta[1]': 'S_img_src_raw',
            'S_denoise_out_meta[9:2]': 'S_img_threshold',
            'S_denoise_out_meta[0]': 'S_img_th_locked',
            'S_denoise_out_meta[11:10]': 'S_k_sel',
            'S_denoise_out_meta[16:15]': 'S_exp_sel',
            'S_denoise_out_meta[14:12]': 'S_region_sel_active',
            'S_denoise_clean_data': 'reference_tone',
            'S_hdmi_out_data': 'reference_osd_data',
        }
        for old, new in replacements.items():
            reference_osd = reference_osd.replace(old, new)

        harness = r'''
`timescale 1ns/1ps
module tb_chroma_pipeline;
localparam integer IMG_MODE=0;
reg S_hdmi_pixel_clk=0;
always #5 S_hdmi_pixel_clk=~S_hdmi_pixel_clk;
reg S_hdmi_rst_n=1;
reg S_hdmi_vsync=0,S_hdmi_hsync=0,S_hdmi_de=0,S_hdmi_user=0,S_hdmi_last=0;
reg [23:0] S_imgp_data=0;
reg [3:0] I_key=4'b1111;
wire [2:0] S_img_mode,S_region_sel_req,S_region_sel_active;
reg [2:0] S_region_sel;
wire [1:0] S_exp_sel;
wire S_img_th_lock_req,S_img_k_step;
reg [1:0] S_k_sel=2;
reg [7:0] S_img_threshold=48;
reg S_img_src_raw=0,S_img_th_locked=0;
wire [3:0] S_hdmi_debug_status=0;
wire S_hdmi_window_rd_en,S_hdmi_out_vsync,S_hdmi_out_hsync,S_hdmi_out_de;
wire [23:0] S_region_data,S_hdmi_out_data;
wire [23:0] reference_tone,reference_osd_data,reference_data,reference_clean;
wire reference_vs,reference_hs,reference_de,reference_read;
reg [19:0] rm1,rm2,rm3;
reg [2:0] rp,ro,rl;
wire ref_protect=(S_img_mode!=0)||(S_imgp_data[23:16]>=208)||
                 (S_imgp_data[15:8]>=208)||(S_imgp_data[7:0]>=208);
wire ref_overlay=(reference_osd_data!=reference_tone);
wire ref_logo=reference_osd.S_logo_opaque;
integer tick=0,wr=0,latency=-1,first_ref=-1;
integer rdi=0,checks=0,video=0,noop=0,protected_count=0,overlay=0,logo=0,changed=0;
integer d_checks[0:3];
reg [19:0] queue_meta[0:1799];
reg [23:0] queue_data[0:1799],queue_clean[0:1799];
reg [2:0] queue_sync[0:1799];
reg queue_protect[0:1799],queue_overlay[0:1799],queue_logo[0:1799];
integer q,mode_d,d_d;
reg [19:0] want_meta;
reg [23:0] want_clean,want_data;
integer old_reads,f,x,y,n,rows,total_rows,p1,p2,p3;
reg [31:0] noise=32'h3f20ab57;
function integer y8;
 input [23:0] rgb;
 begin y8=(77*rgb[23:16]+150*rgb[15:8]+29*rgb[7:0]+128)>>8;end
endfunction
always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)begin
 if(!S_hdmi_rst_n)begin rm1<=0;rm2<=0;rm3<=0;rp<=7;ro<=0;rl<=0;end
 else begin
  rm1<={S_img_mode,S_exp_sel,S_region_sel_active,S_k_sel,S_img_threshold,S_img_src_raw,S_img_th_locked};
  rm2<=rm1;rm3<=rm2;rp<={rp[1:0],ref_protect};ro<={ro[1:0],ref_overlay};rl<={rl[1:0],ref_logo};
 end
end
always @(posedge S_hdmi_pixel_clk)begin
 if(S_hdmi_rst_n)begin
  if(S_hdmi_window_rd_en!==reference_read)$fatal(1,"DDR request changed at%0d",tick);
  if(reference_read)rdi=rdi+1;
 end
 #1;
 if(!S_hdmi_rst_n)begin tick=0;wr=0;latency=-1;first_ref=-1;end
 else begin
  if(reference_vs && first_ref<0)first_ref=tick;
  if(S_hdmi_out_vsync && latency<0 && first_ref>=0)begin
   latency=tick-first_ref;
   if(latency<1650 || latency>1680)$fatal(1,"Unexpected denoiser raster latency%0d",latency);
   $display("PASS measured fixed raster delay: %0d cycles after original mixer",latency);
  end
  if(latency>=0 && tick>first_ref+latency+2)begin
   q=(wr-latency+1800)%1800;
   if({S_hdmi_out_hsync,S_hdmi_out_vsync,S_hdmi_out_de}!==queue_sync[q])
    $fatal(1,"HS/VS/DE mismatch tick%0d",tick);
   want_meta=queue_meta[q];want_clean=queue_clean[q];want_data=queue_data[q];
   if(S_denoise_out_meta!==want_meta)
    $fatal(1,"Metadata misalignment tick%0d got%05x expected%05x",tick,S_denoise_out_meta,want_meta);
   if(S_hdmi_out_de)begin
    video=video+1;mode_d=want_meta[19:17];d_d=want_meta[14:12];
    d_checks[d_d]=d_checks[d_d]+1;
    if(y8(S_denoise_clean_data)!=y8(want_clean))
     $fatal(1,"Brightness changed after top integration tick%0d got%06x want%06x",tick,S_denoise_clean_data,want_clean);
    if(d_d==0 || mode_d!=0)begin
     noop=noop+1;
     if(S_denoise_clean_data!==want_clean || S_hdmi_out_data!==want_data)
      $fatal(1,"D0/noncolor image or OSD mismatch tick%0d mode%0d D%0d clean%06x/%06x OSD%06x/%06x",tick,mode_d,d_d,S_denoise_clean_data,want_clean,S_hdmi_out_data,want_data);
    end
    if(queue_protect[q])begin
     protected_count=protected_count+1;
     if(S_denoise_clean_data!==want_clean)$fatal(1,"Pre-tone protected pixel changed");
    end
    if(queue_overlay[q])begin
     overlay=overlay+1;
     if(S_hdmi_out_data!==want_data)$fatal(1,"OSD content/position changed tick%0d got%06x want%06x",tick,S_hdmi_out_data,want_data);
    end
    if(queue_logo[q])begin
     logo=logo+1;
     if(S_hdmi_out_data!==want_data)$fatal(1,"Logo content/position changed tick%0d",tick);
    end
    if(S_denoise_clean_data!==want_clean)changed=changed+1;
   end
   checks=checks+1;
  end
  queue_sync[wr]={reference_hs,reference_vs,reference_de};
  queue_data[wr]=reference_data;queue_clean[wr]=reference_clean;
  queue_meta[wr]=rm3;queue_protect[wr]=rp[2];queue_overlay[wr]=ro[2];queue_logo[wr]=rl[2];
  wr=(wr+1)%1800;tick=tick+1;
 end
end
highlight_tone reference_processor(
 .I_de(S_hdmi_de),.I_enable(S_img_mode==0),.I_sel(3'd3),
 .I_data(S_imgp_data),.O_mask(),.O_data(reference_tone));
hdmi_mixer #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.DEBUG_MODE(0)) reference_mixer(
 .I_clk(S_hdmi_pixel_clk),.I_rst_n(S_hdmi_rst_n),.I_video_vsync(S_hdmi_vsync),
 .I_video_hsync(S_hdmi_hsync),.I_video_de(S_hdmi_de),.I_video_user(S_hdmi_user),
 .I_video_last(S_hdmi_last),.I_debug_status(4'd0),.O_video_rd_en(reference_read),
 .I_video_rd_data(reference_osd_data),.O_hdmi_vsync(reference_vs),
 .O_hdmi_hsync(reference_hs),.O_hdmi_de(reference_de),.O_hdmi_data(reference_data));
hdmi_mixer #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.DEBUG_MODE(0)) reference_clean_mixer(
 .I_clk(S_hdmi_pixel_clk),.I_rst_n(S_hdmi_rst_n),.I_video_vsync(S_hdmi_vsync),
 .I_video_hsync(S_hdmi_hsync),.I_video_de(S_hdmi_de),.I_video_user(S_hdmi_user),
 .I_video_last(S_hdmi_last),.I_debug_status(4'd0),.O_video_rd_en(),
 .I_video_rd_data(reference_tone),.O_hdmi_vsync(),.O_hdmi_hsync(),
 .O_hdmi_de(),.O_hdmi_data(reference_clean));
'''
        harness += declarations+'\n'+ui+'\n'+commit+'\n'+metadata+'\n'+tone+'\n'+mixer+'\n'+carry+'\n'+denoise+'\n'+osd+'\n'+reference_osd
        harness += r'''
task cycles;
 input integer count;integer j;
 begin for(j=0;j<count;j=j+1)begin @(negedge S_hdmi_pixel_clk);end end
endtask
task press;
 input integer key,hold;integer j;
 begin
  I_key[key]=0;cycles(hold);I_key[key]=1;cycles(14);
 end
endtask
task check_ui;
 input integer mode,exp,request,committed;
 begin
  if({S_img_mode,S_exp_sel,S_region_sel_req,S_region_sel}!=={mode[2:0],exp[1:0],request[2:0],committed[2:0]})
   $fatal(1,"UI mode/exp/request/commit%0d/%0d/%0d/%0d wanted%0d/%0d/%0d/%0d",S_img_mode,S_exp_sel,S_region_sel_req,S_region_sel,mode,exp,request,committed);
  if(S_img_th_lock_req!==0 || S_img_k_step!==0)$fatal(1,"D key modified unrelated controls");
 end
endtask
task pulse_vs;
 begin
  S_hdmi_vsync=1;S_hdmi_user=1;cycles(8);
  S_hdmi_vsync=0;S_hdmi_user=0;cycles(8);
 end
endtask
initial begin
 for(n=0;n<4;n=n+1)d_checks[n]=0;
 #1 S_hdmi_rst_n=0;cycles(5);S_hdmi_rst_n=1;cycles(16);
 check_ui(0,3,0,0);
 repeat(3)begin I_key[3]=0;cycles(1);I_key[3]=1;cycles(1);end
 cycles(14);check_ui(0,3,0,0);
 press(3,100);check_ui(0,3,1,0); // no active-frame candidate commit
 pulse_vs;check_ui(0,3,1,1);
 press(3,14);check_ui(0,3,2,1);pulse_vs;check_ui(0,3,2,2);
 press(3,14);check_ui(0,3,3,2);pulse_vs;check_ui(0,3,3,3);
 press(3,14);check_ui(0,3,0,3);pulse_vs;check_ui(0,3,0,0);
 press(2,100);check_ui(0,0,0,0);
 press(2,14);press(2,14);press(2,14);check_ui(0,3,0,0);
 $display("PASS UI: D0/1/2/3 wrap, bounce, long hold, exposure independence, vertical-blank commit");
 for(f=0;f<7;f=f+1)begin
  if(f>0 && f<4)press(3,14);
  if(f>=4)press(1,14);
  pulse_vs;
  rows=(f==0)?720:((f<4)?100:48);
  total_rows=rows+30;
  old_reads=rdi;
  for(y=0;y<total_rows;y=y+1)begin
   for(x=0;x<1650;x=x+1)begin
    @(negedge S_hdmi_pixel_clk);
    S_hdmi_hsync=(x>=1390 && x<1430);
    S_hdmi_vsync=(y>=rows+5 && y<rows+10);
    S_hdmi_user=(x==0 && y==0);
    S_hdmi_de=(x<1280 && y<rows);
    S_hdmi_last=S_hdmi_de && x==1279;
    noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
    p1=40+((x/32+y/16)%70)+(noise[2:0])-3;
    p2=50+((x/32+y/16)%70)+(noise[5:3])-3;
    p3=60+((x/32+y/16)%70)+(noise[8:6])-3;
    if(x>=1000 && x<1100)begin p1=240;p2=210;p3=190;end
    if(S_img_mode==1)begin p1=(x+y)%256;p2=p1;p3=p1;end
    if(S_img_mode==2)begin p1=((x/23+y/17)%2)*255;p2=p1;p3=p1;end
    if(S_img_mode==3)begin p1=((x%29==0)||(y%23==0))?255:0;p2=p1;p3=p1;end
    S_imgp_data={p1[7:0],p2[7:0],p3[7:0]};
    S_img_threshold=48+f;
   end
  end
  @(negedge S_hdmi_pixel_clk);
  S_hdmi_de=0;S_hdmi_user=0;S_hdmi_last=0;S_hdmi_hsync=0;S_hdmi_vsync=0;
  cycles(1800);
  if(rdi-old_reads!=1280*rows)$fatal(1,"Frame%0d consumed%0d DDR reads expected%0d",f,rdi-old_reads,1280*rows);
  $display("PASS pipeline frame%0d mode%0d D%0d: %0d active pixels, DDR count exact",f,S_img_mode,S_region_sel,1280*rows);
 end
 cycles(2000);
 if(video!=(720+300+144)*1280)$fatal(1,"Lost/extra active pixel count%0d",video);
 if(changed<1000 || overlay<1000 || logo<1000)$fatal(1,"Insufficient denoise/OSD/Logo coverage: %0d/%0d/%0d",changed,overlay,logo);
 if(d_checks[0]<921600 || d_checks[1]<120000 || d_checks[2]<120000 || d_checks[3]<120000)
  $fatal(1,"Candidate coverage failed %0d/%0d/%0d/%0d",d_checks[0],d_checks[1],d_checks[2],d_checks[3]);
 $display("PASS chroma_pipeline: cycles=%0d pixels=%0d noop=%0d protected=%0d overlay=%0d logo=%0d changed=%0d delay=%0d reads=%0d",checks,video,noop,protected_count,overlay,logo,changed,latency,rdi);
 $finish;
end
initial begin #100000000;$fatal(1,"pipeline watchdog");end
endmodule
'''
        # Independent tiny test checks new text, including D rather than H/M.
        glyphs = {
            'C': [14,17,16,16,16,17,14], '=': [0,31,0,31,0,0,0],
            '3': [30,1,1,14,1,1,30], ' ': [0]*7,
            'D': [30,17,17,17,17,17,30],
            '0': [14,17,19,21,25,17,14], '1': [4,12,4,4,4,4,14],
            '2': [14,17,1,2,4,8,31],
        }
        expected = []
        for sel in range(4):
            text = 'C=3 D='+str(sel)
            for yy in range(14):
                for xx in range(84):
                    cell, col = divmod(xx, 12)
                    expected.append(int(col//2 < 5 and bool(glyphs[text[cell]][yy//2] & (1 << (4-col//2)))))
        (output/'glyph_expected.hex').write_text('\n'.join(map(str, expected))+'\n', encoding='ascii')
        glyph_file = (output/'glyph_expected.hex').as_posix()
        glyph_tb = r'''
`timescale 1ns/1ps
module tb_denoise_label;
reg [10:0] x=0;reg [9:0] y=0;reg enable=1;reg [2:0] sel=0;
wire box,white;
reg expected[0:4703];
integer s,ix,iy,index=0;
osd_region_line #(.DENOISE_MODE(1)) dut(.I_x(x),.I_y(y),.I_enable(enable),.I_sel(sel),.O_box(box),.O_white(white));
initial begin
 $readmemh("GLYPH_PATH",expected);
 for(s=0;s<4;s=s+1)begin
  sel=s;
  for(iy=0;iy<14;iy=iy+1)for(ix=0;ix<84;ix=ix+1)begin
   x=24+ix;y=56+iy;#1;
   if(box!==1 || white!==expected[index])$fatal(1,"Wrong C=3 D=%0d glyph x/y%0d/%0d",s,ix,iy);
   index=index+1;
  end
 end
 enable=0;#1;if(box!==0 || white!==0)$fatal(1,"Disabled label visible");
 $display("PASS denoise_label: 4704 independent 5x7 glyph pixels; C=3 D=0/1/2/3");$finish;
end
endmodule
'''.replace('GLYPH_PATH', glyph_file)
        (output/'tb_chroma_pipeline.v').write_text(harness, encoding='utf-8')
        (output/'tb_denoise_label.v').write_text(glyph_tb, encoding='utf-8')
        sources = [hdl/name for name in ['hdmi_mixer.v', 'highlight_tone.v', 'highlight_region.v',
                   'chroma_denoise_stream.v', 'osd_overlay.v', 'osd_font_rom.v', 'osd_logo_rom.v', 'img_mode_sel.v']]
        sources += [root/'tools/tests/chroma_eram_model.v']
        for bench in ('denoise_label','chroma_pipeline'):
            command = [str(args.iverilog_bin/'iverilog.exe'), '-g2012', '-Wall', '-I', str(hdl),
                       '-s', 'tb_'+bench, '-o', str(output/(bench+'.vvp')), str(output/('tb_'+bench+'.v'))]
            command += [str(p) for p in sources]
            build = subprocess.run(command, cwd=root, capture_output=True, text=True, errors='replace', timeout=60)
            (output/(bench+'_compile.log')).write_text(build.stdout+build.stderr, encoding='utf-8')
            assert build.returncode==0, build.stdout+build.stderr
            run = subprocess.run([str(args.iverilog_bin/'vvp.exe'),str(output/(bench+'.vvp'))], cwd=root,
                                 capture_output=True, text=True, errors='replace', timeout=900)
            (output/(bench+'_simulation.log')).write_text(run.stdout+run.stderr, encoding='utf-8')
            print(run.stdout,end='')
            assert run.returncode==0, run.stdout+run.stderr
            assert 'PASS '+bench+':' in run.stdout
        match=re.search(r'PASS chroma_pipeline: cycles=(\d+) pixels=(\d+) noop=(\d+) protected=(\d+) overlay=(\d+) logo=(\d+) changed=(\d+) delay=(\d+) reads=(\d+)',run.stdout)
        assert match
        summary.update(dict(zip(['cycles','active_pixels','noop_pixels','protected_pixels','overlay_pixels','logo_pixels','modified_pixels','fixed_delay_cycles','identical_ddr_reads'],map(int,match.groups()))))
        summary.update(pass_=True,full_720p_D0_frames=1,extra_color_candidate_rows=300,noncolor_rows=144,
                       glyph_pixels_checked=4704,production_instances_extracted=True,
                       debounce_time_only_shortened=True,top_VS_commit_extracted=True,
                       reference='Previous C3 -> OSD -> mixer topology, current OSD assets and new candidate text',
                       board_validation='not_run')
        summary['source_sha256'] = {p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                                    for p in [top_path,root/'tools/test_chroma_denoise_pipeline.py']+sources}
    except (OSError,AssertionError,ValueError,subprocess.SubprocessError) as err:
        summary['error']=str(err)
        print('FAIL chroma_pipeline:',err)
    summary['pass']=summary.pop('pass_')
    (output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n', encoding='utf-8')
    return 0 if summary['pass'] else 1


if __name__=='__main__':
    raise SystemExit(main())
