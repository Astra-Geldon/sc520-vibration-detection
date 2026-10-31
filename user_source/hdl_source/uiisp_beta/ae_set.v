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
// SW5 selects the accepted highlight-protection parameters or the archived
// ee675b6 reference. I_protect_en is already debounced and synchronized here.
// A launch always waits for the real controller's done-low / done-high cycle;
// its initial done-high after initialization is not an applied-parameter ACK.
module ae_set (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_protect_en,
    input  wire        I_ae_cfg_done,
    input  wire        I_cam_cfg_done,
    output reg         O_ae_req = 1'b0,
    output reg [15:0]  O_ae,
    output reg [15:0]  O_ag,
    output reg         O_protect_applied,
    output wire        O_pending,
    output reg         O_valid
);
    localparam [15:0] FIXED_EXPOSURE = 16'd900;
    localparam [15:0] FIXED_GAIN = 16'd128; // 8x analog * 1.5x digital = 12x
    localparam [15:0] REFERENCE_EXPOSURE = 16'd1991;
    localparam [15:0] REFERENCE_GAIN = 16'd160; // archived nominal 24x
    reg in_flight;
    reg saw_busy;
    reg requested_protect;

    // Retain the last completed selection while pending. A failed/unfinished
    // group must never turn the requested switch position into an ON/OFF ACK.
    assign O_pending = in_flight || !O_valid || !I_cam_cfg_done ||
                       (O_protect_applied != I_protect_en);

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            O_ae_req <= 1'b0;
            // Preserve startup values and force a post-initialization group,
            // even when the switch starts at its reference/OFF position.
            O_ae <= 16'd1990;
            O_ag <= 16'd17;
            O_protect_applied <= 1'b1;
            O_valid <= 1'b0;
            in_flight <= 1'b0;
            saw_busy <= 1'b0;
            requested_protect <= 1'b1;
        end else begin
            O_ae_req <= 1'b0;
            if (in_flight) begin
                if (!I_ae_cfg_done) begin
                    saw_busy <= 1'b1;
                end else if (saw_busy && I_cam_cfg_done) begin
                    O_protect_applied <= requested_protect;
                    O_valid <= 1'b1;
                    in_flight <= 1'b0;
                    saw_busy <= 1'b0;
                end
            end else if (I_cam_cfg_done && I_ae_cfg_done &&
                         (!O_valid || (O_protect_applied != I_protect_en))) begin
                O_ae <= I_protect_en ? FIXED_EXPOSURE : REFERENCE_EXPOSURE;
                O_ag <= I_protect_en ? FIXED_GAIN : REFERENCE_GAIN;
                requested_protect <= I_protect_en;
                O_ae_req <= 1'b1;
                O_valid <= 1'b0;
                in_flight <= 1'b1;
                saw_busy <= 1'b0;
            end
            // No FIFO is required: a stable switch level is the latest target.
            // If it changes while busy, compare it again after this ACK. If it
            // returns to this group's selection, do not issue a duplicate.
        end
    end
endmodule
