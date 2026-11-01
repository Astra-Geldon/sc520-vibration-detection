"""Check that passive AE metering preserves the original AWB video RTL.

Uses both real AWB revisions and the unchanged real signal_delay controller.
Only its vendor RAM primitive is replaced with a common synchronous RAM model.
The full ISP is checked statically: deleting AE-only additions must recover
every original non-comment Verilog token, including all video connections.
Never launches TD, synthesis, place-and-route, or bit generation.
"""
from pathlib import Path
import difflib
import hashlib
import json
import random
import re
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "validation/auto_exposure_20261101/sim_video_tap"
BEFORE = ROOT / "validation/auto_exposure_20261101/before"
AWB_REL = Path("user_source/hdl_source/awb.v")
ISP_REL = Path("user_source/hdl_source/isp/isp_top.v")
DELAY = ROOT / "user_source/hdl_source/signal_delay.v"


def without_comments(text):
    return re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)


def normalized(text):
    return re.sub(r"\s+", "", without_comments(text))


def sub_once(pattern, replacement, text):
    result, count = re.subn(pattern, replacement, text, flags=re.S)
    assert count == 1, (pattern, count)
    return result


def static_check():
    current = {rel: (ROOT / rel).read_text(encoding="utf-8", errors="replace")
               for rel in (AWB_REL, ISP_REL)}
    original = {rel: (BEFORE / rel).read_text(encoding="utf-8", errors="replace")
                for rel in (AWB_REL, ISP_REL)}
    awb = without_comments(current[AWB_REL])
    awb = sub_once(
        r"input\s+O_tready\s*,\s*output\s*\[5:0\]\s*O_ae_luma\s*,"
        r"\s*output\s*O_ae_valid\s*,\s*output\s*O_ae_frame_start",
        "input O_tready", awb)
    awb = sub_once(r"reg\s+S_ae_frame_start_d0\s*;", "", awb)
    awb = sub_once(r"S_ae_frame_start_d0\s*<=\s*1'b0\s*;", "", awb)
    awb = sub_once(r"S_ae_frame_start_d0\s*<=\s*I_tuser\s*;", "", awb)
    for lhs, rhs in (("O_ae_luma", "S_lgray_d0"),
                     ("O_ae_valid", "I_tvalid_r0"),
                     ("O_ae_frame_start", "S_ae_frame_start_d0")):
        awb = sub_once(rf"assign\s+{lhs}\s*=\s*{rhs}\s*;", "", awb)
    assert normalized(awb) == normalized(original[AWB_REL]), \
        "An original AWB video token changed beyond the additive AE tap"

    isp = without_comments(current[ISP_REL])
    isp = sub_once(
        r"output\s+I_tready\s*,\s*output\s*\[5:0\]\s*O_ae_luma\s*,"
        r"\s*output\s*O_ae_valid\s*,\s*output\s*O_ae_frame_start",
        "output I_tready", isp)
    isp = sub_once(r"reg\s*\[95:0\]\s*ae_bypass_rgb\s*;.*?"
                   r"assign\s+O_ae_frame_start\s*=\s*ae_bypass_fs\s*;", "", isp)
    isp = sub_once(
        r"\.O_tready\s*\(awb_O_tready\)\s*,\s*"
        r"\.O_ae_luma\s*\(O_ae_luma\)\s*,\s*"
        r"\.O_ae_valid\s*\(O_ae_valid\)\s*,\s*"
        r"\.O_ae_frame_start\s*\(O_ae_frame_start\)",
        ".O_tready(awb_O_tready)", isp)
    assert normalized(isp) == normalized(original[ISP_REL]), \
        "An original ISP video token or connection changed"
    (OUT / "production_delta.patch").write_text("".join(
        "".join(difflib.unified_diff(original[rel].splitlines(True),
                                    current[rel].splitlines(True),
                                    fromfile="before/" + rel.as_posix(),
                                    tofile=rel.as_posix()))
        for rel in (AWB_REL, ISP_REL)), encoding="utf-8")
    return original[AWB_REL]


RAM = r'''
// Test substitute only: the actual signal_delay controller remains in use.
module blk_mem_gen_awb_delay_signal(
    input clka, input wea, input [10:0] addra, input [95:0] dia,
    input clkb, input [10:0] addrb, output [95:0] dob);
    reg [95:0] mem[0:2047];
    reg [95:0] read0=0,read1=0;
    integer i;
    initial for(i=0;i<2048;i=i+1) mem[i]=0;
    always @(posedge clka) if(wea) mem[addra]<=dia;
    always @(posedge clkb) begin read0<=mem[addrb];read1<=read0;end
`ifdef TWO_RAM_CYCLES
    assign dob=read1;
`else
    assign dob=read0;
`endif
endmodule
'''


