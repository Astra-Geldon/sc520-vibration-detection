`timescale 1ns/1ps
// Complete raster, not an active-only substitute. Checks all HS/VS/DE/meta
// clocks, full active pixel counts, protected borders and per-pixel Y8.
module tb_chroma_stream;
    localparam HT=1650,VT=750,W=1280,H=720,NF=4,LAT=HT+8;
    localparam FRAME=HT*VT, RUN=NF*FRAME,TOKEN_HISTORY=2*HT+5;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg hs=0,vs=0,de=0,protect=0;
    reg [23:0] rgb=0;
    reg [19:0] meta=0;
    wire ohs,ovs,ode;
    wire [23:0] orgb;
    wire [19:0] ometa;
    chroma_denoise_stream #(.H_TOTAL(HT)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_hs(hs),.I_vs(vs),.I_de(de),
        .I_data(rgb),.I_protect(protect),.I_meta(meta),
        .O_hs(ohs),.O_vs(ovs),.O_de(ode),.O_data(orgb),.O_meta(ometa));
    reg [46:0] history[0:LAT];
    reg history_bypass[0:LAT];
    reg [49:0] token_history[0:TOKEN_HISTORY-1];
    integer frame_count[0:NF-1],modified[0:NF-1];
    integer cycle,x,y,f,i,expected_index,checked=0,pixels=0,bypassed=0;
    integer r,g,b,jitter,yr,yo,idx,tap,offset,token_checks=0;
    reg [46:0] expected;
    // A raw line-delay test, independently proves exactly HT samples per
    // downstream sampling edge, including the initial uninitialized fill.
    reg [49:0] line_input=0;
    wire [49:0] line_output;
    chroma_denoise_line #(.H_TOTAL(HT)) line_dut
        (.clk(clk),.rst_n(rst_n),.din(line_input),.dout(line_output));
    initial begin
        for(i=0;i<NF;i=i+1) begin frame_count[i]=0; modified[i]=0; end
        repeat(3) @(negedge clk);
        rst_n=1;
        for(cycle=0;cycle<RUN+LAT;cycle=cycle+1) begin
            f=cycle/FRAME;y=(cycle%FRAME)/HT;x=cycle%HT;
            de=cycle<RUN && x<W && y<H;
            hs=x>=1390 && x<1430;vs=y>=725 && y<730;
            // Move a color patch in each frame and change bright edges/noise
            // every clock; a stale previous frame cannot satisfy the oracle.
            jitter=((x*13+y*7+f*3) ^ (x/3+y/2))%13-6;
            if(x>=150+f*35 && x<370+f*35 && y>=170 && y<410) begin
                r=165+jitter;g=105-jitter/2;b=72+jitter;
            end else if(x>=900 && x<1040) begin
                r=255;g=240+jitter;b=220+jitter;
            end else begin
                r=105+jitter;g=116-jitter/2;b=133+jitter;
            end
            rgb={r[7:0],g[7:0],b[7:0]};
            protect=(x>=900 && x<1040) || ((x+y+f)%29==0);
            // Mode and threshold metadata deliberately vary by row; adjacent
            // incompatible contexts must not be blended.
            meta={3'd0,2'd3,f[2:0],2'd1,8'd100,1'b0,1'b1};
            if(y>=300 && y<330) meta[9:2]=8'd120;
            idx=cycle%(LAT+1);
            history[idx]={meta,hs,vs,de,de?rgb:24'd0};
            history_bypass[idx]=protect || f==0 || x==0 || x==W-1 || y==0 || y==H-1;
            yr=(77*r+150*g+29*b+128)/256;
            // Blanking is explicitly zeroed before the color conversion.
            if(!de) begin yr=0;r=0;g=0;b=0;end
            token_history[cycle%TOKEN_HISTORY]={meta,hs,vs,de,protect,yr[7:0],9'(r-g),9'(b-g)};
            line_input=cycle+1;
            // Inspect the actual 3x3 input immediately BEFORE its sampling
            // edge. This proves each tap has the intended x/y coordinate,
            // rather than merely proving the center brightness afterwards.
            if(cycle>=TOKEN_HISTORY && cycle%97==0) begin
                for(tap=0;tap<9;tap=tap+1) begin
                    offset=2+(2-tap/3)*HT+(2-tap%3);
                    if(dut.S_window[tap*50+:50] !== token_history[(cycle-offset)%TOKEN_HISTORY])
                        $fatal(1,"3x3 tap alignment mismatch cycle=%0d tap=%0d",cycle,tap);
                    token_checks=token_checks+1;
                end
            end
            @(posedge clk); #1;
            if(cycle>=HT-1 && line_output !== cycle-HT+2)
                $fatal(1,"Line stride mismatch at cycle %0d got=%0d wanted=%0d",cycle,line_output,cycle-HT+2);
            if(cycle<HT-1 && line_output !== 0)
                $fatal(1,"Unfilled RAM was not masked");
            if(cycle>=LAT) begin
                expected_index=(cycle-LAT)%(LAT+1);
                expected=history[expected_index];
                if({ometa,ohs,ovs,ode} !== expected[46:24])
                    $fatal(1,"Control/meta alignment mismatch cycle=%0d out=%h wanted=%h",cycle,{ometa,ohs,ovs,ode},expected[46:24]);
                if(ode) begin
                    checked=checked+1;
                    yr=(77*expected[23:16]+150*expected[15:8]+29*expected[7:0]+128)/256;
                    yo=(77*orgb[23:16]+150*orgb[15:8]+29*orgb[7:0]+128)/256;
                    if(yr !== yo) $fatal(1,"Brightness mismatch cycle=%0d RGB=%h -> %h Y=%0d -> %0d",cycle,expected[23:0],orgb,yr,yo);
                    if(history_bypass[expected_index]) begin
                        bypassed=bypassed+1;
                        if(orgb !== expected[23:0]) $fatal(1,"D0/protected/border RGB changed cycle=%0d",cycle);
                    end
                    f=(cycle-LAT)/FRAME;
                    frame_count[f]=frame_count[f]+1;
                    if(orgb !== expected[23:0]) modified[f]=modified[f]+1;
                end else if(orgb !== 0) $fatal(1,"Nonblack blanking cycle=%0d",cycle);
                pixels=pixels+ode;
            end
            @(negedge clk);
        end
        for(f=0;f<NF;f=f+1) begin
            if(frame_count[f] != W*H) $fatal(1,"Missing/extra active pixels frame%0d count=%0d",f,frame_count[f]);
            if(f>0 && modified[f]==0) $fatal(1,"D%0d never filtered",f);
            $display("PASS chroma_stream frame D%0d: pixels=%0d modified=%0d Y8/errors=0",f,frame_count[f],modified[f]);
        end
        $display("PASS chroma_stream: %0d full720p pixels, %0d bypass checks; all HS/VS/DE/meta aligned; latency=%0d",checked,bypassed,LAT);
        $display("PASS chroma_taps: %0d exact 3x3 coordinates across frame/line borders",token_checks);
        $finish;
    end
endmodule
