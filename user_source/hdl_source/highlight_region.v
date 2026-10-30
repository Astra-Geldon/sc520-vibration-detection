// Streaming highlight mask, evaluated independently for every video pixel.
// There is no frame/line buffer, spatial blend, temporal hold, or exposure fusion.
// Non-highlight pixels (and all disabled/blanked pixels) pass through bit for bit.
module highlight_region (
    input  wire        I_de,
    input  wire        I_enable,
    input  wire [1:0]  I_sel,         // 0=off, 1=wide, 2=standard, 3=strict
    input  wire [23:0] I_source,      // camera RGB before OSD/Logo
    input  wire [23:0] I_data,        // display pixels, same cycle as source
    output wire        O_mask,
    output wire [23:0] O_data
);
    wire [7:0] S_r = I_source[23:16];
    wire [7:0] S_g = I_source[15:8];
    wire [7:0] S_b = I_source[7:0];
    // Four times Y, with explicit widths to cover 0..1020.
    wire [9:0] S_y4 = {2'b0, S_r} + {1'b0, S_g, 1'b0} + {2'b0, S_b};
    wire [9:0] S_limit4 = (I_sel == 2'd1) ? 10'd832 :  // Y >= 208
                          (I_sel == 2'd2) ? 10'd896 :  // Y >= 224
                                           10'd960;   // Y >= 240
    // Channel clipping is a risk even when luma is lower, e.g. saturated red.
    wire S_channel_clip = (S_r >= 8'd250) || (S_g >= 8'd250) || (S_b >= 8'd250);
    assign O_mask = I_de && I_enable && (I_sel != 2'd0) &&
                    ((S_y4 >= S_limit4) || S_channel_clip);
    // Magenta is only a visible selection marker, not a protected exposure.
    assign O_data = O_mask ? 24'hFF00FF : I_data;
endmodule
