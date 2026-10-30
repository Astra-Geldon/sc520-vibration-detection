// Fixed-luma, same-frame chroma denoise AFTER C3 and BEFORE OSD.
// Two raster-line ERAM delays, no DDR traffic or previous-frame history.
// Token layout: meta[49:30], HS/VS/DE[29:27], protect[26],
//              Y8[25:18], signed(R-G)[17:9], signed(B-G)[8:0].
module chroma_denoise_stream #(
    parameter integer H_TOTAL = 1650
)(
    input wire I_clk, I_rst_n,
    input wire I_hs, I_vs, I_de,
    input wire [23:0] I_data,
    input wire I_protect,
    // {mode[2:0], exposure[1:0], D[2:0], k[1:0], threshold[7:0], raw, locked}
    input wire [19:0] I_meta,
    output wire O_hs, O_vs, O_de,
    output wire [23:0] O_data,
    output wire [19:0] O_meta
);
    // Keep C3's multiplier separate from the new color conversion.
    reg [23:0] S_rgb;
    reg [23:0] S_flags;
    wire [7:0] S_r = S_rgb[23:16], S_g = S_rgb[15:8], S_b = S_rgb[7:0];
    wire [15:0] S_r16 = {8'd0,S_r}, S_g16 = {8'd0,S_g}, S_b16 = {8'd0,S_b};
    // Constant products use shifts/adds; no new variable multiplier.
    wire [15:0] S_y_sum = (S_r16<<6)+(S_r16<<3)+(S_r16<<2)+S_r16 +
                         (S_g16<<7)+(S_g16<<4)+(S_g16<<2)+(S_g16<<1) +
                         (S_b16<<5)-(S_b16<<1)-S_b16+16'd128;
    wire signed [8:0] S_dr = $signed({1'b0,S_r})-$signed({1'b0,S_g});
    wire signed [8:0] S_db = $signed({1'b0,S_b})-$signed({1'b0,S_g});
    reg [49:0] S_token;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin S_rgb<=0; S_flags<=0; S_token<=0; end
        else begin
            S_rgb <= I_de ? I_data : 24'd0;
            S_flags <= {I_meta,I_hs,I_vs,I_de,I_protect};
            S_token <= {S_flags,S_y_sum[15:8],S_dr,S_db};
        end
    end
    wire [49:0] S_row1, S_row2;
    chroma_denoise_line #(.H_TOTAL(H_TOTAL)) u_line1
        (.clk(I_clk),.rst_n(I_rst_n),.din(S_token),.dout(S_row1));
    chroma_denoise_line #(.H_TOTAL(H_TOTAL)) u_line2
        (.clk(I_clk),.rst_n(I_rst_n),.din(S_row1),.dout(S_row2));
    reg [49:0] S_h00,S_h01,S_h10,S_h11,S_h20,S_h21;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_h00<=0;S_h01<=0;S_h10<=0;S_h11<=0;S_h20<=0;S_h21<=0;
        end else begin
            S_h00<=S_h01; S_h01<=S_token;
            S_h10<=S_h11; S_h11<=S_row1;
            S_h20<=S_h21; S_h21<=S_row2;
        end
    end
    wire [449:0] S_window = {S_token,S_h01,S_h00,S_row1,S_h11,S_h10,S_row2,S_h21,S_h20};
    chroma_denoise_core u_core
        (.clk(I_clk),.rst_n(I_rst_n),.window_tokens(S_window),
         .O_hs(O_hs),.O_vs(O_vs),.O_de(O_de),.O_data(O_data),.O_meta(O_meta));
endmodule

// Port B reads the NEXT address, one clock before port A overwrites it.
// Read/write addresses differ, avoiding cross-port read-during-write ambiguity.
// The synchronous NOREG RAM output itself provides the read clock; do not
// insert another output register or the raster stride would become H_TOTAL+1.
module chroma_denoise_line #(
    parameter integer H_TOTAL=1650
)(input wire clk,rst_n,input wire [49:0] din,output wire [49:0] dout);
    reg [10:0] S_addr;
    reg [11:0] S_fill;
    wire [10:0] S_next = (S_addr==H_TOTAL-1) ? 11'd0 : S_addr+11'd1;
    wire [49:0] S_q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin S_addr<=0;S_fill<=0;end
        else begin
            S_addr<=S_next;
            if(S_fill<H_TOTAL) S_fill<=S_fill+1'b1;
        end
    end
    assign dout=(S_fill>=H_TOTAL) ? S_q : 50'd0;
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A(50),.DATA_WIDTH_B(50),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.MODE("DP"),
        .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
        .IMPLEMENT("20K(FAST)"),.ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
        .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
        .OREGSET_A("RESET"),.OREGSET_B("RESET"),
        .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
        .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC"),
        .INIT_FILE("NONE"),.FILL_ALL("NONE")
    ) u_ram (
        .dia(din),.dib(50'd0),.addra(S_addr),.addrb(S_next),
        .cea(1'b1),.ceb(1'b1),.ocea(1'b0),.oceb(1'b0),
        .clka(clk),.clkb(clk),.wea(1'b1),.web(1'b0),.bea(1'b0),.beb(1'b0),
        .rsta(~rst_n),.rstb(~rst_n),.doa(),.dob(S_q),
        .ecc_sbiterr(),.ecc_dbiterr(),.ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0)
    );
