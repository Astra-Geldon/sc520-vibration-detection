// Verification-only synchronous dual-port RAM model. The encrypted vendor
// model cannot be loaded by Icarus. NOREG means the RAM read clock is retained
// but there is no additional output pipeline register. There is deliberately
// no memory reset/initialization: production must mask its fill interval.
module PH1P_LOGIC_ERAM #(
    parameter DATA_WIDTH_A=50, DATA_WIDTH_B=50, ADDR_WIDTH_A=11, ADDR_WIDTH_B=11,
    parameter DATA_DEPTH_A=2048, DATA_DEPTH_B=2048,
    parameter MODE="DP", REGMODE_A="NOREG", REGMODE_B="NOREG",
    parameter WRITEMODE_A="NORMAL", WRITEMODE_B="NORMAL", IMPLEMENT="20K(FAST)",
    parameter ECC_ENCODE="DISABLE", ECC_DECODE="DISABLE", CLKMODE="ASYNC",
    parameter SSROVERCE="DISABLE", OREGSET_A="RESET", OREGSET_B="RESET",
    parameter RESETMODE_A="ASYNC", RESETMODE_B="ASYNC",
    parameter ASYNC_RESET_RELEASE_A="ASYNC", ASYNC_RESET_RELEASE_B="ASYNC",
    parameter INIT_FILE="NONE", FILL_ALL="NONE"
)(
    input [DATA_WIDTH_A-1:0] dia, input [DATA_WIDTH_B-1:0] dib,
    input [ADDR_WIDTH_A-1:0] addra, input [ADDR_WIDTH_B-1:0] addrb,
    input cea,ceb,ocea,oceb,clka,clkb,wea,web,bea,beb,rsta,rstb,
    input ecc_sbiterrinj,ecc_dbiterrinj,
    output reg [DATA_WIDTH_A-1:0] doa,
    output reg [DATA_WIDTH_B-1:0] dob,
    output ecc_sbiterr,ecc_dbiterr
);
    reg [DATA_WIDTH_A-1:0] memory[0:DATA_DEPTH_A-1];
    assign ecc_sbiterr=0;
    assign ecc_dbiterr=0;
    initial begin
        if(DATA_WIDTH_A != DATA_WIDTH_B || ADDR_WIDTH_A != ADDR_WIDTH_B ||
           REGMODE_B != "NOREG" || MODE != "DP")
            $fatal(1,"Unsupported verification RAM configuration");
    end
    always @(posedge clka) begin
        if(cea && wea && !rsta) memory[addra] <= dia;
    end
    always @(posedge clkb or posedge rstb) begin
        if(rstb) dob <= 0;
        else if(ceb) begin
            if(web) $fatal(1,"Test model port B must remain read-only");
            if(wea && cea && addra == addrb)
                $fatal(1,"Production RAM read/write address collision");
            dob <= memory[addrb];
        end
    end
endmodule
