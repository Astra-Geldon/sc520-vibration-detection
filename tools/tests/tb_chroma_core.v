`timescale 1ns/1ps
module tb_chroma_core;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg [449:0] tokens=0;
    wire hs,vs,de;
    wire [23:0] rgb;
    wire [19:0] meta;
    chroma_denoise_core dut(.clk(clk),.rst_n(rst_n),.window_tokens(tokens),
        .O_hs(hs),.O_vs(vs),.O_de(de),.O_data(rgb),.O_meta(meta));
    integer in_file,out_file,rc,cycle,count;
    reg [449:0] vector;
    reg [46:0] expected;
    reg [1023:0] vectors_path,expected_path;
    initial begin
        if(!$value$plusargs("vectors=%s",vectors_path) ||
           !$value$plusargs("expected=%s",expected_path) ||
           !$value$plusargs("count=%d",count)) $fatal(1,"Missing vector args");
        in_file=$fopen(vectors_path,"r");out_file=$fopen(expected_path,"r");
        if(!in_file || !out_file) $fatal(1,"Cannot open numeric oracle vectors");
        repeat(3) @(negedge clk);
        rst_n=1;
        for(cycle=0;cycle<count+5;cycle=cycle+1) begin
            if(cycle<count) begin
                rc=$fscanf(in_file,"%h\n",vector);
                if(rc!=1) $fatal(1,"Missing input vector %0d",cycle);
                tokens=vector;
            end else tokens=0;
            @(posedge clk); #1;
            if(cycle>=5) begin
                rc=$fscanf(out_file,"%h\n",expected);
                if(rc!=1) $fatal(1,"Missing expected vector");
                if({meta,hs,vs,de,rgb} !== expected)
                    $fatal(1,"Core mismatch vector=%0d got=%h expected=%h",cycle-5,{meta,hs,vs,de,rgb},expected);
            end
            @(negedge clk);
        end
        $display("PASS chroma_core: %0d independent Python integer-oracle windows; latency=5 cycles",count);
        $finish;
    end
endmodule
