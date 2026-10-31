// Remove only the chroma of shading overflow, retaining the old RGB8 colour.
// Prepares tone operands BEFORE the existing mixer register. The shoulder
// must still use the ORIGINAL wide peak; recomputing it changes brightness.
// No multipliers, registers, line/frame memory, division or scene history.
module highlight_white_prepare (
    input wire I_enable,
    input wire [1:0] I_white_sel, // 0 off, 1 <=1/4, 2 <=1/2, 3 <=full correction
    input wire [26:0] I_wide_data,
    output wire [26:0] O_wide_data
);
    wire [8:0] S_r = I_wide_data[26:18];
    wire [8:0] S_g = I_wide_data[17:9];
    wire [8:0] S_b = I_wide_data[8:0];
    // Overflow starts continuously at 256, rather than resetting hue at 255.
    wire [8:0] S_er = S_r[8] ? ({1'b0,S_r[7:0]} + 9'd1) : 9'd0;
    wire [8:0] S_eg = S_g[8] ? ({1'b0,S_g[7:0]} + 9'd1) : 9'd0;
    wire [8:0] S_eb = S_b[8] ? ({1'b0,S_b[7:0]} + 9'd1) : 9'd0;
    wire [10:0] S_excess_y4 = {2'b0,S_er} + {1'b0,S_eg,1'b0} + {2'b0,S_eb} + 11'd2;
    wire [8:0] S_excess_y = S_excess_y4[10:2];
    // Equivalent to testing min(clipped RGB)>=threshold, without a min tree.
    // A narrower confidence ramp limits correction of pastel colours.
    wire S_near240 = (S_r >= 9'd240) && (S_g >= 9'd240) && (S_b >= 9'd240);
    wire S_near244 = (S_r >= 9'd244) && (S_g >= 9'd244) && (S_b >= 9'd244);
    wire S_near248 = (S_r >= 9'd248) && (S_g >= 9'd248) && (S_b >= 9'd248);
    wire [1:0] S_confidence = S_near248 ? 2'd3 : S_near244 ? 2'd2 : S_near240 ? 2'd1 : 2'd0;
    wire [1:0] S_strength = (I_white_sel < S_confidence) ? I_white_sel : S_confidence;
    wire S_apply = I_enable && (|{S_r[8],S_g[8],S_b[8]}) && (S_strength != 2'd0);
    function [8:0] f_correct;
        input [8:0] value;
        input [8:0] excess;
        input [8:0] mean_excess;
        input [1:0] strength;
        reg signed [10:0] delta;
        reg signed [10:0] result;
        begin
            delta = $signed({2'b0,mean_excess}) - $signed({2'b0,excess});
            case (strength)
                2'd1: delta = (delta + 11'sd2) >>> 2;
                2'd2: delta = (delta + 11'sd1) >>> 1;
                default: delta = delta;
            endcase
            result = $signed({2'b0,value}) + delta;
            // Every result is a convex blend of value and clip8(value)+mean.
            // Both endpoints fit 9 bits and do not exceed the original peak.
            f_correct = result[8:0];
        end
    endfunction
    assign O_wide_data = !S_apply ? I_wide_data : {
        f_correct(S_r,S_er,S_excess_y,S_strength),
        f_correct(S_g,S_eg,S_excess_y,S_strength),
        f_correct(S_b,S_eb,S_excess_y,S_strength)
    };
endmodule
