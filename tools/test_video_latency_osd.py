"""Raster-check compact LAT and status text against an independent 5x7 reference.

No TD tools or hardware are used.  All generated simulation files stay under
validation/compact_osd_20261101/sim_osd.
"""
from pathlib import Path
import hashlib
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
VALIDATION = ROOT / "validation/latency_osd_20261101"
BASELINE = VALIDATION / "before/osd_overlay.v"
SIM = ROOT / "validation/compact_osd_20261101/sim_osd"
SIM.mkdir(parents=True, exist_ok=True)

expected_hash = (VALIDATION / "before/osd_overlay.sha256").read_text().strip().lower()
assert hashlib.sha256(BASELINE.read_bytes()).hexdigest() == expected_hash, "Baseline changed"
old_source = BASELINE.read_text(encoding="utf-8")
assert "module osd_overlay #(" in old_source
(SIM / "osd_overlay_baseline.v").write_text(
    old_source.replace("module osd_overlay #(", "module osd_overlay_baseline #(", 1),
    encoding="utf-8",
)

TB = r'''
`timescale 1ns/1ps
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n=0, de=0, vs=0;
    reg [2:0] mode=7;
    reg [5:0] states=6'b101001, pending=6'b010100;
    reg valid=0;
    reg [15:0] bcd=0;
    reg [23:0] data=0;
    wire [23:0] output_new, output_old, output_disabled, output_bypass, output_no_status, output_plain;
    osd_overlay dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_de(de), .I_vs(vs), .I_mode(mode),
        .I_alg_state(states), .I_alg_pending(pending),
        .I_latency_valid(valid), .I_latency_bcd(bcd),
        .I_data(data), .O_data(output_new)
    );
    osd_overlay #(.LATENCY_EN(0)) disabled (
        .I_clk(clk), .I_rst_n(rst_n), .I_de(de), .I_vs(vs), .I_mode(mode),
        .I_alg_state(states), .I_alg_pending(pending),
        .I_latency_valid(valid), .I_latency_bcd(bcd),
        .I_data(data), .O_data(output_disabled)
    );
    osd_overlay #(.OSD_EN(0)) bypass (
        .I_clk(clk), .I_rst_n(rst_n), .I_de(de), .I_vs(vs), .I_mode(mode),
        .I_alg_state(states), .I_alg_pending(pending),
        .I_latency_valid(valid), .I_latency_bcd(bcd),
        .I_data(data), .O_data(output_bypass)
    );
    osd_overlay #(.STATUS_EN(0)) no_status (
        .I_clk(clk), .I_rst_n(rst_n), .I_de(de), .I_vs(vs), .I_mode(mode),
        .I_alg_state(states), .I_alg_pending(pending),
        .I_latency_valid(valid), .I_latency_bcd(bcd),
        .I_data(data), .O_data(output_no_status)
    );
    osd_overlay #(.STATUS_EN(0), .LATENCY_EN(0)) plain (
        .I_clk(clk), .I_rst_n(rst_n), .I_de(de), .I_vs(vs), .I_mode(mode),
        .I_alg_state(states), .I_alg_pending(pending),
        .I_latency_valid(valid), .I_latency_bcd(bcd),
        .I_data(data), .O_data(output_plain)
    );
    osd_overlay_baseline #(.STATUS_EN(0)) old (
        .I_clk(clk), .I_rst_n(rst_n), .I_de(de), .I_vs(vs), .I_mode(mode),
        .I_alg_state(states), .I_alg_pending(pending),
        .I_data(data), .O_data(output_old)
    );

    // Independent 5x7 reference for both compact panels. The original mode
    // label, logo and all remaining video pixels use the production baseline.
    function [34:0] glyph;
        input [7:0] ascii;
        begin
            case (ascii)
                "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
                "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
                "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
                "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
                "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
                "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
                "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
                "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
                "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
                "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
                "5":glyph=35'b11111_10000_10000_11110_00001_00001_11110;
                "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
                "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
                "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
                "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
                ".":glyph=35'b00000_00000_00000_00000_00000_00110_00110;
                "-":glyph=35'b00000_00000_00000_11111_00000_00000_00000;
                "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
                "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
                "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
                "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
                "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
                "G":glyph=35'b01111_10000_10000_10111_10001_10001_01111;
                "I":glyph=35'b11111_00100_00100_00100_00100_00100_11111;
                "N":glyph=35'b10001_11001_10101_10011_10001_10001_10001;
                "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
                "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
                "W":glyph=35'b10001_10001_10001_10101_10101_11011_10001;
                "X":glyph=35'b10001_10001_01010_00100_01010_10001_10001;
                default:glyph=0;
            endcase
        end
    endfunction

    // Physical switch labels, intentionally independent of the DUT decoder.
    function [7:0] label_char;
        input integer item, index;
        reg [87:0] label;
        begin
            case(item)
                0:label="S1 AWB "; 1:label="S2 GAM "; 2:label="S3 CSC ";
                3:label="S2 N1  "; 4:label="S5 EXP "; 5:label="S4 DEM ";
            endcase
            // Strings above are seven characters, right aligned in 88 bits.
            label_char=(label >> (8*(6-index))) & 8'hff;
        end
    endfunction

    reg expected_valid;
    reg [15:0] expected_bcd;
    integer frame, x, y, checked=0, panel_checked=0, status_checked=0;
    integer char_index, row_index, col_index, bit_index, item;
    integer lat_file, status_file, full_file;
    reg [1023:0] filename;
    reg [7:0] ascii;
    reg [34:0] bits;
    reg [23:0] expected_pixel, expected_latency, expected_status, ink_color;
    task check_pixel;
        begin
            if (dut.S_x !== x || dut.S_y !== y)
                $fatal(1,"Raster coordinate mismatch expected=(%0d,%0d) actual=(%0d,%0d)",x,y,dut.S_x,dut.S_y);
            if (output_plain !== output_old)
                $fatal(1,"Both panels disabled changed original mode/logo/video frame=%0d x=%0d y=%0d",frame,x,y);
            if (output_bypass !== data)
                $fatal(1,"OSD_EN=0 failed direct bypass");
            expected_latency=output_old;
            expected_status=output_old;
            if (x>=92 && x<196 && y>=24 && y<40) begin
                expected_latency=24'h000000;
                if (x>=96 && x<192 && y>=28 && y<36) begin
                    char_index=(x-96)/8;
                    col_index=(x-96)%8;
                    row_index=y-28;
                    ascii=" ";
                    case(char_index)
                        0:ascii="L"; 1:ascii="A"; 2:ascii="T";
                        4:ascii=expected_valid ? (8'h30+expected_bcd[15:12]) : "-";
                        5:ascii=expected_valid ? (8'h30+expected_bcd[11:8]) : "-";
                        6:ascii=expected_valid ? (8'h30+expected_bcd[7:4]) : "-";
                        7:ascii=".";
                        8:ascii=expected_valid ? (8'h30+expected_bcd[3:0]) : "-";
                        10:ascii="M"; 11:ascii="S";
                    endcase
                    bits=glyph(ascii);
                    bit_index=34-row_index*5-col_index;
                    if (row_index<7 && col_index<5 && bits[bit_index])
                        expected_latency=24'hffffff;
                end
                panel_checked=panel_checked+1;
                $fwrite(lat_file,"%c%c%c",output_new[23:16],output_new[15:8],output_new[7:0]);
            end
            if (x>=20 && x<316 && y>=684 && y<716) begin
                expected_status=24'h000000;
                if (x>=24 && x<312 && y>=688 && y<712 && ((y-688)%16)<8) begin
                    item=((y-688)/16)*3+(x-24)/96;
                    char_index=((x-24)%96)/8;
                    col_index=(x-24)%8;
                    row_index=(y-688)%16;
                    ascii=" ";
                    if(char_index<7) ascii=label_char(item,char_index);
                    else case(char_index)
                        7:ascii=pending[item] ? "W" : "O";
                        8:ascii=pending[item] ? "A" : (states[item] ? "N" : "F");
                        9:ascii=pending[item] ? "I" : (states[item] ? " " : "F");
                        10:ascii=pending[item] ? "T" : " ";
                    endcase
                    ink_color=pending[item] ? 24'hffd040 : (states[item] ? 24'h50ff80 : 24'ha0a0a0);
                    bits=glyph(ascii);
                    bit_index=34-row_index*5-col_index;
                    if(row_index<7 && col_index<5 && bits[bit_index]) expected_status=ink_color;
                end
                status_checked=status_checked+1;
                $fwrite(status_file,"%c%c%c",output_new[23:16],output_new[15:8],output_new[7:0]);
            end
            expected_pixel=expected_latency;
            if(x>=20 && x<316 && y>=684 && y<716) expected_pixel=expected_status;
            if(output_new !== expected_pixel)
                $fatal(1,"OSD pixel mismatch frame=%0d x=%0d y=%0d expected=%h actual=%h",frame,x,y,expected_pixel,output_new);
            if(output_disabled !== expected_status)
                $fatal(1,"LATENCY_EN=0 mismatch frame=%0d x=%0d y=%0d",frame,x,y);
            if(output_no_status !== expected_latency)
                $fatal(1,"STATUS_EN=0 mismatch frame=%0d x=%0d y=%0d",frame,x,y);
            if(frame==3) $fwrite(full_file,"%c%c%c",output_new[23:16],output_new[15:8],output_new[7:0]);
            checked=checked+1;
        end
    endtask

    initial begin
        // Force a real reset edge for all asynchronous-reset registers.
        rst_n=1; #1; rst_n=0;
        repeat(3) @(negedge clk);
        rst_n=1;
        #1;
        if (dut.S_latency_valid !== 1'b0) $fatal(1,"Boot must show invalid timing");
        for(frame=0;frame<4;frame=frame+1) begin
            @(negedge clk);
            mode=frame;
            case(frame)
                0:begin states=6'h3f;pending=0;end
                1:begin states=0;pending=0;end
                2:begin states=6'h3f;pending=6'h3f;end
                3:begin states=6'b101010;pending=6'b001001;end
            endcase
            $sformat(filename,"__SIM__/lat_%0d.ppm",frame);
            lat_file=$fopen(filename,"wb");
            $fwrite(lat_file,"P6\n104 16\n255\n");
            $sformat(filename,"__SIM__/status_%0d.ppm",frame);
            status_file=$fopen(filename,"wb");
            $fwrite(status_file,"P6\n296 32\n255\n");
            if(frame==3) begin
                full_file=$fopen("__SIM__/frame.ppm","wb");
                $fwrite(full_file,"P6\n1280 720\n255\n");
            end
            if(!lat_file || !status_file || (frame==3 && !full_file)) $fatal(1,"Cannot open raster output");
            case(frame)
                0:begin expected_valid=0;expected_bcd=16'h0000;end
                1:begin expected_valid=1;expected_bcd=16'h9876;end
                2:begin expected_valid=1;expected_bcd=16'h6543;end
                3:begin expected_valid=1;expected_bcd=16'h2109;end
            endcase
            valid=expected_valid;bcd=expected_bcd;vs=1;
            repeat(2) @(negedge clk);
            // Changing the input while VS stays high must not tear the result.
            valid=~expected_valid;bcd=16'h1111;
            repeat(2) @(negedge clk);
            if (dut.S_latency_valid !== expected_valid || dut.S_latency_bcd !== expected_bcd)
                $fatal(1,"Timing snapshot must latch on the VS rising edge only");
            vs=0;
            for(y=0;y<720;y=y+1) begin
                for(x=0;x<1280;x=x+1) begin
                    @(negedge clk);
                    de=1;
                    data={x[7:0],y[7:0],(x[7:0]^y[7:0]^frame[7:0])};
                    if (x==640 && y==100) begin
                        // A mid-frame measurement update applies next frame.
                        bcd=16'h5555;valid=~expected_valid;
                    end
                    #1;
                    check_pixel;
                end
                @(negedge clk);de=0;
            end
            $fclose(lat_file);$fclose(status_file);
            if(frame==3) $fclose(full_file);
            $display("FRAME_PASS mode=%0d valid=%0d bcd=%h",mode,expected_valid,expected_bcd);
        end
        // A formerly valid result must return to dashes at a later frame edge.
        @(negedge clk);vs=1;valid=0;bcd=16'h9999;
        repeat(2) @(negedge clk);
        if (dut.S_latency_valid !== 1'b0) $fatal(1,"Invalid result did not replace valid result");
        $display("LATENCY_OSD_PASS pixels=%0d panel_pixels=%0d status_pixels=%0d",checked,panel_checked,status_checked);
        $finish;
    end
endmodule
'''
(SIM / "tb_video_latency_osd.v").write_text(TB.replace("__SIM__", SIM.as_posix()), encoding="utf-8")
iverilog = shutil.which("iverilog") or r"C:\iverilog\bin\iverilog.exe"
vvp = shutil.which("vvp") or r"C:\iverilog\bin\vvp.exe"
sources = [
    SIM / "tb_video_latency_osd.v",
    SIM / "osd_overlay_baseline.v",
    ROOT / "user_source/hdl_source/osd_overlay.v",
    ROOT / "user_source/hdl_source/osd_font_rom.v",
    ROOT / "user_source/hdl_source/osd_logo_rom.v",
]
subprocess.run([iverilog, "-g2012", "-Wall", "-s", "tb", "-o", str(SIM / "sim.vvp"),
                *map(str, sources)], cwd=ROOT, check=True)
