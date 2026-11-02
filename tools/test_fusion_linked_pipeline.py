#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""抽取真实融合显示流水，与归档N1及混合器组成的独立参考逐拍对照。"""

from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
HDL = ROOT / "user_source/hdl_source"
BASELINE = "d755598"
IVERILOG = Path(shutil.which("iverilog") or
                r"C:\Users\lenovo\AppData\Local\iverilog\bin\iverilog.exe")


def archived(relative: str) -> str:
    return subprocess.check_output(
        ["git", "show", BASELINE + ":" + relative], cwd=ROOT).decode("utf-8")


def instance(top: str, marker: str) -> str:
    start = top.index(marker)
    return top[start:top.index("    );", start) + len("    );")]


def actual_declarations(top: str) -> str:
    start = top.index("    wire [23:0] S_lift_data, S_tone_stage_data;")
    end = top.index("    reg [2:0] S_tone_stage_mode;", start)
    return top[start:top.index(";", end) + 1]


def actual_pipeline(top: str) -> str:
    start = top.index("    // 复用混合器既有的第一级像素寄存器")
    mixer_start = top.index("    hdmi_mixer #(", start)
    end = top.index("    );", mixer_start) + len("    );")
    pipeline = top[start:end]
    controller = instance(top, "    fusion_lift_control u_fusion_lift_control (")
    assert controller in pipeline
    return pipeline.replace(controller,
                            "    assign S_fusion_strength = test_strength;\n"
                            "    assign S_fusion_triggered = (test_strength != 0);", 1)


