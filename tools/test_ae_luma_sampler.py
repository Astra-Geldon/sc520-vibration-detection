"""外部视频流测试：独立复现8桶背景P60测光，不启动TD。

参考模型保存每帧有效像素并独立执行每N个像素抽样；背景P60排除56以上
高光，P60低于22增曝、高于30减曝，近饱和达到10%时紧急减曝，背景
有效样本不足40%时保持。测试同时覆盖边界帧长、禁用帧、序号回卷和完整
720p帧，不读取DUT计数器或累加器。
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "validation/auto_exposure_20261101/sim_sampler"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = ROOT / "user_source/hdl_source/ae_luma_sampler.v"


class Stream:
    HIGHLIGHT_EXCLUDE = 56
    NEAR_CLIP_LUMA = 60
    BG_LOW_LUMA = 22
    BG_HIGH_LUMA = 30
    EMERGENCY_CLIP_PERCENT = 10
    BACKGROUND_MIN_PERCENT = 40

    def __init__(self, expected, log2):
        self.expected = expected
        self.period = 1 << log2
        self.words = []
        self.publications = []
        self.reset_model()

    def reset_model(self):
        self.fs_before = False
        self.pixels = None
        self.enabled = False
        self.packet = 0
        self.output_valid = False

    def tick(self, fs=0, valid=0, enabled=1, luma=0, reset_n=1):
        if not reset_n:
            self.reset_model()
        else:
            rising = fs and not self.fs_before
            self.fs_before = bool(fs)
            if rising:
                if self.pixels is not None:
                    exact_length = len(self.pixels) == self.expected * self.period
                    if not exact_length or not self.enabled:
                        state = 3
                    else:
                        samples = self.pixels[::self.period]
                        bins = [0] * 8
                        near_clip = 0
                        for value in samples:
                            if value >= self.HIGHLIGHT_EXCLUDE:
                                bins[7] += 1
                            else:
                                bins[min(value >> 3, 6)] += 1
                            near_clip += value >= self.NEAR_CLIP_LUMA
                        background = sum(bins[:7])
                        if near_clip >= (self.expected * self.EMERGENCY_CLIP_PERCENT + 99) // 100:
                            state = 2
                        elif background < (self.expected * self.BACKGROUND_MIN_PERCENT + 99) // 100:
                            state = 0
                        else:
                            cumulative = 0
                            p60 = 59
                            representatives = (3, 11, 19, 27, 35, 43, 51)
                            for index in range(7):
                                cumulative += bins[index]
                                if cumulative * 5 >= background * 3:
                                    p60 = representatives[index]
                                    break
                            state = 1 if p60 < self.BG_LOW_LUMA else (
                                2 if p60 > self.BG_HIGH_LUMA else 0)
                    sequence = ((self.packet >> 2) + 1) % 16
                    self.packet = sequence * 4 + state
                    self.output_valid = True
                    self.publications.append((sequence, state))
                self.pixels = []
                self.enabled = bool(enabled)
            elif self.pixels is not None:
                self.enabled &= bool(enabled)
            if self.pixels is not None and valid:
                self.pixels.append(luma)
        word = luma | (enabled << 6) | (valid << 7) | (fs << 8) | (reset_n << 9)
        word |= self.packet << 10
        word |= int(self.output_valid) << 16
        self.words.append(word)

    def frame(self, selected, beats=None, coincident=True, blanks=True,
              enabled=True, disable_at=None, held_fs=False):
        beats = self.expected * self.period if beats is None else beats
        values = [selected[(i // self.period) % len(selected)]
                  if i % self.period == 0 else (63 if i % 2 else 0)
                  for i in range(beats)]
        sent = 0
        self.tick(fs=1, valid=int(coincident), enabled=int(enabled),
                  luma=values[0] if coincident else 0)
        if coincident:
            sent = 1
        if held_fs:
            self.tick(fs=1, valid=1, enabled=int(enabled), luma=values[sent])
            sent += 1
        self.tick(fs=0, enabled=int(enabled))
        for i in range(sent, beats):
            self.tick(valid=1, enabled=int(enabled and i != disable_at), luma=values[i])
            if blanks and i % 11 == 7:
                self.tick(enabled=int(enabled), luma=63)
        self.tick(enabled=int(enabled))


TB = r'''
`timescale 1ns/1ps
module tb;
    parameter EXPECTED=4;
    parameter LOG2=4;
    parameter VECTORS=1;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=1,fs=0,valid=0,enable=0;
    reg [5:0] luma=0;
    wire [5:0] measure;
    wire output_valid;
    ae_luma_sampler #(.EXPECTED_SAMPLES(EXPECTED),.SAMPLE_LOG2(LOG2)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_frame_start(fs),.I_valid(valid),
        .I_enable(enable),.I_luma(luma),.O_measure(measure),.O_valid(output_valid));
    reg [31:0] vectors[0:VECTORS-1];
    integer i;
    initial begin
        $readmemh("__VECTORS__",vectors);
        #1;rst_n=0;
        for(i=0;i<VECTORS;i=i+1)begin
            @(negedge clk);
            {rst_n,fs,valid,enable,luma}=vectors[i][9:0];
            @(posedge clk);#1;
            if({output_valid,measure}!==vectors[i][16:10])
                $fatal(1,"Vector %0d expected packet=%h valid=%b actual=%h/%b",i,
                       vectors[i][15:10],vectors[i][16],measure,output_valid);
        end
        $display("AE_LUMA_SAMPLER_PASS expected=%0d sample_log2=%0d cycles=%0d",EXPECTED,LOG2,VECTORS);
        $finish;
    end
endmodule
'''


def run(name, stream, log2):
    folder = OUT / name
    folder.mkdir(exist_ok=True)
    vectors = folder / "vectors.hex"
    vectors.write_text("".join(f"{v:08x}\n" for v in stream.words), encoding="ascii")
    bench = folder / "tb.v"
    # Icarus在$readmemh中对非ASCII绝对路径处理不稳定，仿真工作目录固定在
    # case目录并只传入ASCII文件名。
    bench.write_text(TB.replace("__VECTORS__", vectors.name), encoding="utf-8")
    executable = folder / "sampler.vvp"
    iv = shutil.which("iverilog") or r"C:\Users\lenovo\AppData\Local\iverilog\bin\iverilog.exe"
    vvp = shutil.which("vvp") or r"C:\Users\lenovo\AppData\Local\iverilog\bin\vvp.exe"
    compile_result = subprocess.run([
        iv, "-g2012", "-Wall", "-s", "tb", f"-Ptb.EXPECTED={stream.expected}",
        f"-Ptb.LOG2={log2}", f"-Ptb.VECTORS={len(stream.words)}", "-o", str(executable),
        bench.name, str(SOURCE),
    ], cwd=folder, capture_output=True, text=True, timeout=60)
    (folder / "compile.log").write_text(compile_result.stdout + compile_result.stderr, encoding="utf-8")
    compile_result.check_returncode()
    result = subprocess.run([vvp, executable.name], cwd=folder,
                            capture_output=True, text=True, timeout=120)
    (folder / "result.log").write_text(result.stdout + result.stderr, encoding="utf-8")
    print(result.stdout, end="", flush=True)
    result.check_returncode()
    assert "AE_LUMA_SAMPLER_PASS" in result.stdout
    return {"case": name, "pass": True, "cycles": len(stream.words),
            "published_frames": len(stream.publications)}


def main():
    small = Stream(4, 4)
    small.tick(reset_n=0)
    # Valid traffic before the first frame marker must never publish a frame.
    for _ in range(25):
        small.tick(valid=1, luma=63)
    small.frame([0])
    small.frame([15], coincident=False)
    small.frame([16], held_fs=True)
    small.frame([24])
    small.frame([25])
    # P60代表值35越过30阈值，触发普通减E（不依赖近饱和保护）。
    small.frame([32])
    # 56以上高光不进入背景；全帧高光但未达到近饱和门限时保持。
    small.frame([56])
    small.frame([63])
    small.frame([8, 24, 16, 16])
    # 背景恰好达到40%时有效，只有两点背景时P60仍按背景分布计算。
    small.frame([56, 56, 16, 16])
    # 背景只有25%时保持。
    small.frame([56, 56, 56, 16])
    small.frame([20], beats=63)
    small.frame([20], beats=48)
    small.frame([20], beats=65)
    small.frame([20], beats=80)
    small.frame([20], enabled=False)
    small.frame([20], disable_at=23)
    small.frame([20])
    for _ in range(20):
        small.frame([20], blanks=False)
    small.tick(fs=1)
    expected_classes = [1, 1, 1, 0, 0, 2, 0, 2, 1, 1, 0,
                        3, 3, 3, 3, 3, 3, 1] + [1] * 20
    assert [state for _, state in small.publications] == expected_classes
    assert any(seq == 0 for seq, _ in small.publications), "Sequence wrap not exercised"
    # Reset halfway into acquisition discards partial history and publication.
    small.tick(fs=0)
    small.tick(valid=1, luma=63)
    small.tick(reset_n=0)
    small.frame([16])
    small.tick(fs=1)
    assert small.publications[-1] == (1, 1)

    no_decimation = Stream(4, 0)
    no_decimation.tick(reset_n=0)
    no_decimation.frame([0, 63, 0, 63], blanks=False)
    no_decimation.frame([16], held_fs=True)
    no_decimation.tick(fs=1)
    assert no_decimation.publications == [(1, 2), (2, 1)]

    full = Stream(14400, 4)
    full.tick(reset_n=0)
    full.frame([63], blanks=False)
    full.frame([16], coincident=False, blanks=False)
    full.tick(fs=1)
    assert full.publications == [(1, 2), (2, 1)]

    results = [run("edge_cases", small, 4), run("no_decimation", no_decimation, 0),
               run("720p", full, 4)]
    summary = {"pass": True, "td_run": False,
               "reference": "External frame pixels and validity, independent 8-bin background P60 model",
               "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
               "cases": results}
    (OUT.parent / "sampler_checks.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
