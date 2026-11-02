#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""对照3841376归档RTL，验证融合处理重排没有改变像素、OSD或视频时序。"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
HDL = ROOT / "user_source/hdl_source"
IV = Path(r"C:\Users\lenovo\AppData\Local\iverilog\bin\iverilog.exe")
REFERENCE_COMMIT = "38413764adee46320d03507684ba582ea9073d10"


def archived(relative: str) -> str:
    return subprocess.check_output(["git", "show", REFERENCE_COMMIT + ":" + relative], cwd=ROOT).decode("utf-8")


def declarations(top: str) -> str:
    start = top.index("    wire [23:0] S_lift_data")
    return top[start:top.index("    assign O_screen_pwm", start)]


def instance(top: str, marker: str) -> str:
    start = top.index(marker)
    return top[start:top.index("    );", start) + len("    );")]


def pipeline(top: str) -> str:
    start = top.index("    // Reuse the mixer's existing first pixel register;")
    end_marker = "    hdmi_mixer #("
    mixer_start = top.index(end_marker, start)
    end = top.index("    );", mixer_start) + len("    );")
    text = top[start:end]
    controller = instance(top, "    adaptive_n1_control u_adaptive_n1_control (")
    assert controller in text
    # 独立指定强度以覆盖所有0..8档，不让帧级控制器的触发场景限制像素覆盖。
    return text.replace(controller, "    assign S_n1_extra_strength = test_strength;", 1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    summary = {"pass": False, "scope": "当前top实际流水与3841376归档融合RTL逐拍对照，无TD编译或上板"}
    deps = [HDL / name for name in ["fixed_n1_lift.v", "hdmi_mixer.v", "osd_overlay.v", "osd_font_rom.v", "osd_logo_rom.v"]]
    top = (HDL / "design_top_wrapper.v").read_text(encoding="utf-8")
    old_top = archived("user_source/hdl_source/design_top_wrapper.v")
    summary["reference_commit"] = REFERENCE_COMMIT
    summary["source_sha256"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [HDL / "design_top_wrapper.v", *deps]}
    try:
        assert ".POST_STAGE_EN ( 1 )" in top
        # 使用提交中的独立旧模块，而不是用新实现的组合再作参考。
        old_n1 = archived("user_source/hdl_source/fixed_n1_lift.v")
        old_n1 = re.sub(r"\b(fixed_n1_\w+|adaptive_n1_control)\b", r"reference_\1", old_n1)
        (out / "reference_n1.v").write_text(old_n1, encoding="utf-8", newline="\n")
        old_mixer = archived("user_source/hdl_source/hdmi_mixer.v").replace("module hdmi_mixer #(", "module reference_hdmi_mixer #(", 1)
        (out / "reference_mixer.v").write_text(old_mixer, encoding="utf-8", newline="\n")
        common = {
            "S_hdmi_pixel_clk", "S_hdmi_rst_n", "S_hdmi_vsync", "S_hdmi_hsync", "S_hdmi_de", "S_hdmi_user", "S_hdmi_last",
            "S_imgp_data", "S_img_mode", "S_demo_hdmi", "S_demo_raw", "S_latency_bcd", "S_latency_valid", "S_demo_alg_state", "S_demo_alg_pending",
        }
        def rename_reference(text: str) -> str:
            text = re.sub(r"\bS_\w+\b", lambda m: m[0] if m[0] in common else "reference_" + m[0], text)
            text = re.sub(r"\bu_\w+\b", lambda m: "reference_" + m[0], text)
            text = re.sub(r"\bfixed_n1_lift\b", "reference_fixed_n1_lift", text)
            return re.sub(r"\bhdmi_mixer\b", "reference_hdmi_mixer", text)
        body = r'''
`timescale 1ns/1ps
module tb;
reg S_hdmi_pixel_clk=0;
always #5 S_hdmi_pixel_clk=~S_hdmi_pixel_clk;
reg S_hdmi_rst_n=0;
reg S_hdmi_vsync=0,S_hdmi_hsync=0,S_hdmi_de=0,S_hdmi_user=0,S_hdmi_last=0;
reg [23:0] S_imgp_data=0;
reg [2:0] S_img_mode=0;
reg [5:0] S_demo_hdmi=6'b111111;
reg S_demo_raw=0;
reg [15:0] S_latency_bcd=16'h1234;
reg S_latency_valid=1;
reg [5:0] S_demo_alg_state=6'b111111,S_demo_alg_pending=0;
reg [3:0] test_strength=0;
wire [23:0] S_osd_mix,S_hdmi_out_data,reference_S_osd_mix,reference_S_hdmi_out_data;
wire S_hdmi_out_vsync,S_hdmi_out_hsync,S_hdmi_out_de,S_hdmi_window_rd_en;
wire reference_S_hdmi_out_vsync,reference_S_hdmi_out_hsync,reference_S_hdmi_out_de,reference_S_hdmi_window_rd_en;
integer checks=0,active_checks=0,reads=0,old_reads=0,age=0;
integer f,x,y,rows,c;
reg [23:0] pattern;
always @(posedge S_hdmi_pixel_clk) begin
    if(S_hdmi_rst_n && S_hdmi_window_rd_en) reads=reads+1;
    #1;
    if(!S_hdmi_rst_n) age=0;
    else begin
        age=age+1;
        if(age>6) begin
            if({S_hdmi_out_vsync,S_hdmi_out_hsync,S_hdmi_out_de,S_hdmi_out_data} !==
                {reference_S_hdmi_out_vsync,reference_S_hdmi_out_hsync,reference_S_hdmi_out_de,reference_S_hdmi_out_data})
                $fatal(1,"融合流水不等价 cycle=%0d frame=%0d xy=%0d/%0d mode=%0d strength=%0d dut=%06x ref=%06x de=%b/%b",checks,f,x,y,S_img_mode,test_strength,S_hdmi_out_data,reference_S_hdmi_out_data,S_hdmi_out_de,reference_S_hdmi_out_de);
            if(S_hdmi_window_rd_en !== reference_S_hdmi_window_rd_en)
                $fatal(1,"DDR读请求改变");
            checks=checks+1;
            if(S_hdmi_out_de) active_checks=active_checks+1;
        end
    end
end
''' + declarations(top) + rename_reference(declarations(old_top)) + pipeline(top) + rename_reference(pipeline(old_top)) + r'''
task blank;
    input integer cycles;
    integer j;
    begin
        for(j=0;j<cycles;j=j+1) begin
            @(negedge S_hdmi_pixel_clk);
            S_hdmi_de=0; S_hdmi_last=0; S_imgp_data=24'h987654;
        end
    end
endtask
initial begin
    #1 S_hdmi_rst_n=1; #1 S_hdmi_rst_n=0;
    blank(8); @(negedge S_hdmi_pixel_clk); S_hdmi_rst_n=1; blank(10);
    for(f=0;f<15;f=f+1) begin
        // 前两帧完整覆盖Logo、模式文字、延时与左下状态面板。
        rows=(f<2)?720:48;
        test_strength=(f==0)?0:((f==1)?8:((f<=10)?f-2:8));
        S_img_mode=(f<=10)?0:f-10;
        S_demo_hdmi[1]=(f!=13);
        S_demo_raw=(f==14);
        S_demo_alg_state=(f%2)?6'b101010:6'b010101;
        S_demo_alg_pending=(f==1)?6'b000100:0;
        S_latency_bcd=16'h1234+f; S_latency_valid=(f!=3);
        @(negedge S_hdmi_pixel_clk); S_hdmi_vsync=1; S_hdmi_user=1;
        blank(8); @(negedge S_hdmi_pixel_clk); S_hdmi_vsync=0; S_hdmi_user=0;
        old_reads=reads;
        for(y=0;y<rows;y=y+1) begin
            S_hdmi_hsync=1; blank(8); S_hdmi_hsync=0;
            for(x=0;x<1280;x=x+1) begin
                @(negedge S_hdmi_pixel_clk); S_hdmi_de=1; S_hdmi_last=(x==1279);
                if(x%32==0) begin
                    c=((x/32)*19+y*13+f*7)&255;
                    case((x/32)%4)
                      0: pattern={8'(c),8'(c),8'(c)};
                      1: pattern={8'(c),8'(c/2),8'(c/3)};
                      2: pattern={8'(c/2),8'(c),8'(c/3)};
                      3: pattern={8'(c/3),8'(c/2),8'(c)};
                    endcase
                end
                S_imgp_data=pattern;
                if(x==0||x==1279) S_imgp_data=24'hffffff;
                if(x==1278) S_imgp_data=24'h000000;
            end
            blank(5);
        end
        blank(12);
        if(reads-old_reads!=1280*rows) $fatal(1,"帧读数量改变 frame=%0d reads=%0d",f,reads-old_reads);
        $display("PASS frame=%0d rows=%0d mode=%0d strength=%0d",f,rows,S_img_mode,test_strength);
    end
    blank(12); @(negedge S_hdmi_pixel_clk); S_hdmi_rst_n=0; blank(4);
    @(negedge S_hdmi_pixel_clk); S_hdmi_rst_n=1; blank(12);
    $display("PASS fusion_pipeline cycles=%0d active=%0d reads=%0d",checks,active_checks,reads);
    $finish;
end
endmodule
'''
        bench = out / "tb_fusion_pipeline.v"
        bench.write_text(body, encoding="utf-8", newline="\n")
        binary = out / "fusion_pipeline.vvp"
        built = subprocess.run([str(IV), "-g2012", "-Wall", "-s", "tb", "-o", str(binary), str(bench), str(out / "reference_n1.v"), str(out / "reference_mixer.v"), *map(str, deps)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        (out / "compile.log").write_bytes(built.stdout)
        if built.returncode:
            raise RuntimeError(built.stdout.decode("utf-8", errors="replace"))
        with (out / "simulation.log").open("wb") as log:
            run = subprocess.run([str(IV.with_name("vvp.exe")), "-i", str(binary)], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=900)
        text = (out / "simulation.log").read_text(encoding="utf-8", errors="replace")
        print(text, end="")
        if run.returncode:
            raise RuntimeError("融合流水RTL仿真失败，见simulation.log")
        result = re.search(r"PASS fusion_pipeline cycles=(\d+) active=(\d+) reads=(\d+)", text)
        assert result
        summary.update({"pass": True, "compared_cycles": int(result[1]), "active_pixel_checks": int(result[2]), "ddr_read_requests": int(result[3]), "full_720p_frames": 2, "short_frames_1280x48": 13, "strengths": list(range(9)), "mode_coverage": [0, 1, 2, 3, 4], "checks": ["逐像素含Logo/OSD输出", "DE/VS/HS逐拍", "DDR读请求与每帧数量", "复位及消隐", "开关及RAW旁路", "总流水延迟一致"]})
        return 0
    except Exception as error:
        summary["error"] = str(error)
        print(str(error))
        return 1
    finally:
        (out / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