PREAMBLE = r'''
`timescale 1ns/1ps
module tb;
reg S_hdmi_pixel_clk=0;
always #5 S_hdmi_pixel_clk=~S_hdmi_pixel_clk;
reg S_hdmi_rst_n=0;
reg S_hdmi_vsync=0,S_hdmi_hsync=0,S_hdmi_de=0,S_hdmi_user=0,S_hdmi_last=0;
reg [23:0] S_imgp_data=0;
reg [2:0] S_img_mode=0;
reg [5:0] S_demo_hdmi=6'b111111;
reg S_demo_raw=0,S_demo_hdmi_valid=1,S_demo_mipi_status_valid=1;
reg [15:0] S_latency_bcd=16'h1234;
reg S_latency_valid=1;
reg [5:0] S_demo_alg_state=6'b111111,S_demo_alg_pending=0;
reg [4:0] test_strength=0;
wire [23:0] S_osd_mix,S_hdmi_out_data;
wire S_hdmi_out_vsync,S_hdmi_out_hsync,S_hdmi_out_de,S_hdmi_window_rd_en;

wire [23:0] ref_stage1,ref_original,ref_envelope,ref_blended,ref_osd_data,ref_out_data;
wire ref_de1,ref_vs1,ref_de2,ref_vs2,ref_out_de,ref_out_vs,ref_out_hs,ref_rd;
reg [7:0] ref_peak1=0,ref_peak2=0;
reg [2:0] ref_mode1=0,ref_mode2=0;
reg ref_enable=0;
reg [4:0] ref_strength=0;
reg [5:0] ref_alg_state=0,ref_alg_pending=0;
reg [15:0] ref_latency_bcd=0;
reg ref_latency_valid=0;
wire ref_enable_now=S_demo_hdmi_valid && S_demo_mipi_status_valid &&
                    S_demo_hdmi[4] && !S_demo_raw && (ref_mode1==0);
integer checks=0,active_checks=0,reads=0,ref_reads=0,age=0;
integer bypass_checks=0,highlight_checks=0,logo_checks=0,status_checks=0;
integer gamma_on_checks=0,gamma_off_checks=0;
integer f,x,y,rows,c,old_reads,old_ref_reads;
reg [23:0] pattern;

function integer peak;
    input [23:0] rgb;
    integer v;
    begin
        v=(rgb[23:16]>rgb[15:8])?rgb[23:16]:rgb[15:8];
        peak=(v>rgb[7:0])?v:rgb[7:0];
    end
endfunction

// 参考路径保持原始像素通过归档混合器，在第二级直接做独立整数混合。
// 它不调用新的envelope/blend模块，也不读取被测后级寄存器。
always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
    if(!S_hdmi_rst_n) begin
        ref_peak1<=0; ref_peak2<=0; ref_mode1<=0; ref_mode2<=0;
        ref_enable<=0; ref_strength<=0; ref_alg_state<=0; ref_alg_pending<=0;
        ref_latency_bcd<=0; ref_latency_valid<=0;
    end else begin
        ref_peak1<=peak(S_imgp_data); ref_peak2<=ref_peak1;
        ref_mode1<=S_img_mode; ref_mode2<=ref_mode1;
        ref_enable<=ref_enable_now; ref_strength<=test_strength;
        ref_alg_state<=S_demo_alg_state; ref_alg_pending<=S_demo_alg_pending;
        ref_latency_bcd<=S_latency_bcd; ref_latency_valid<=S_latency_valid;
    end
end

reference_fixed_n1_lift ref_n1(.I_de(ref_de2), .I_enable(ref_enable),
    .I_data(ref_original), .I_peak(ref_peak2), .I_extra_strength(4'd0), .O_data(ref_envelope));
function [7:0] mix_channel;
    input integer original,envelope,strength;
    integer result;
    begin
        result=original+((envelope-original)*strength+8)/16;
        mix_channel=result;
    end
endfunction
assign ref_blended=(!ref_de2 || !ref_enable)?ref_original:{
    mix_channel(ref_original[23:16],ref_envelope[23:16],ref_strength),
    mix_channel(ref_original[15:8],ref_envelope[15:8],ref_strength),
    mix_channel(ref_original[7:0],ref_envelope[7:0],ref_strength)};

osd_overlay #(.OSD_EN(1), .LOGO_EN(1), .H_ACTIVE(1280), .V_ACTIVE(720),
    .LOGO_W(128), .LOGO_H(80), .LOGO_X(1136), .LOGO_Y(16),
    .TEXT_X(24), .TEXT_Y(24), .BOX_PAD(8)) ref_osd(
    .I_clk(S_hdmi_pixel_clk), .I_rst_n(S_hdmi_rst_n),
    .I_de(ref_de2), .I_vs(ref_vs2), .I_mode(ref_mode2),
    .I_latency_bcd(ref_latency_bcd), .I_latency_valid(ref_latency_valid),
    .I_alg_state(ref_alg_state), .I_alg_pending(ref_alg_pending),
    .I_n1_active(ref_strength!=0), .I_data(ref_blended), .O_data(ref_osd_data));
reference_hdmi_mixer #(.H_OFFSET(0), .V_OFFSET(0), .IMG_WIDTH(1280),
    .IMG_HEIGHT(720), .PIXEL_STAGE_EN(0), .POST_STAGE_EN(1)) ref_mixer(
    .I_clk(S_hdmi_pixel_clk), .I_rst_n(S_hdmi_rst_n),
    .I_video_vsync(S_hdmi_vsync), .I_video_hsync(S_hdmi_hsync),
    .I_video_de(S_hdmi_de), .I_video_user(S_hdmi_user), .I_video_last(S_hdmi_last),
    .O_video_rd_en(ref_rd), .I_video_rd_data(S_imgp_data),
    .O_stage_data(ref_stage1), .O_stage_de(ref_de1), .O_stage_vs(ref_vs1),
    .I_stage_result(24'd0), .O_post_stage_data(ref_original),
    .O_post_stage_de(ref_de2), .O_post_stage_vs(ref_vs2),
    .I_post_stage_result(ref_osd_data), .O_hdmi_vsync(ref_out_vs),
    .O_hdmi_hsync(ref_out_hs), .O_hdmi_de(ref_out_de), .O_hdmi_data(ref_out_data));

always @(posedge S_hdmi_pixel_clk) begin
    if(S_hdmi_rst_n && S_hdmi_window_rd_en) reads=reads+1;
    if(S_hdmi_rst_n && ref_rd) ref_reads=ref_reads+1;
    #1;
    if(!S_hdmi_rst_n) age=0;
    else begin
        age=age+1;
        if(age>8) begin
            if({S_hdmi_out_vsync,S_hdmi_out_hsync,S_hdmi_out_de,S_hdmi_out_data} !==
               {ref_out_vs,ref_out_hs,ref_out_de,ref_out_data})
                $fatal(1,"HDMI流水不符 cycle=%0d frame=%0d xy=%0d/%0d mode=%0d strength=%0d actual=%06x expected=%06x de=%b/%b",checks,f,x,y,S_img_mode,test_strength,S_hdmi_out_data,ref_out_data,S_hdmi_out_de,ref_out_de);
            if(S_hdmi_window_rd_en!==ref_rd) $fatal(1,"DDR读请求时序变化");
            if(S_fusion_enable!==ref_enable_now) $fatal(1,"SW5/mode/RAW使能与独立参考不符");
            if(S_post_lift_data!==ref_blended)
                $fatal(1,"OSD前像素不符 frame=%0d xy=%0d/%0d actual=%06x expected=%06x",f,x,y,S_post_lift_data,ref_blended);
            if({S_post_stage_mode,S_post_stage_enable,S_post_stage_strength,
                S_post_alg_state,S_post_alg_pending,S_post_latency_bcd,S_post_latency_valid} !==
               {ref_mode2,ref_enable,ref_strength,ref_alg_state,ref_alg_pending,ref_latency_bcd,ref_latency_valid})
                $fatal(1,"像素与模式/使能/状态/延迟元数据未对齐 frame=%0d xy=%0d/%0d",f,x,y);
            checks=checks+1;
            if(S_hdmi_out_de) active_checks=active_checks+1;
            if(ref_de2) begin
                if(!ref_enable || ref_strength==0) begin
                    if(S_post_lift_data!==ref_original) $fatal(1,"未补亮区域没有逐位旁路");
                    bypass_checks=bypass_checks+1;
                end
                if(ref_peak2>=192) begin
                    if(S_post_lift_data!==ref_original) $fatal(1,"高光原值被改变");
                    highlight_checks=highlight_checks+1;
                end
                if(ref_osd.S_in_logo) logo_checks=logo_checks+1;
                if(ref_osd.S_y>=600) status_checks=status_checks+1;
                if(S_demo_hdmi[1]) gamma_on_checks=gamma_on_checks+1;
                else gamma_off_checks=gamma_off_checks+1;
            end
        end
    end
end
'''