TB = r'''
`timescale 1ns/1ps
module tb;
    parameter integer VECTORS=1;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=1,enable=0,last=0,user=0,valid=0,ready=0;
    reg [95:0] data=0;
    wire old_last,old_user,old_valid,old_ready;
    wire new_last,new_user,new_valid,new_ready;
    wire [95:0] old_data,new_data;
    wire [5:0] ae_luma;
    wire ae_valid,ae_fs;
    awb_before #(.IMG_HEIGHT(20),.IMG_WIDTH(1280)) baseline(
        .I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_tlast(last),
        .I_tuser(user),.I_tdata(data),.I_tvalid(valid),.I_tready(old_ready),
        .O_tlast(old_last),.O_tuser(old_user),.O_tdata(old_data),
        .O_tvalid(old_valid),.O_tready(ready));
    awb #(.IMG_HEIGHT(20),.IMG_WIDTH(1280)) modified(
        .I_clk(clk),.I_rst_n(rst_n),.I_enable(enable),.I_tlast(last),
        .I_tuser(user),.I_tdata(data),.I_tvalid(valid),.I_tready(new_ready),
        .O_tlast(new_last),.O_tuser(new_user),.O_tdata(new_data),
        .O_tvalid(new_valid),.O_tready(ready),
        .O_ae_luma(ae_luma),.O_ae_valid(ae_valid),.O_ae_frame_start(ae_fs));
    reg [103:0] vectors[0:VECTORS-1];
    reg [7:0] expected_tap=0;
    integer luma;
    integer i,compared=0,valid_beats=0,ready_low=0,awb_off=0;
    integer fs_valid=0,fs_blank=0,gain_active=0,min_seen=63,max_seen=0;
    task check_video;
        begin
            if({new_last,new_user,new_valid,new_ready,new_data} !==
               {old_last,old_user,old_valid,old_ready,old_data})
                $fatal(1,"Video inequivalence vector=%0d",i);
            if(new_ready!==ready)
                $fatal(1,"Original ready pass-through changed vector=%0d",i);
            if({ae_fs,ae_valid,ae_luma}!==expected_tap)
                $fatal(1,"AE tap delay/value vector=%0d exp=%h got=%h",i,
                       expected_tap,{ae_fs,ae_valid,ae_luma});
            compared=compared+1;
        end
    endtask
    initial begin
        $readmemh("__VECTORS__",vectors);
        #1;rst_n=0;
        for(i=0;i<VECTORS;i=i+1)begin
            @(negedge clk);
            {rst_n,enable,last,user,valid,ready,data}=vectors[i][101:0];
            // Input changes must not leak through the registered AE tap.
            if(!rst_n) expected_tap=0;
            #1;check_video();
            @(posedge clk);
            luma=(data[23:16]+2*data[15:8]+data[7:0])/16;
            expected_tap=rst_n ? {user,valid,luma[5:0]} : 8'd0;
            #1;check_video();
            if(rst_n)begin
                if(valid)begin
                    valid_beats=valid_beats+1;
                    if(!enable)awb_off=awb_off+1;
                    if(luma<min_seen)min_seen=luma;
                    if(luma>max_seen)max_seen=luma;
                end
                if(!ready)ready_low=ready_low+1;
                if(user && valid)fs_valid=fs_valid+1;
                if(user && !valid)fs_blank=fs_blank+1;
                if(modified.in_r_r1!=20'h10000 || modified.in_b_r1!=20'h10000)
                    gain_active=gain_active+1;
                if({modified.in_r_r1,modified.in_b_r1,modified.sample_count}!==
                   {baseline.in_r_r1,baseline.in_b_r1,baseline.sample_count})
                    $fatal(1,"AWB adaptive state changed vector=%0d",i);
            end
        end
        if(valid_beats<40000 || awb_off<1000 || ready_low<1000 ||
           fs_valid<2 || fs_blank<2 || gain_active<1000 || min_seen!=0 || max_seen!=63)
            $fatal(1,"Missing coverage valid=%0d off=%0d ready0=%0d FS=%0d/%0d gains=%0d luma=%0d..%0d",
                   valid_beats,awb_off,ready_low,fs_valid,fs_blank,gain_active,min_seen,max_seen);
        $display("AE_VIDEO_TAP_PASS cycles=%0d comparisons=%0d valid=%0d awb_off=%0d ready_low=%0d gain_active=%0d luma=%0d..%0d",
                 VECTORS,compared,valid_beats,awb_off,ready_low,gain_active,min_seen,max_seen);
        $finish;
    end
endmodule
'''


