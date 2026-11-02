"""验证融合版曝光请求、生效值、固定G12和KEY4去抖，不调用TD。"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess


CONTROL_BENCH = r'''
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,auto_en=1,freeze=0,done=1,cfg=0,mvalid=0;
reg [5:0] measure=0;
wire req,auto_applied,pending,valid,exposure_valid;
wire [15:0] ae,ag,applied_e;
integer requests=0,seq=0,wanted=0,expected=0,i=0,delta=0;
fusion_exposure_control dut(.I_clk(clk),.I_rst(rst),
 .I_auto_en(auto_en),.I_freeze(freeze),.I_measure(measure),.I_measure_valid(mvalid),
 .I_ae_cfg_done(done),.I_cam_cfg_done(cfg),.O_ae_req(req),.O_ae(ae),.O_ag(ag),
 .O_auto_applied(auto_applied),.O_pending(pending),.O_valid(valid),
 .O_applied_exposure(applied_e),.O_exposure_valid(exposure_valid));
reg [15:0] held_ae,held_ag;
reg was_waiting=0;
always @(negedge clk) if(!rst)begin
 if(req)begin
  requests=requests+1;
  if(valid || !pending || exposure_valid)$fatal(1,"请求未生效就发布有效状态");
  held_ae=ae;held_ag=ag;was_waiting=1;
  if(ag!=128)$fatal(1,"融合版请求改变了G12");
 end else if(was_waiting && !valid)begin
  if(ae!==held_ae || ag!==held_ag)$fatal(1,"写入期间参数被修改");
 end
 if(valid)was_waiting=0;
 if(exposure_valid && (!valid || pending || !cfg || freeze))
  $fatal(1,"过渡期或冻结期误报生效E有效");
end
task cycles;input integer n;begin repeat(n)@(negedge clk);#1;end endtask
task packet;input [1:0] cls;begin
 seq=(seq+1)%16;measure={seq[3:0],cls};mvalid=1;cycles(4);
end endtask
task quiet;input integer n;begin
 cycles(12);if(requests!=n)$fatal(1,"请求数%0d，预期%0d",requests,n);
end endtask
task ack;
 reg [15:0] before_e,target_e;
 begin
 before_e=applied_e;target_e=ae;
 done=0;cycles(5);
 if(valid || !pending || exposure_valid || applied_e!==before_e)
  $fatal(1,"忙状态误发布请求E");
 done=1;cycles(5);
 if(!valid || pending || applied_e!==target_e || exposure_valid===freeze)
  $fatal(1,"真实组写完成未发布生效E或冻结标志错误");
 end
endtask
task settling;begin packet(0);packet(0);packet(0);end endtask
task demand;
 input [1:0] cls;input integer value;input integer count;
 reg [15:0] before_e;
 begin
  before_e=applied_e;
  packet(cls);quiet(count-1);packet(cls);quiet(count);
  if(ae!=value || ag!=128)$fatal(1,"曝光步进%0d，预期%0d，增益%0d",ae,value,ag);
  if(applied_e!==before_e || exposure_valid)$fatal(1,"尚未生效的请求E泄露到补亮端");
 end
endtask
initial begin
 cycles(4);
 if(ae!=1990 || ag!=17 || valid || !pending || exposure_valid || applied_e!=0)
  $fatal(1,"复位状态错误");
 rst=0;cycles(4);quiet(0);cfg=1;cycles(5);quiet(1);
 if(ae!=900 || ag!=128 || auto_applied || valid || applied_e!=0)
  $fatal(1,"自动曝光初始请求错误");
 // done从未拉低时，持续为高也不能确认请求已生效。
 for(i=0;i<10;i=i+1)packet(1);
 quiet(1);if(valid || exposure_valid || applied_e!=0)$fatal(1,"done卡高被误认完成");
 ack();if(!auto_applied || applied_e!=900)$fatal(1,"自动模式确认失败");
 // 同一序号、写入期间的旧统计和中性/无效包均不触发额外调整。
 quiet(1);settling();quiet(1);
 packet(1);packet(2);packet(0);packet(1);quiet(1);packet(3);packet(1);quiet(1);
 packet(1);quiet(2);
 if(ae!=956 || applied_e!=900 || exposure_valid)$fatal(1,"新请求与生效值未隔离");
 cycles(30);quiet(2);if(applied_e!=900)$fatal(1,"done卡高污染生效E");
 ack();
 settling();for(i=0;i<10;i=i+1)begin packet(0);packet(3);end quiet(2);
 demand(2,897,3);ack();
 // 逐次产生真实统计包和ACK，覆盖两侧限幅，不强制内部寄存器。
 expected=897;wanted=3;
 while(expected<1991)begin
  settling();delta=expected/16;if(delta<1)delta=1;
  expected=expected+delta;if(expected>1991)expected=1991;
  wanted=wanted+1;demand(1,expected,wanted);ack();
 end
 settling();for(i=0;i<20;i=i+1)packet(1);quiet(wanted);
 while(expected>128)begin
  settling();delta=expected/16;if(delta<1)delta=1;
  expected=expected-delta;if(expected<128)expected=128;
  wanted=wanted+1;demand(2,expected,wanted);ack();
 end
 settling();for(i=0;i<20;i=i+1)packet(2);quiet(wanted);
 // 冻结消费统计但不调整；恢复时仍要求三个新包和两个同向包。
 freeze=1;cycles(1);
 if(exposure_valid || applied_e!=128)$fatal(1,"冻结时生效E状态错误");
 for(i=0;i<20;i=i+1)packet(1);quiet(wanted);
 freeze=0;cycles(5);quiet(wanted);settling();quiet(wanted);
 wanted=wanted+1;demand(1,136,wanted);
 // 模式在忙状态改变，只能等待旧组完成，再提交E900/G12。
 auto_en=0;packet(2);cycles(8);
 if(ae!=136 || ag!=128 || valid || applied_e!=128)$fatal(1,"忙中切模式改变在途参数");
 done=0;cycles(5);done=1;cycles(12);wanted=wanted+1;quiet(wanted);
 if(ae!=900 || ag!=128 || auto_applied!==1 || applied_e!=136 || exposure_valid)
  $fatal(1,"关闭AE后的固定组未正确排队");
 ack();if(auto_applied || applied_e!=900)$fatal(1,"固定E900确认失败");
 for(i=0;i<20;i=i+1)packet(2);quiet(wanted);
 if(ae!=900 || ag!=128 || !exposure_valid)$fatal(1,"关闭AE后仍自主改变参数");
 // 冻结时允许模式归一化，但不会将冻结场景交给补亮统计。
 auto_en=1;freeze=1;cycles(8);wanted=wanted+1;quiet(wanted);
 if(ae!=900 || ag!=128 || auto_applied)$fatal(1,"冻结时自动模式初始化失败");
 ack();if(!auto_applied || exposure_valid)$fatal(1,"冻结模式确认状态错误");
 freeze=0;cycles(4);settling();wanted=wanted+1;demand(1,956,wanted);
 // 摄像头配置无效时，即使done恢复为高也不能确认生效。
 done=0;cfg=0;for(i=0;i<40;i=i+1)packet(1);quiet(wanted);
 done=1;cycles(10);
 if(valid || !pending || exposure_valid || applied_e!=900)
  $fatal(1,"无摄像头配置时误认生效");
 cfg=1;cycles(6);
 if(!valid || pending || !exposure_valid || applied_e!=956)
  $fatal(1,"合法恢复后未发布生效E");
 quiet(wanted);
 cfg=0;#1;
 if(exposure_valid || !pending || applied_e!=956)$fatal(1,"配置丢失未屏蔽生效E有效位");
 cfg=1;cycles(4);quiet(wanted);
 $display("PASS 融合曝光：%0d次真实请求；握手、请求/生效隔离、范围步进、固定G12、冻结和模式切换",requests);
 $finish;
end
initial begin #1000000;$fatal(1,"曝光控制器超时");end
endmodule
'''

KEY_BENCH = r'''
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,key_n=0;wire enable;
integer changes=0;reg old=1;
ae_key_toggle #(.DEBOUNCE_CYCLES(5)) dut(.I_clk(clk),.I_rst_n(rst_n),.I_key_n(key_n),.O_enable(enable));
always @(negedge clk)if(rst_n)begin if(enable!=old)changes=changes+1;old=enable;end
task cycles;input integer n;begin repeat(n)@(negedge clk);#1;end endtask
initial begin
 cycles(4);if(enable!==1)$fatal(1,"默认AE必须开启");
 rst_n=1;cycles(100);if(enable!==1 || changes!=0)$fatal(1,"上电长按误触发");
 key_n=1;cycles(20);
 repeat(8)begin key_n=0;cycles(2);key_n=1;cycles(2);end
 cycles(20);if(changes!=0)$fatal(1,"按键抖动误触发");
 key_n=0;cycles(30);if(enable!==0 || changes!=1)$fatal(1,"首次按下未切换");
 cycles(200);if(changes!=1)$fatal(1,"长按重复触发");
 key_n=1;cycles(2);key_n=0;cycles(30);if(changes!=1)$fatal(1,"释放抖动误触发");
 key_n=1;cycles(20);key_n=0;cycles(20);
 if(enable!==1 || changes!=2)$fatal(1,"第二次按下未切换");
 $display("PASS KEY4：默认开启、上电长按抑制、按下/释放去抖和单次触发");$finish;
end
initial begin #100000;$fatal(1,"按键验证超时");end
endmodule
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path,
                        default=Path('validation/fusion_exposure_linked/control'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    hdl = root / 'user_source/hdl_source'
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    iv = Path(shutil.which('iverilog') or
              'C:/Users/lenovo/AppData/Local/iverilog/bin/iverilog.exe')
    vvp = Path(shutil.which('vvp') or iv.with_name('vvp.exe'))
    source = (hdl / 'fusion_exposure_control.v').read_text(encoding='utf-8')
    assert 'I_protect_en' not in source and 'O_protect_applied' not in source
    cases = []
    for name, bench_source, rtl in [
            ('control', CONTROL_BENCH, 'fusion_exposure_control.v'),
            ('key', KEY_BENCH, 'ae_key_toggle.v')]:
        bench = out / (name + '_tb.v')
        bench.write_text(bench_source, encoding='utf-8')
        binary = out / (name + '.vvp')
        compiled = subprocess.run(
            [str(iv), '-g2012', '-s', 'tb', '-o', binary.name,
             bench.name, str(hdl / rtl)], cwd=out,
            capture_output=True, encoding='utf-8', errors='replace', timeout=60)
        log = compiled.stdout + compiled.stderr
        (out / (name + '.log')).write_text(log, encoding='utf-8')
        if compiled.returncode:
            raise AssertionError(log)
        run = subprocess.run([str(vvp), binary.name], cwd=out, capture_output=True,
                             encoding='utf-8', errors='replace', timeout=60)
        log += run.stdout + run.stderr
        (out / (name + '.log')).write_text(log, encoding='utf-8')
        if run.returncode or 'PASS ' not in run.stdout:
            raise AssertionError(log)
        cases.append(dict(name=name, passed=True, result=run.stdout.strip()))
        print(run.stdout.strip(), flush=True)
    hashes = {str((hdl / name).relative_to(root)):
              hashlib.sha256((hdl / name).read_bytes()).hexdigest()
              for name in ('fusion_exposure_control.v', 'ae_key_toggle.v')}
    (out / 'summary.json').write_text(
        json.dumps(dict(passed=True, td_run=False, source_sha256=hashes,
                        cases=cases), ensure_ascii=False, indent=2) + '\n',
        encoding='utf-8')


if __name__ == '__main__':
    main()
