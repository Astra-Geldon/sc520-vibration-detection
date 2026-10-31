"""Verify actual natural/reference labels, legacy pixels and Logo composition.

The expected text comes from independent small glyph bitmaps.  The default-off
parameter is also compared against the original committed OSD implementation.
Generated vectors, HDL and simulator logs are written only under _build.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess


FONT = {
    '0': '01110 10001 10011 10101 11001 10001 01110',
    '1': '00100 01100 00100 00100 00100 00100 01110',
    '2': '01110 10001 00001 00010 00100 01000 11111',
    '3': '11110 00001 00001 01110 00001 00001 11110',
    '4': '00010 00110 01010 10010 11111 00010 00010',
    '6': '01110 10000 10000 11110 10001 10001 01110',
    '8': '01110 10001 10001 01110 10001 10001 01110',
    '9': '01110 10001 10001 01111 00001 00001 01110',
    'E': '11111 10000 10000 11110 10000 10000 11111',
    'G': '01110 10001 10000 10111 10001 10001 01110',
    'V': '10001 10001 10001 10001 10001 01010 00100',
    'L': '10000 10000 10000 10000 10000 10000 11111',
    'N': '10001 11001 11001 10101 10011 10011 10001',
    '=': '00000 11111 00000 11111 00000 00000 00000',
    ' ': '00000 00000 00000 00000 00000 00000 00000',
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = args.output
    output.mkdir(parents=True, exist_ok=True)
    font = {key: value.split() for key, value in FONT.items()}
    vector_file = output / 'vectors.hex'
    count = 0
    with vector_file.open('w', encoding='ascii') as handle:
        for natural in range(2):
            for gain12 in range(2):
                for enabled in range(2):
                    for gain_sel, gain in enumerate([24, 12 if gain12 else 16, 8, 4]):
                        for verified in range(2):
                            for lift in range(4):
                                suffix = f'N={lift-1}' if natural and lift >= 2 else f'L={lift}'
                                text = f'E=900 G={gain:2d} V={verified} {suffix}'
                                assert len(text) == 18
                                for y in range(49, 77):
                                    for x in range(17, 248):
                                        box = int(enabled and 20 <= x < 244 and 52 <= y < 74)
                                        white = 0
                                        if enabled and 24 <= x < 240 and 56 <= y < 70:
                                            cell, col = divmod(x - 24, 12)
                                            if col < 10:
                                                white = int(font[text[cell]][(y - 56) // 2][col // 2] == '1')
                                        word = natural
                                        for width, value in [(1, gain12), (1, enabled), (2, gain_sel),
                                                             (1, verified), (2, lift), (11, x),
                                                             (10, y), (1, box), (1, white)]:
                                            word = (word << width) | value
                                        handle.write(f'{word:08x}\n')
                                        count += 1

    baseline = subprocess.check_output(
        ['git', 'show', '6882d41:user_source/hdl_source/osd_overlay.v'], cwd=root).decode('utf-8')
    for name in ['osd_overlay', 'osd_gain_line', 'osd_region_line', 'osd_threshold_line']:
        baseline = re.sub(r'\b' + name + r'\b', name + '_legacy', baseline)
    legacy_file = output / 'osd_overlay_legacy.v'
    legacy_file.write_text(baseline, encoding='utf-8')
    bench = r'''`timescale 1ns/1ps
module tb;
reg natural=0,gain12=0,en=0,verified=0;
reg [1:0] sel=0,lift=0;reg [10:0] x=0;reg [9:0] y=0;
reg eb=0,ew=0;reg [30:0] vectors[0:COUNT-1];
wire [3:0] box,white;wire [23:0] result[0:3];wire [23:0] legacy[0:1];
integer n,gx,gy,which,c,colours=0;
genvar idx;
generate for(idx=0;idx<4;idx=idx+1)begin:g_current
 localparam integer NAT=idx/2, G12=idx%2;
 osd_gain_line #(.LIFT_DEBUG_EN(1),.GAIN12_EN(G12),.NATURAL_LIFT_EN(NAT)) line(
  .I_x(x),.I_y(y),.I_enable(en),.I_sel(sel),.I_verified(verified),.I_lift_sel(lift),
  .O_box(box[idx]),.O_white(white[idx]));
 osd_overlay #(.GAIN_DEBUG_EN(1),.LIFT_DEBUG_EN(1),.GAIN12_EN(G12),.NATURAL_LIFT_EN(NAT),.LOGO_EN(1)) overlay(
  .I_clk(1'b0),.I_rst_n(1'b0),.I_de(en),.I_vs(1'b0),.I_mode(3'd0),.I_src_raw(1'b0),
  .I_k_sel(2'd2),.I_exp_sel(2'd3),.I_gain_sel(sel),.I_gain_verified(verified),.I_lift_sel(lift),
  .I_region_sel(4'd0),.I_threshold(8'd128),.I_th_locked(1'b0),.I_data(24'had7329),.O_data(result[idx]));
 initial begin force overlay.S_x=x;force overlay.S_y=y;end
end
for(idx=0;idx<2;idx=idx+1)begin:g_legacy
 osd_overlay_legacy #(.GAIN_DEBUG_EN(1),.LIFT_DEBUG_EN(1),.GAIN12_EN(idx),.LOGO_EN(1)) overlay(
  .I_clk(1'b0),.I_rst_n(1'b0),.I_de(en),.I_vs(1'b0),.I_mode(3'd0),.I_src_raw(1'b0),
  .I_k_sel(2'd2),.I_exp_sel(2'd3),.I_gain_sel(sel),.I_gain_verified(verified),.I_lift_sel(lift),
  .I_region_sel(4'd0),.I_threshold(8'd128),.I_th_locked(1'b0),.I_data(24'had7329),.O_data(legacy[idx]));
 initial begin force overlay.S_x=x;force overlay.S_y=y;end
end endgenerate
initial begin
 $readmemh("VECTORS",vectors);
 for(n=0;n<COUNT;n=n+1)begin
  {natural,gain12,en,sel,verified,lift,x,y,eb,ew}=vectors[n];#1;
  which=natural*2+gain12;
  if({box[which],white[which]}!=={eb,ew})
   $fatal(1,"label glyph natural%0d gain12%0d x%0d y%0d L%0d",natural,gain12,x,y,lift);
  if(result[which]!==(eb?(ew?24'hffffff:24'h000000):24'had7329))
   $fatal(1,"OSD composition natural%0d x%0d y%0d L%0d",natural,x,y,lift);
  if(result[0]!==legacy[0]||result[1]!==legacy[1])
   $fatal(1,"default-off pixels changed x%0d y%0d",x,y);
 end
 en=1;
 for(gy=12;gy<100;gy=gy+1)for(gx=1132;gx<1268;gx=gx+1)begin
  x=gx;y=gy;#1;
  for(c=0;c<4;c=c+1)if(result[c]!==legacy[c%2])$fatal(1,"Logo changed variant%0d",c);
  if(result[3]==24'h1b3a66||result[3]==24'he8382f)colours=colours+1;
 end
 if(colours!=4198)$fatal(1,"Logo coloured pixel count%0d",colours);
 $display("PASS natural OSD: COUNT label/composition vectors, all gain/V/lift/enable states; exact default-off pixels; %0d Logo coloured pixels",colours);
 $finish;
end
endmodule
'''.replace('COUNT', str(count)).replace('VECTORS', vector_file.as_posix())
    tb = output / 'tb.v'
    tb.write_text(bench, encoding='utf-8')
    iv = Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin/iverilog.exe')
    files = [root / 'user_source/hdl_source' / name for name in
             ['osd_overlay.v', 'osd_font_rom.v', 'osd_logo_rom.v']]
    run = subprocess.run([str(iv), '-g2012', '-s', 'tb', '-o', str(output / 'test.vvp'),
                          str(tb), str(legacy_file)] + [str(p) for p in files],
                         capture_output=True, text=True, errors='replace')
    (output / 'compile.log').write_text(run.stdout + run.stderr, encoding='utf-8')
    assert run.returncode == 0, run.stdout + run.stderr
    run = subprocess.run([str(iv.with_name('vvp.exe')), str(output / 'test.vvp')],
                         capture_output=True, text=True, errors='replace', timeout=180)
    (output / 'simulation.log').write_text(run.stdout + run.stderr, encoding='utf-8')
    assert run.returncode == 0 and 'PASS natural OSD' in run.stdout, run.stdout + run.stderr
    summary = {
        'pass': True,
        'scope': 'Actual E/G/V/L or N glyphs/composition; natural on/off, gain12 on/off, all gains,V,lift,enable; exact default-off baseline pixels and Logo',
        'reference_commit': '6882d41',
        'pixel_vectors': count,
        'logo_coloured_pixels': 4198,
        'natural_labels': ['L=0', 'L=1', 'N=1', 'N=2'],
        'source_sha256': {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in files},
        'test_script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    }
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(run.stdout, flush=True)


if __name__ == '__main__':
    main()