result = subprocess.run([vvp, str(SIM / "sim.vvp")], cwd=ROOT, check=False,
                        text=True, capture_output=True, timeout=240)
(SIM / "result.log").write_text(result.stdout + result.stderr, encoding="utf-8")
print(result.stdout, end="")
result.check_returncode()
if "LATENCY_OSD_PASS" not in result.stdout:
    raise RuntimeError("Simulation finished without the required pass marker")

# These previews contain pixels emitted by the production RTL, not mockups.
from PIL import Image
import json
for name in ["frame", *[f"lat_{i}" for i in range(4)], *[f"status_{i}" for i in range(4)]]:
    Image.open(SIM / (name + ".ppm")).save(SIM / (name + ".png"))
(SIM.parent / "osd_checks.json").write_text(json.dumps({
    "pass": True,
    "pixels_checked": 3686400,
    "font_pixels": [5, 7], "character_pitch": 8,
    "latency_box": [92, 24, 104, 16],
    "status_box": [20, 684, 296, 32],
    "states_checked": ["ON", "OFF", "WAIT", "mixed"],
    "outside_panels_matches_original": True,
    "disabled_parameters_and_combinational_video_bypass": True,
    "td_run": False,
    "source_sha256": hashlib.sha256((ROOT / "user_source/hdl_source/osd_overlay.v").read_bytes()).hexdigest(),
}, indent=2) + "\n", encoding="utf-8")
