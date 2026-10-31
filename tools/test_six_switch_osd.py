"""Raster-check the five-switch / six-stage applied-state OSD.

The actual production RTL is clocked through four complete 1280x720 frames.
Pixels outside the new panel are compared with the accepted f86bc17 OSD;
STATUS_EN=0 must reproduce that OSD everywhere, and OSD_EN=0 must stay a
combinational pass-through.  Panel images are decoded independently in Python
to check the visible labels, bit-to-item mapping, ON/OFF/WAIT and colours.
No FPGA, serial port or capture device is accessed.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

from PIL import Image


# Small conventional 5x7 letter templates, checked against pixels emitted by
# RTL rather than its internal item/character signals.
FONT = {
    'A': ['01110','10001','10001','11111','10001','10001','10001'],
    'B': ['11110','10001','10001','11110','10001','10001','11110'],
    'C': ['01111','10000','10000','10000','10000','10000','01111'],
    'D': ['11110','10001','10001','10001','10001','10001','11110'],
    'E': ['11111','10000','10000','11110','10000','10000','11111'],
    'F': ['11111','10000','10000','11110','10000','10000','10000'],
    'G': ['01111','10000','10000','10111','10001','10001','01111'],
    'I': ['11111','00100','00100','00100','00100','00100','11111'],
    'M': ['10001','11011','10101','10101','10001','10001','10001'],
    'N': ['10001','11001','10101','10011','10001','10001','10001'],
    'O': ['01110','10001','10001','10001','10001','10001','01110'],
    'P': ['11110','10001','10001','11110','10000','10000','10000'],
    'S': ['01111','10000','10000','01110','00001','00001','11110'],
    'T': ['11111','00100','00100','00100','00100','00100','00100'],
    'W': ['10001','10001','10001','10101','10101','11011','10001'],
    'X': ['10001','10001','01010','00100','01010','10001','10001'],
    '1': ['00100','01100','00100','00100','00100','00100','01110'],
    '2': ['01110','10001','00001','00010','00100','01000','11111'],
    '3': ['11110','00001','00001','01110','00001','00001','11110'],
    '4': ['00010','00110','01010','10010','11111','00010','00010'],
    '5': ['11111','10000','10000','11110','00001','00001','11110'],
    ' ': ['00000'] * 7,
}

BENCH = r'''
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rstn=0,de=0,vs=0;reg[2:0] mode=0;
reg[5:0] enabled=0,pending=0;reg[23:0] pixel=24'h304050;
wire[23:0] actual,reference,no_status,bypass;
osd_overlay dut(.I_clk(clk),.I_rst_n(rstn),.I_de(de),.I_vs(vs),
 .I_mode(mode),.I_alg_state(enabled),.I_alg_pending(pending),
 .I_data(pixel),.O_data(actual));
osd_overlay #(.STATUS_EN(0)) disabled_panel(.I_clk(clk),.I_rst_n(rstn),
 .I_de(de),.I_vs(vs),.I_mode(mode),.I_alg_state(enabled),
 .I_alg_pending(pending),.I_data(pixel),.O_data(no_status));
osd_overlay #(.OSD_EN(0)) disabled_osd(.I_clk(clk),.I_rst_n(rstn),
 .I_de(de),.I_vs(vs),.I_mode(mode),.I_alg_state(enabled),
 .I_alg_pending(pending),.I_data(pixel),.O_data(bypass));
osd_overlay_reference old(.I_clk(clk),.I_rst_n(rstn),.I_de(de),.I_vs(vs),
 .I_mode(mode),.I_data(pixel),.O_data(reference));
integer x,y,frame,outfile,noutside=0,ninside=0;
reg[1023:0] filename;
initial begin
 #1;rstn=1;#1;rstn=0;repeat(3)@(negedge clk);rstn=1;
 for(frame=0;frame<4;frame=frame+1)begin
  mode=frame;
  case(frame)
   0:begin enabled=6'h3f;pending=0;end
   1:begin enabled=0;pending=0;end
   2:begin enabled=6'h3f;pending=6'h3f;end
   3:begin enabled=6'b101010;pending=6'b001001;end
  endcase
  @(negedge clk);de=0;vs=1;
  repeat(3)@(negedge clk);vs=0;
  $sformat(filename,"__OUT__/panel_%0d.ppm",frame);
  outfile=$fopen(filename,"wb");
  if(!outfile)$fatal(1,"cannot open panel output");
  $fwrite(outfile,"P6\n592 64\n255\n");
  for(y=0;y<720;y=y+1)begin
   for(x=0;x<1280;x=x+1)begin
    @(negedge clk);de=1;pixel=24'h304050;
    #1;
    if(dut.S_x!==x||dut.S_y!==y)$fatal(1,"raster coordinates x=%0d y=%0d got=%0d,%0d",x,y,dut.S_x,dut.S_y);
    if(no_status!==reference)$fatal(1,"STATUS_EN=0 changed original OSD x=%0d y=%0d mode=%0d",x,y,mode);
    if(bypass!==pixel)$fatal(1,"OSD_EN=0 not pass-through");
    if(x>=16&&x<608&&y>=648&&y<712)begin
     ninside=ninside+1;
     $fwrite(outfile,"%c%c%c",actual[23:16],actual[15:8],actual[7:0]);
    end else begin
     noutside=noutside+1;
     if(actual!==reference)$fatal(1,"outside-panel pixel changed x=%0d y=%0d mode=%0d",x,y,mode);
    end
    if(x==800&&y==400)begin
     pixel=24'hb02080;#1;
     if(actual!==pixel||no_status!==pixel||bypass!==pixel)$fatal(1,"added pixel latency");
     pixel=24'h304050;#1;
    end
   end
   @(negedge clk);de=0;
   @(negedge clk);
  end
  $fclose(outfile);
 end
 $display("PASS raster outside=%0d panel=%0d modes=4 zero-latency=1",noutside,ninside);
 $finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    hdl = root / 'user_source/hdl_source'
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    iv = Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin/iverilog.exe')
    files = [hdl / f for f in ('osd_overlay.v','osd_font_rom.v','osd_logo_rom.v')]
    result = {'pass': False, 'reference': 'f86bc17',
              'source_sha256': {p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
    try:
        original = subprocess.check_output(['git','show','f86bc17:user_source/hdl_source/osd_overlay.v'],cwd=root)
        ref = out / 'osd_overlay_reference.v'
        ref.write_bytes(original.replace(b'module osd_overlay #(',b'module osd_overlay_reference #(',1))
        tb = out / 'tb.v'
        tb.write_text(BENCH.replace('__OUT__',out.as_posix()),encoding='utf-8',newline='\n')
        vvp = out / 'osd_raster.vvp'
        run = subprocess.run([str(iv),'-g2012','-s','tb','-o',str(vvp),str(tb),str(ref)]+list(map(str,files)),
                             capture_output=True,text=True,errors='replace',timeout=60)
        (out/'compile.log').write_text(run.stdout+run.stderr,encoding='utf-8')
        assert run.returncode == 0,run.stdout+run.stderr
        run = subprocess.run([str(iv.with_name('vvp.exe')),str(vvp)],capture_output=True,text=True,errors='replace',timeout=180)
        (out/'raster.log').write_text(run.stdout+run.stderr,encoding='utf-8')
        assert run.returncode == 0 and 'PASS raster' in run.stdout,run.stdout+run.stderr
        print(run.stdout.strip(),flush=True)
        result['raster'] = {'pass':True,'complete_720p_frames':4,'modes':[0,1,2,3],
                            'panel_disabled_original_equivalence':True,'outside_panel_original_equivalence':True,
                            'combinational_passthrough':True}
        labels=['S1 AWB ','S2 GAM ','S3 CSC ','S2 N1  ','S5 EXP ','S4 DEM ']
        cases=[(63,0),(0,0),(63,63),(0b101010,0b001001)]
        colors={'ON':(80,255,128),'OFF':(160,160,160),'WAIT':(255,208,64)}
        previews=[]
        result['panels']=[]
        for frame,(states,pending) in enumerate(cases):
            panel=Image.open(out/f'panel_{frame}.ppm').convert('RGB')
            assert panel.size==(592,64)
            expected=Image.new('RGB',panel.size,(0,0,0))
            strings=[]
            for i,label in enumerate(labels):
                state='WAIT' if (pending>>i)&1 else ('ON' if (states>>i)&1 else 'OFF')
                text=(label+state).ljust(11)
                strings.append(text.rstrip())
                color=colors[state]
                x0=8+(i%3)*192
                y0=8+(i//3)*32
                for k,c in enumerate(text):
                    for y,row in enumerate(FONT[c]):
                        for x,bit in enumerate(row):
                            if bit=='1':
                                for dy in (0,1):
                                    for dx in (0,1):
                                        expected.putpixel((x0+16*k+2*x+dx,y0+2*y+dy),color)
            assert panel.tobytes()==expected.tobytes(),f'visible labels/colour/spacing wrong in frame {frame}'
            panel.save(out/f'panel_{frame}.png')
            previews.append(panel)
            result['panels'].append({'frame':frame,'pass':True,'labels':strings})
        combined=Image.new('RGB',(592,64*4+8*3),(24,24,24))
        for i,p in enumerate(previews):combined.paste(p,(0,i*72))
        combined.resize((1184,560),Image.Resampling.NEAREST).save(out/'panel_comparison.png')
        result['pass']=True
        print('PASS visible labels, SW2 shared mapping, six states and ON/OFF/WAIT colours',flush=True)
    finally:
        (out/'summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    main()