endmodule

module chroma_denoise_core(
    input wire clk,rst_n,
    input wire [449:0] window_tokens,
    output reg O_hs,O_vs,O_de,
    output reg [23:0] O_data,
    output reg [19:0] O_meta
);
    wire [49:0] C=window_tokens[200+:50];
    wire [2:0] D=C[44:42];
    wire [7:0] YT=(D==1)?8'd8:(D==2)?8'd12:8'd16;
    wire [9:0] CT=(D==1)?10'd12:(D==2)?10'd16:10'd24;
    function signed [15:0] f_weight;
        input signed [8:0] dr,db;
        reg signed [15:0] r,b;
        begin
            r={{7{dr[8]}},dr}; b={{7{db[8]}},db};
            f_weight=(r<<<6)+(r<<<3)+(r<<<2)+r+(b<<<5)-(b<<<1)-b+16'sd128;
        end
    endfunction
    function [23:0] f_original;
        input [49:0] word;
        reg signed [8:0] dr,db;
        reg signed [15:0] n;
        reg signed [9:0] g;
        reg signed [10:0] r,b;
        begin
            dr=word[17:9];db=word[8:0]; n=f_weight(dr,db);
            g=$signed({2'b00,word[25:18]})-(n>>>8);
            r={{1{g[9]}},g}+{{2{dr[8]}},dr};
            b={{1{g[9]}},g}+{{2{db[8]}},db};
            f_original={r[7:0],g[7:0],b[7:0]};
        end
    endfunction
    function signed [8:0] f_choose;
        input [49:0] n,c;
        input [7:0] yt;
        input [9:0] ct;
        input channel_b;
        reg signed [8:0] dy;
        reg signed [9:0] dr,db;
        reg [8:0] ay;
        reg [9:0] ar,ab;
        begin
            dy=$signed({1'b0,n[25:18]})-$signed({1'b0,c[25:18]});
            dr=$signed({n[17],n[17:9]})-$signed({c[17],c[17:9]});
            db=$signed({n[8],n[8:0]})-$signed({c[8],c[8:0]});
            ay=dy[8] ? -dy:dy; ar=dr[9] ? -dr:dr; ab=db[9] ? -db:db;
            f_choose=channel_b ? c[8:0]:c[17:9];
            if(n[27] && !n[26] && (n[49:30]==c[49:30]) && ay<=yt && ar<=ct && ab<=ct)
                f_choose=channel_b ? n[8:0]:n[17:9];
        end
    endfunction
    wire signed [12:0] R[0:8],B[0:8];
    wire [8:0] V;
    genvar i;
    generate for(i=0;i<9;i=i+1) begin:g_tap
        wire [49:0] N=window_tokens[i*50+:50];
        wire signed [8:0] r=f_choose(N,C,YT,CT,1'b0);
        wire signed [8:0] b=f_choose(N,C,YT,CT,1'b1);
        wire signed [12:0] rr={{4{r[8]}},r},bb={{4{b[8]}},b};
        localparam integer SH=(i==4)?2:((i==1)||(i==3)||(i==5)||(i==7))?1:0;
        assign R[i]=rr<<<SH; assign B[i]=bb<<<SH;assign V[i]=N[27];
    end endgenerate
    function signed [8:0] f_blend;
        input signed [8:0] average,original;
        input [2:0] mode;
        reg signed [11:0] diff,mixed,limit;
        begin
            diff=$signed({{3{average[8]}},average})-$signed({{3{original[8]}},original});
            case(mode)
                1:begin mixed=(diff+12'sd2)>>>2;limit=2;end
                2:begin mixed=((diff<<<1)+12'sd2)>>>2;limit=4;end
                3:begin mixed=((diff<<<1)+diff+12'sd2)>>>2;limit=6;end
                default:begin mixed=0;limit=0;end
            endcase
            if(mixed>limit)mixed=limit;
            if(mixed < -limit)mixed=-limit;
            f_blend=$signed({{3{original[8]}},original})+mixed;
        end
    endfunction
    reg signed [12:0] rr0,rr1,rr2,bb0,bb1,bb2;
    reg signed [8:0] ar1,ab1,dr2,db2;
    reg signed [15:0] num3;
    reg signed [8:0] dr3,db3;
    reg signed [10:0] r4,g4,b4;
    reg [49:0] t0,t1,t2,t3,t4;
    wire signed [15:0] S_k3=num3>>>8;
    wire signed [15:0] S_g3=$signed({8'd0,t3[25:18]})-S_k3;
    reg [23:0] orig0,orig1,orig2,orig3,orig4;
    reg bypass0,bypass1,bypass2,bypass3,bypass4;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            rr0<=0;rr1<=0;rr2<=0;bb0<=0;bb1<=0;bb2<=0;
            ar1<=0;ab1<=0;dr2<=0;db2<=0;dr3<=0;db3<=0;num3<=0;
            r4<=0;g4<=0;b4<=0;t0<=0;t1<=0;t2<=0;t3<=0;t4<=0;
            orig0<=0;orig1<=0;orig2<=0;orig3<=0;orig4<=0;
            bypass0<=1;bypass1<=1;bypass2<=1;bypass3<=1;bypass4<=1;
            O_hs<=0;O_vs<=0;O_de<=0;O_data<=0;O_meta<=0;
        end else begin
            rr0<=R[0]+R[1]+R[2];rr1<=R[3]+R[4]+R[5];rr2<=R[6]+R[7]+R[8];
            bb0<=B[0]+B[1]+B[2];bb1<=B[3]+B[4]+B[5];bb2<=B[6]+B[7]+B[8];
            t0<=C;orig0<=f_original(C);bypass0<=C[26]||!(&V)||(D==0)||(D>3);
            ar1<=(rr0+rr1+rr2+13'sd8)>>>4;ab1<=(bb0+bb1+bb2+13'sd8)>>>4;
            t1<=t0;orig1<=orig0;bypass1<=bypass0;
            dr2<=f_blend(ar1,$signed(t1[17:9]),t1[44:42]);
            db2<=f_blend(ab1,$signed(t1[8:0]),t1[44:42]);
            t2<=t1;orig2<=orig1;bypass2<=bypass1;
            num3<=f_weight(dr2,db2);dr3<=dr2;db3<=db2;
            t3<=t2;orig3<=orig2;bypass3<=bypass2;
            g4<=S_g3;r4<=S_g3+$signed({{7{dr3[8]}},dr3});b4<=S_g3+$signed({{7{db3[8]}},db3});
            t4<=t3;orig4<=orig3;bypass4<=bypass3;
            O_hs<=t4[29];O_vs<=t4[28];O_de<=t4[27];O_meta<=t4[49:30];
            if(!t4[27])O_data<=24'd0;
            else if(bypass4||r4<0||r4>255||g4<0||g4>255||b4<0||b4>255)O_data<=orig4;
            else O_data<={r4[7:0],g4[7:0],b4[7:0]};
        end
    end
endmodule