STIMULUS = r'''
task blank;
    input integer n;
    integer j;
    begin
        for(j=0;j<n;j=j+1) begin
            @(negedge S_hdmi_pixel_clk);
            S_hdmi_de=0; S_hdmi_last=0; S_imgp_data=24'h987654;
        end
    end
endtask
task reset;
    begin
        @(negedge S_hdmi_pixel_clk); S_hdmi_rst_n=0;
        blank(8);
        @(negedge S_hdmi_pixel_clk); S_hdmi_rst_n=1;
        blank(12);
    end
endtask
initial begin
    #1 S_hdmi_rst_n=1; #1 S_hdmi_rst_n=0;
    blank(8); reset;
    for(f=0;f<29;f=f+1) begin
        if(f==28) reset;
        rows=(f==0 || f==16)?720:24;
        test_strength=(f<=16)?f:16;
        S_img_mode=0; S_demo_raw=0; S_demo_hdmi=6'b111111;
        S_demo_hdmi_valid=1; S_demo_mipi_status_valid=1;
        if(f==17 || f==24) S_demo_hdmi[1]=0;
        if(f==18 || f==24) S_demo_hdmi[4]=0;
        if(f==19) S_demo_raw=1;
        if(f>=20 && f<=23) S_img_mode=f-19;
        if(f==25) S_demo_hdmi_valid=0;
        if(f==26) S_demo_mipi_status_valid=0;
        if(f==27) test_strength=9;
        S_demo_alg_state=(f%2)?6'b101010:6'b010101;
        S_demo_alg_pending=(f==16)?6'b001100:0;
        S_latency_bcd=16'h1234+f; S_latency_valid=(f!=3);
        @(negedge S_hdmi_pixel_clk); S_hdmi_vsync=1; S_hdmi_user=1;
        blank(8); @(negedge S_hdmi_pixel_clk); S_hdmi_vsync=0; S_hdmi_user=0;
        old_reads=reads; old_ref_reads=ref_reads;
        for(y=0;y<rows;y=y+1) begin
            S_hdmi_hsync=1; blank(8); S_hdmi_hsync=0;
            for(x=0;x<1280;x=x+1) begin
                @(negedge S_hdmi_pixel_clk); S_hdmi_de=1; S_hdmi_last=(x==1279);
                if(x%32==0) begin
                    c=((x/32)*19+y*13+f*7)&255;
                    case((x/32)%4)
                        0:pattern={8'(c),8'(c),8'(c)};
                        1:pattern={8'(c),8'(c/2),8'(c/3)};
                        2:pattern={8'(c/2),8'(c),8'(c/3)};
                        3:pattern={8'(c/3),8'(c/2),8'(c)};
                    endcase
                end
                S_imgp_data=pattern;
                if(x==0 || x==1279) S_imgp_data=24'hffffff;
                if(x==1278) S_imgp_data=24'h000000;
                if(f==27) begin
                    if(y==8 && x==400) S_demo_hdmi[4]=0;
                    if(y==8 && x==800) S_demo_hdmi[4]=1;
                    if(y==10 && x==400) S_img_mode=1;
                    if(y==10 && x==800) S_img_mode=0;
                    if(y==12 && x==400) S_demo_raw=1;
                    if(y==12 && x==800) S_demo_raw=0;
                    if(y==14 && x==400) S_demo_hdmi[1]=0;
                    if(y==14 && x==800) S_demo_hdmi[1]=1;
                    if(y==16 && x==400) test_strength=0;
                    if(y==16 && x==800) test_strength=16;
                end
            end
            blank(5);
        end
        blank(12);
        if(reads-old_reads!=1280*rows || ref_reads-old_ref_reads!=1280*rows)
            $fatal(1,"帧DDR读数量不符 frame=%0d reads=%0d reference=%0d expected=%0d",f,reads-old_reads,ref_reads-old_ref_reads,1280*rows);
        $display("PASS frame=%0d rows=%0d mode=%0d strength=%0d",f,rows,S_img_mode,test_strength);
    end
    blank(12); reset; blank(12);
    if(logo_checks==0 || status_checks==0 || gamma_on_checks==0 || gamma_off_checks==0)
        $fatal(1,"覆盖未遍历Logo、状态面板或SW2开关");
    $display("PASS fusion_linked_pipeline cycles=%0d active=%0d reads=%0d bypass=%0d highlights=%0d logo=%0d status=%0d gamma_on=%0d gamma_off=%0d",checks,active_checks,reads,bypass_checks,highlight_checks,logo_checks,status_checks,gamma_on_checks,gamma_off_checks);
    $finish;
end
endmodule
'''


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=ROOT / "validation/fusion_linked_pipeline_20261102")
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    sources = [HDL / name for name in ("design_top_wrapper.v", "fusion_shadow_lift.v",
                                     "hdmi_mixer.v", "osd_overlay.v", "osd_font_rom.v", "osd_logo_rom.v")]
    summary = {
        "pass": False, "td_run": False,
        "scope": "真实top显示段与归档N1/混合器及独立整数混合逐拍比较；控制器强度单独驱动",
        "source_sha256": {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                          for path in sources},
        "baseline_commit": subprocess.check_output(["git", "rev-parse", BASELINE], cwd=ROOT).decode().strip(),
    }
    try:
        top = sources[0].read_text(encoding="utf-8")
        old_n1 = archived("user_source/hdl_source/fixed_n1_lift.v")
        old_n1 = re.sub(r"\b(fixed_n1_\w+|adaptive_n1_control)\b", r"reference_\1", old_n1)
        old_mixer = archived("user_source/hdl_source/hdmi_mixer.v").replace(
            "module hdmi_mixer #(", "module reference_hdmi_mixer #(", 1)
        (out / "reference_n1.v").write_text(old_n1, encoding="utf-8", newline="\n")
        (out / "reference_mixer.v").write_text(old_mixer, encoding="utf-8", newline="\n")
        enable_statement = re.search(r"(?ms)^    wire S_fusion_enable\s*=.*?;", top)
        assert enable_statement and "S_demo_hdmi[4]" in enable_statement[0]
        assert "S_demo_hdmi[1]" not in enable_statement[0]
        body = PREAMBLE + actual_declarations(top) + "\n" + enable_statement[0] + "\n"
        body += actual_pipeline(top) + "\n" + STIMULUS
        tb = out / "pipeline_tb.v"
        tb.write_text(body, encoding="utf-8", newline="\n")
        binary = out / "pipeline.vvp"
        compile_sources = [tb.name, "reference_n1.v", "reference_mixer.v"]
        compile_sources += [os.path.relpath(path, out) for path in sources[1:]]
        built = subprocess.run(
            [str(IVERILOG), "-g2012", "-Wall", "-s", "tb", "-o", binary.name, *compile_sources],
            cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        (out / "compile.log").write_bytes(built.stdout)
        if built.returncode:
            raise AssertionError(built.stdout.decode("utf-8", errors="replace"))
        with (out / "simulation.log").open("wb") as log:
            run = subprocess.run([str(IVERILOG.with_name("vvp.exe")), "-i", binary.name],
                                 cwd=out, stdout=log, stderr=subprocess.STDOUT, timeout=900)
        result = (out / "simulation.log").read_text(encoding="utf-8", errors="replace")
        print(result, end="", flush=True)
        if run.returncode or "PASS fusion_linked_pipeline" not in result:
            raise AssertionError("显示流水仿真失败，见simulation.log")
        last_line = result.split("PASS fusion_linked_pipeline", 1)[1].splitlines()[0]
        summary.update({key: int(value) for key, value in re.findall(r"(\w+)=(\d+)", last_line)})
        summary.update({"pass": True, "full720p_frames": 2, "short1280x24_frames": 27,
                        "strengths": list(range(17)), "modes": [0, 1, 2, 3, 4],
                        "checks": ["HDMI像素与DE/HS/VS逐拍一致", "每帧DDR读数量及请求时序",
                                   "独立原图与元数据第二级对齐", "SW2与补亮使能独立",
                                   "SW5/RAW/模式/无效控制旁路", "Logo及下方状态面板",
                                   "帧内控制/模式/强度切换", "复位与消隐"]})
    except Exception as error:
        summary["error"] = str(error)
        print(str(error), flush=True)
    (out / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if summary["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
