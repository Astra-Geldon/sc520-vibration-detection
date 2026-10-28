// Bind conservative common-motion evidence to the exact spectrum window.
// i_ready/i_motion describe this frame's four reference blocks, completed
// before row5 arrives. No sample is removed, replaced or delayed.
`ifndef VIB_MOTION_WINDOW_V
`define VIB_MOTION_WINDOW_V
module vib_motion_window (
    input wire clk, rst_n,
    input wire i_tick,
    input wire [2:0] i_row,
    input wire i_ready, i_valid, i_motion,
    input wire i_scan_trig,
    output wire o_veto,
    output reg [31:0] o_info
);
    reg [6:0] motion_frames, valid_frames, unavailable_frames;
    wire frame_end=i_tick&&(i_row==3'd5);
    wire frame_valid=i_ready&&i_valid;
    wire frame_motion=frame_valid&&i_motion;
    // Include a simultaneous final-frame observation rather than assigning
    // it to the next window. In the normal path scan starts >400 clocks later.
    wire [6:0] motion_total=motion_frames+
        ((frame_end&&frame_motion&&(motion_frames<7'd64))?7'd1:7'd0);
    wire [6:0] valid_total=valid_frames+
        ((frame_end&&frame_valid&&(valid_frames<7'd64))?7'd1:7'd0);
    wire [6:0] unavailable_total=unavailable_frames+
        ((frame_end&&!frame_valid&&(unavailable_frames<7'd64))?7'd1:7'd0);
    assign o_veto=(motion_total!=0);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            motion_frames<=0; valid_frames<=0; unavailable_frames<=0;
            o_info<=0;
        end else if(i_scan_trig) begin
            // [31] rejected, [22:16] coherent-motion frame count,
            // [14:8] all-four-valid frame count, [6:0] unavailable count.
            o_info<={o_veto,8'd0,motion_total,1'b0,valid_total,1'b0,unavailable_total};
            motion_frames<=0; valid_frames<=0; unavailable_frames<=0;
        end else if(frame_end) begin
            motion_frames<=motion_total;
            valid_frames<=valid_total;
            unavailable_frames<=unavailable_total;
        end
    end
endmodule
`endif
