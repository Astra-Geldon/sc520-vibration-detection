module uart_tx_simple #(parameter integer CLK_HZ=50000000, parameter integer BAUD=115200)(input wire clk,input wire rst_n,input wire [7:0] data,input wire valid,output wire ready,output wire tx);
localparam integer DIV=CLK_HZ/BAUD; reg [15:0] cnt; reg [3:0] bitn; reg [9:0] sh; reg busy;
assign ready=~busy; assign tx=busy?sh[0]:1'b1;
always @(posedge clk or negedge rst_n) begin if(!rst_n) begin cnt<=0;bitn<=0;sh<=10'h3ff;busy<=0; end else if(!busy) begin if(valid) begin sh<={1'b1,data,1'b0};cnt<=0;bitn<=0;busy<=1;end end else if(cnt==DIV-1) begin cnt<=0; if(bitn==9) begin busy<=0;sh<=10'h3ff;end else begin bitn<=bitn+1'b1;sh<={1'b1,sh[9:1]};end end else cnt<=cnt+1'b1; end
endmodule
