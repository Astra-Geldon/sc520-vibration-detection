"""Check runtime ISP switches against the accepted f86bc17 RTL.

Runs real bilinear interpolation in all four Bayer formats, real AWB with its
unchanged signal_delay controller (using a synchronous dual-port RAM model),
and the real registered Gamma stage. Build artifacts stay outside the repo.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path(
        'D:/FPGA/codex/_build/20261029project/six-switch-demo-20261101/isp-tests'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    hdl = root / 'user_source/hdl_source'
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    compiler = Path('D:/FPGA/codex/slice_budget_20261026/tooling/iverilog/app/bin/iverilog.exe')
    baseline = 'f86bc17'
    owned = ['isp/isp_top.v', 'awb.v', 'isp/demosaic_4x_2_0/demosaic.v',
             'isp/demosaic_4x_2_0/bilinear_interpolation.v']
    report = {'pass': False, 'reference_commit': baseline,
              'source_sha256': {n: hashlib.sha256((hdl/n).read_bytes()).hexdigest() for n in owned},
              'ram_scope': 'Synchronous read-before-write dual-port behavioural model; '
                           'unchanged real signal_delay RTL, not vendor silicon timing',
              'checks': {}}

    def archive(name, module, dest):
        blob = subprocess.check_output(['git', 'show', baseline + ':user_source/hdl_source/' + name], cwd=root)
        blob, count = re.subn(rb'\bmodule\s+' + module.encode() + rb'\b',
                              b'module legacy_' + module.encode(), blob, count=1)
        assert count == 1
        path = out/dest
        path.write_bytes(blob)
        return path

    def run(name, bench, dependencies):
        folder = out/name
        folder.mkdir(exist_ok=True)
        tb, binary = folder/'tb.v', folder/'tb.vvp'
        tb.write_text(bench, encoding='utf-8', newline='\n')
        built = subprocess.run([str(compiler), '-g2012', '-s', 'tb', '-o', str(binary), str(tb)]
                               + [str(p) for p in dependencies], cwd=root, capture_output=True,
                               text=True, errors='replace', timeout=60)
        (folder/'compile.log').write_text(built.stdout + built.stderr, encoding='utf-8')
        assert built.returncode == 0, name + '\n' + built.stdout + built.stderr
        simulated = subprocess.run([str(compiler.with_name('vvp.exe')), '-i', str(binary)],
                                   cwd=root, capture_output=True, text=True, errors='replace', timeout=120)
        (folder/'simulation.log').write_text(simulated.stdout + simulated.stderr, encoding='utf-8')
        print(simulated.stdout, end='', flush=True)
        assert simulated.returncode == 0 and 'PASS ' in simulated.stdout, name + '\n' + simulated.stdout + simulated.stderr
        report['checks'][name] = {'pass': True, 'result': simulated.stdout.strip()}

    try:
        old_bilinear = archive(owned[3], 'bilinear_interpolation', 'legacy_bilinear.v')
        old_awb = archive('awb.v', 'awb', 'legacy_awb.v')
        old_isp = subprocess.check_output(['git', 'show', baseline + ':user_source/hdl_source/isp/isp_top.v'], cwd=root)
        gamma = old_isp[old_isp.index(b'module axis_gamma_rgb96 ('):]
        gamma = gamma[:gamma.index(b'endmodule') + len(b'endmodule')]
        old_gamma = out/'legacy_gamma.v'
        old_gamma.write_bytes(gamma.replace(b'module axis_gamma_rgb96 (', b'module legacy_axis_gamma_rgb96 (', 1))

        run('bilinear_raw', r'''
`timescale 1ns/1ps
module tb;
reg clk=0; always #5 clk=~clk;
reg rst=0, valid=0, last=0, user=0, ypos=0;
reg [95:0] prev_line=0, cur_line=0, next_line=0;
wire [127:0] actual[0:3], reference[0:3], raw_gray;
wire [3:0] ov,ol,ou,rv,rl,ru;
wire raw_valid,raw_last,raw_user;
integer n,p,k,valid_words=0,cycle_checks=0;
reg [127:0] expected[0:4]; reg [4:0] ev=0,el=0,eu=0;
reg [127:0] grey_input;
genvar m;
generate for(m=0;m<4;m=m+1)begin:formats
 localparam FORMAT=(m==0)?"BGGR":(m==1)?"RGGB":(m==2)?"GBRG":"GRBG";
 bilinear_interpolation #(.BAYER_MODE(FORMAT)) dut(
  .I_clk(clk),.I_rst_n(rst),.I_enable(1'b1),.I_tvalid(valid),.I_tlast(last),.I_tuser(user),.I_tready(),
  .bayer_ypos(ypos),.matrix_last_line(prev_line),.matrix_cur_line(cur_line),.matrix_next_line(next_line),
  .O_tdata(actual[m]),.O_tvalid(ov[m]),.O_tlast(ol[m]),.O_tuser(ou[m]),.O_tready(1'b1));
 legacy_bilinear_interpolation #(.BAYER_MODE(FORMAT)) old(
  .I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tlast(last),.I_tuser(user),.I_tready(),
  .bayer_ypos(ypos),.matrix_last_line(prev_line),.matrix_cur_line(cur_line),.matrix_next_line(next_line),
  .O_tdata(reference[m]),.O_tvalid(rv[m]),.O_tlast(rl[m]),.O_tuser(ru[m]),.O_tready(1'b1));
end endgenerate
bilinear_interpolation raw_dut(
 .I_clk(clk),.I_rst_n(rst),.I_enable(1'b0),.I_tvalid(valid),.I_tlast(last),.I_tuser(user),.I_tready(),
 .bayer_ypos(ypos),.matrix_last_line(prev_line),.matrix_cur_line(cur_line),.matrix_next_line(next_line),
 .O_tdata(raw_gray),.O_tvalid(raw_valid),.O_tlast(raw_last),.O_tuser(raw_user),.O_tready(1'b1));
always @(posedge clk)begin
 if(!rst)begin
  ev=0;el=0;eu=0;for(k=0;k<5;k=k+1)expected[k]=0;
 end else begin
  grey_input=0;
  // Independently pick the four matrix centres in left-to-right order.
  for(p=0;p<4;p=p+1)grey_input[p*32+:32]={8'd0,{3{cur_line[56-p*8+:8]}}};
  for(k=4;k>0;k=k-1)expected[k]=expected[k-1];
  expected[0]=grey_input;
  ev={ev[3:0],valid};el={el[3:0],last};eu={eu[3:0],user};
  #1;
  for(p=0;p<4;p=p+1)begin
   if({actual[p],ov[p],ol[p],ou[p]}!=={reference[p],rv[p],rl[p],ru[p]})
    $fatal(1,"all-on demosaic mismatch Bayer%0d cycle%0d",p,n);
   cycle_checks=cycle_checks+1;
  end
  if({raw_valid,raw_last,raw_user}!=={ev[4],el[4],eu[4]})$fatal(1,"raw sync mismatch cycle%0d",n);
  if(raw_valid)begin
   if(raw_gray!==expected[4])$fatal(1,"raw centres mismatch got%h expected%h cycle%0d",raw_gray,expected[4],n);
   valid_words=valid_words+1;
  end
 end
end
initial begin
 repeat(5)@(negedge clk);rst=1;
 for(n=0;n<30000;n=n+1)begin
  @(negedge clk);
  valid=((n%419)<320)&&(n%23!=0);last=(n%419==319);user=(n%6704==0);ypos=(n/419)%2;
  prev_line={$random,$random,$random};cur_line={$random,$random,$random};next_line={$random,$random,$random};
 end
 @(negedge clk);valid=0;last=0;user=0;
 repeat(10)@(negedge clk);
 if(valid_words<20000)$fatal(1,"insufficient raw coverage");
 $display("PASS bilinear all-on_cycle_checks=%0d raw_four_pixel_words=%0d Bayer_formats=4 sync_latency=5",cycle_checks,valid_words);
 $finish;
end
endmodule
''', [hdl/owned[3], old_bilinear])

        run('gamma', r'''
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,valid=0,last=0,user=0;
reg [95:0] data=0;
wire [95:0] actual,reference,bypassed;
wire av,al,au,rv,rl,ru,bv,bl,bu;
integer n,j,checks=0;
axis_gamma_rgb96 dut(.I_clk(clk),.I_rst_n(rst),.I_enable(1'b1),.I_tvalid(valid),.I_tlast(last),.I_tuser(user),
 .I_tdata(data),.O_tdata(actual),.O_tvalid(av),.O_tlast(al),.O_tuser(au));
axis_gamma_rgb96 off(.I_clk(clk),.I_rst_n(rst),.I_enable(1'b0),.I_tvalid(valid),.I_tlast(last),.I_tuser(user),
 .I_tdata(data),.O_tdata(bypassed),.O_tvalid(bv),.O_tlast(bl),.O_tuser(bu));
legacy_axis_gamma_rgb96 old(.I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tlast(last),.I_tuser(user),
 .I_tdata(data),.O_tdata(reference),.O_tvalid(rv),.O_tlast(rl),.O_tuser(ru));
always @(posedge clk)if(rst)begin
 #1;
 if({actual,av,al,au}!=={reference,rv,rl,ru})$fatal(1,"gamma all-on mismatch %0d",n);
 if({bv,bl,bu}!=={valid,last,user})$fatal(1,"gamma bypass sync mismatch");
 if(bypassed!==(valid?data:96'd0))$fatal(1,"gamma bypass data mismatch");
 checks=checks+1;
end
initial begin
 repeat(5)@(negedge clk);rst=1;
 for(n=0;n<4096;n=n+1)begin
  @(negedge clk);valid=(n%19!=0);last=(n%17==0);user=(n%1000==0);
  for(j=0;j<12;j=j+1)data[j*8+:8]=(n+j*17)%256;
 end
 @(negedge clk);valid=0;last=0;user=0;
 repeat(3)@(negedge clk);
 $display("PASS gamma all-on_and_identity_cycles=%0d channel_values=256",checks);$finish;
end
endmodule
''', [hdl/owned[0], old_gamma])

        run('awb', r'''
`timescale 1ns/1ps
module blk_mem_gen_awb_delay_signal(input clka,input wea,input [10:0] addra,input [95:0] dia,
 input clkb,input [10:0] addrb,output reg [95:0] dob);
reg [95:0] mem[0:2047];
always @(posedge clka)if(wea)mem[addra]<=dia;
always @(posedge clkb)dob<=mem[addrb];
endmodule
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,valid=0,last=0,user=0;
reg [95:0] data=0;
wire [95:0] actual,reference,bypassed;
wire av,al,au,rv,rl,ru,bv,bl,bu;
integer f,y,x,j,checks=0,identity_words=0,nonunity=0,wr=0,rd=0;
reg [95:0] queue[0:99999];
awb #(.IMG_HEIGHT(16),.IMG_WIDTH(1280)) dut(.I_clk(clk),.I_rst_n(rst),.I_enable(1'b1),
 .I_tvalid(valid),.I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tready(),
 .O_tdata(actual),.O_tvalid(av),.O_tlast(al),.O_tuser(au),.O_tready(1'b1));
awb #(.IMG_HEIGHT(16),.IMG_WIDTH(1280)) off(.I_clk(clk),.I_rst_n(rst),.I_enable(1'b0),
 .I_tvalid(valid),.I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tready(),
 .O_tdata(bypassed),.O_tvalid(bv),.O_tlast(bl),.O_tuser(bu),.O_tready(1'b1));
legacy_awb #(.IMG_HEIGHT(16),.IMG_WIDTH(1280)) old(.I_clk(clk),.I_rst_n(rst),
 .I_tvalid(valid),.I_tlast(last),.I_tuser(user),.I_tdata(data),.I_tready(),
 .O_tdata(reference),.O_tvalid(rv),.O_tlast(rl),.O_tuser(ru),.O_tready(1'b1));
always @(posedge clk)if(rst)begin
 if(valid)begin queue[wr]=data;wr=wr+1;end
 #1;
 if({actual,av,al,au}!=={reference,rv,rl,ru})$fatal(1,"AWB all-on mismatch frame%0d line%0d",f,y);
 if({bv,bl,bu}!=={av,al,au})$fatal(1,"AWB bypass changed sync");
 if(au!==user)$fatal(1,"AWB early frame reset pulse changed");
 if(bv)begin
  if(rd>=wr)$fatal(1,"AWB unexpected output");
  if(bypassed!==queue[rd])$fatal(1,"AWB unity data mismatch word%0d got%h expected%h",rd,bypassed,queue[rd]);
  rd=rd+1;identity_words=identity_words+1;
  if(actual!==bypassed)nonunity=nonunity+1;
 end
 checks=checks+1;
end
initial begin
 repeat(5)@(negedge clk);rst=1;
 for(f=0;f<12;f=f+1)begin
  @(negedge clk);user=1;valid=0;last=0;
  @(negedge clk);user=0;
  repeat(140)@(negedge clk);
  for(y=0;y<16;y=y+1)begin
   for(x=0;x<320;x=x+1)begin
    @(negedge clk);valid=1;last=(x==319);
    for(j=0;j<4;j=j+1)data[j*24+:24]={8'(40+(x+j+f)%50),8'(100+(x*3+j+y)%60),8'(20+(x*7+j)%50)};
   end
   @(negedge clk);valid=0;last=0;
   repeat(200)@(negedge clk);
  end
 end
 repeat(250)@(negedge clk);
 if(rd!=wr||identity_words!=61440||nonunity<20000)$fatal(1,"AWB coverage wr%0d rd%0d learned%0d",wr,rd,nonunity);
 $display("PASS awb all-on_cycles=%0d identity_four_pixel_words=%0d nonunity_words=%0d early_tuser_preserved=1 delay_RAM_preserved=1",checks,identity_words,nonunity);
 $finish;
end
endmodule
''', [hdl/'awb.v', old_awb, hdl/'signal_delay.v'])

        report['pass'] = True
    finally:
        (out/'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('PASS six-switch ISP checks; ' + str(out/'summary.json'), flush=True)


if __name__ == '__main__':
    main()
