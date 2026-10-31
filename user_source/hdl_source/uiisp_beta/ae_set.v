/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/
// Fixed production exposure/gain selected from the accepted N1 comparison.
// Keep one startup request after camera initialization: the factory mode table
// has different defaults, so constants alone must not bypass this grouped write.
module ae_set (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_ae_cfg_done,
    input  wire        I_cam_cfg_done,
    output reg         O_ae_req = 1'b0,
    output reg [15:0]  O_ae,
    output reg [15:0]  O_ag
);
    localparam [15:0] FIXED_EXPOSURE = 16'd900;
    localparam [15:0] FIXED_GAIN = 16'd128; // 8x analog * 1.5x digital = 12x

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            O_ae_req <= 1'b0;
            // Preserve the previous startup handshake and output values.
            O_ae <= 16'd1990;
            O_ag <= 16'd17;
        end else if (O_ae_req) begin
            O_ae_req <= 1'b0;
        end else if (((O_ae != FIXED_EXPOSURE) || (O_ag != FIXED_GAIN)) &&
                     I_cam_cfg_done && I_ae_cfg_done) begin
            O_ae <= FIXED_EXPOSURE;
            O_ag <= FIXED_GAIN;
            O_ae_req <= 1'b1;
        end
    end
endmodule