def make_vectors():
    rng = random.Random(20261101)
    words = []

    def tick(reset_n=1, enable=1, last=0, user=0, valid=0, ready=None, rgb=None):
        data = rng.getrandbits(96)
        if rgb is not None:
            data = (data & ~0xffffff) | (rgb[0] << 16) | (rgb[1] << 8) | rgb[2]
        bits = (reset_n << 5) | (enable << 4) | (last << 3) | (user << 2)
        bits |= (valid << 1) | (rng.randrange(2) if ready is None else ready)
        words.append(data | (bits << 96))

    tick(reset_n=0)
    tick(reset_n=0)
    for _ in range(130):
        tick(valid=rng.randrange(2))
    # Real AWB needs at least 4096 accepted samples to commit non-unity gains.
    # These 20-line frames provide 6400, then exercise rejected dark/saturated
    # pixels, raw input changes in blanking, valid holes, and enable switching.
    for frame in range(8):
        enable = int(frame % 3 != 2)
        coincident = frame % 2 == 0
        if not coincident:
            tick(enable=enable, user=1)
        for row in range(20):
            for beat in range(320):
                choices = ((40, 80, 30), (64, 96, 64), (0, 0, 0),
                           (255, 255, 255), (80, 100, 40), (32, 64, 60))
                rgb = choices[frame % len(choices)]
                if beat == 10:
                    rgb = (0, 0, 0)
                elif beat == 11:
                    rgb = (255, 255, 255)
                tick(enable=enable, valid=1, last=int(beat == 319), rgb=rgb,
                     user=int(coincident and row == 0 and beat == 0))
                if frame % 2 and beat % 29 == 13:
                    tick(enable=enable)
            for _ in range(140):
                tick(enable=enable)
        for _ in range(125):
            tick(enable=enable)
    # Consecutive FS, reset with active input, and enable changes mid-stream.
    for _ in range(3):
        tick(user=1, valid=1)
    tick(reset_n=0, user=1, valid=1)
    tick(reset_n=0, valid=1)
    for i in range(2000):
        tick(enable=i % 2, valid=int(i % 7 != 0), user=int(i % 311 == 0),
             last=int(i % 29 == 0))
    return words


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    paths = (ROOT / AWB_REL, ROOT / ISP_REL, DELAY)
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in paths}
    before = static_check()
    before = sub_once(r"\bmodule\s+awb\b", "module awb_before", before)
    old_rtl = OUT / "awb_before.v"
    old_rtl.write_text(before, encoding="utf-8")
    (OUT / "ram_model.v").write_text(RAM, encoding="utf-8")
    words = make_vectors()
    vectors = OUT / "vectors.hex"
    vectors.write_text("".join(f"{word:026x}\n" for word in words), encoding="ascii")
    bench = OUT / "tb.v"
    bench.write_text(TB.replace("__VECTORS__", vectors.as_posix()), encoding="utf-8")
    iv = shutil.which("iverilog") or r"C:\iverilog\bin\iverilog.exe"
    vvp = shutil.which("vvp") or r"C:\iverilog\bin\vvp.exe"
    results = []
    for name, defines in (("normal_ram1", []),
                          ("normal_ram2", ["TWO_RAM_CYCLES"]),
                          ("raw_pass", ["RAW_PASS"])):
        executable = OUT / (name + ".vvp")
        compile_result = subprocess.run([
            iv, "-g2012", "-Wall", "-s", "tb", f"-Ptb.VECTORS={len(words)}",
            *[f"-D{define}" for define in defines], "-o", str(executable),
            str(bench), str(old_rtl), str(ROOT / AWB_REL), str(DELAY),
            str(OUT / "ram_model.v")], cwd=ROOT, capture_output=True, text=True, timeout=60)
        (OUT / (name + ".compile.log")).write_text(
            compile_result.stdout + compile_result.stderr, encoding="utf-8")
        compile_result.check_returncode()
        result = subprocess.run([vvp, str(executable)], cwd=ROOT,
                                capture_output=True, text=True, timeout=120)
        (OUT / (name + ".result.log")).write_text(result.stdout + result.stderr,
                                                   encoding="utf-8")
        print(name + ": " + result.stdout, end="", flush=True)
        result.check_returncode()
        assert "AE_VIDEO_TAP_PASS" in result.stdout
        results.append({"case": name, "pass": True, "cycles": len(words)})
    for path in paths:
        assert hashlib.sha256(path.read_bytes()).hexdigest() == hashes[str(path.relative_to(ROOT))], \
            "Production RTL changed during validation; rerun against one stable snapshot"
    summary = {"pass": True, "td_run": False, "source_sha256": hashes,
               "static": {"awb_original_tokens_preserved": True,
                          "isp_original_tokens_and_video_connections_preserved": True,
                          "isp_ae_ports_pass_through": True},
               "simulation": {"video_ports": ["data", "valid", "user", "last", "ready"],
                              "compared_at": "Each input change and each rising clock",
                              "tap_reference": "Externally supplied RGB/input FS/valid, registered once",
                              "vendor_ram_substitute": True,
                              "real_awb_and_signal_delay_used": True,
                              "cases": results},
               "limit": "RTL equivalence with shared behavioral RAM does not establish physical timing"}
    (OUT.parent / "video_tap_checks.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
