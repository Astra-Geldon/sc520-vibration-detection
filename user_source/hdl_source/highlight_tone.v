// Single-exposure, streaming midtone compensation. H1 is evaluated BEFORE
// compensation. It never switches the sensor exposure per region or recovers
// samples already clipped earlier in the sensor/ISP chain.
// No pixel registers, line/frame storage, division, or history are used.
module highlight_tone (
    input  wire        I_de,
    input  wire        I_enable,
    input  wire [2:0]  I_sel,       // 0=off, 1=weak, 2=medium, 3=strong, 4=H1 mask
    input  wire [23:0] I_data,      // current color pixel BEFORE OSD/Logo
    output wire        O_mask,
    output wire [23:0] O_data
);
    wire [23:0] S_marker;
    highlight_region u_h1 (
        .I_de(I_de), .I_enable(I_enable), .I_sel(2'd1),
        .I_source(I_data), .I_data(I_data),
        .O_mask(O_mask), .O_data(S_marker)
    );

    wire [7:0] S_r = I_data[23:16];
    wire [7:0] S_g = I_data[15:8];
    wire [7:0] S_b = I_data[7:0];
    wire [7:0] S_rg_max = (S_r > S_g) ? S_r : S_g;
    wire [7:0] S_max = (S_rg_max > S_b) ? S_rg_max : S_b;
    // Stop lifting at the maximum-channel shoulder. Every H1 pixel is
    // unchanged; this also protects saturated colors whose Y is below 208.
    wire [7:0] S_room = (S_max < 8'd208) ? (8'd208 - S_max) : 8'd0;
    wire [15:0] S_pr = S_r * S_room;
    wire [15:0] S_pg = S_g * S_room;
    wire [15:0] S_pb = S_b * S_room;

    function [7:0] f_lift;
        input [7:0] value;
        input [15:0] product;
        input [2:0] candidate;
        reg [17:0] numerator;
        reg [8:0] lifted;
        begin
            // Same gain for R/G/B, rounded once per channel. Common products
            // are shared between all candidates; 3*p is an add and shift.
            case (candidate)
                3'd1: begin
                    numerator = {2'b0, product} + 18'd256;
                    lifted = {1'b0, value} + numerator[17:9];
                end
                3'd2: begin
                    numerator = {2'b0, product} + {1'b0, product, 1'b0} + 18'd512;
                    lifted = {1'b0, value} + {1'b0, numerator[17:10]};
                end
                3'd3: begin
                    numerator = {2'b0, product} + 18'd128;
                    lifted = {1'b0, value} + numerator[16:8];
                end
                default: begin
                    numerator = 18'd0;
                    lifted = {1'b0, value};
                end
            endcase
            // The max-channel shoulder bounds valid lifted pixels to <=208.
            // Saturation is explicit rather than allowing unsigned wrap.
            f_lift = lifted[8] ? 8'hff : lifted[7:0];
        end
    endfunction

    wire [23:0] S_lifted = {f_lift(S_r, S_pr, I_sel),
                            f_lift(S_g, S_pg, I_sel),
                            f_lift(S_b, S_pb, I_sel)};
    assign O_data = (!I_de || !I_enable) ? I_data :
                    (I_sel == 3'd4) ? S_marker :
                    O_mask ? I_data : S_lifted;
endmodule
