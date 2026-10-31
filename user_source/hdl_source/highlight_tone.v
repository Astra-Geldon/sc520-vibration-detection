// Shared analytical gain lookup from the current pixel maximum.
// Top captures only the maximum at the existing pixel boundary.
module highlight_gain (
    input wire [2:0] I_sel,
    input wire [8:0] I_peak,
    output wire [17:0] O_gain
);
    wire [1:0] S_profile = I_sel[1:0];
    wire S_wide_enable = (S_profile != 2'd0);
    // Full Q16 gain is algebraically identical to old value+round(value*boost).
    function [17:0] f_c3_gain;
        input [7:0] peak;
        begin
            case (peak)
                8'd0: f_c3_gain = 18'd205312;
                8'd1: f_c3_gain = 18'd204226;
                8'd2: f_c3_gain = 18'd203144;
                8'd3: f_c3_gain = 18'd202066;
                8'd4: f_c3_gain = 18'd200992;
                8'd5: f_c3_gain = 18'd199922;
                8'd6: f_c3_gain = 18'd198856;
                8'd7: f_c3_gain = 18'd197794;
                8'd8: f_c3_gain = 18'd196736;
                8'd9: f_c3_gain = 18'd195682;
                8'd10: f_c3_gain = 18'd194632;
                8'd11: f_c3_gain = 18'd193586;
                8'd12: f_c3_gain = 18'd192544;
                8'd13: f_c3_gain = 18'd191506;
                8'd14: f_c3_gain = 18'd190472;
                8'd15: f_c3_gain = 18'd189442;
                8'd16: f_c3_gain = 18'd188416;
                8'd17: f_c3_gain = 18'd187394;
                8'd18: f_c3_gain = 18'd186376;
                8'd19: f_c3_gain = 18'd185362;
                8'd20: f_c3_gain = 18'd184352;
                8'd21: f_c3_gain = 18'd183346;
                8'd22: f_c3_gain = 18'd182344;
                8'd23: f_c3_gain = 18'd181346;
                8'd24: f_c3_gain = 18'd180352;
                8'd25: f_c3_gain = 18'd179362;
                8'd26: f_c3_gain = 18'd178376;
                8'd27: f_c3_gain = 18'd177394;
                8'd28: f_c3_gain = 18'd176416;
                8'd29: f_c3_gain = 18'd175442;
                8'd30: f_c3_gain = 18'd174472;
                8'd31: f_c3_gain = 18'd173506;
                8'd32: f_c3_gain = 18'd172544;
                8'd33: f_c3_gain = 18'd171586;
                8'd34: f_c3_gain = 18'd170632;
                8'd35: f_c3_gain = 18'd169682;
                8'd36: f_c3_gain = 18'd168736;
                8'd37: f_c3_gain = 18'd167794;
                8'd38: f_c3_gain = 18'd166856;
                8'd39: f_c3_gain = 18'd165922;
                8'd40: f_c3_gain = 18'd164992;
                8'd41: f_c3_gain = 18'd164066;
                8'd42: f_c3_gain = 18'd163144;
                8'd43: f_c3_gain = 18'd162226;
                8'd44: f_c3_gain = 18'd161312;
                8'd45: f_c3_gain = 18'd160402;
                8'd46: f_c3_gain = 18'd159496;
                8'd47: f_c3_gain = 18'd158594;
                8'd48: f_c3_gain = 18'd157696;
                8'd49: f_c3_gain = 18'd156802;
                8'd50: f_c3_gain = 18'd155912;
                8'd51: f_c3_gain = 18'd155026;
                8'd52: f_c3_gain = 18'd154144;
                8'd53: f_c3_gain = 18'd153266;
                8'd54: f_c3_gain = 18'd152392;
                8'd55: f_c3_gain = 18'd151522;
                8'd56: f_c3_gain = 18'd150656;
                8'd57: f_c3_gain = 18'd149794;
                8'd58: f_c3_gain = 18'd148936;
                8'd59: f_c3_gain = 18'd148082;
                8'd60: f_c3_gain = 18'd147232;
                8'd61: f_c3_gain = 18'd146386;
                8'd62: f_c3_gain = 18'd145544;
                8'd63: f_c3_gain = 18'd144706;
                8'd64: f_c3_gain = 18'd143872;
                8'd65: f_c3_gain = 18'd143042;
                8'd66: f_c3_gain = 18'd142216;
                8'd67: f_c3_gain = 18'd141394;
                8'd68: f_c3_gain = 18'd140576;
                8'd69: f_c3_gain = 18'd139762;
                8'd70: f_c3_gain = 18'd138952;
                8'd71: f_c3_gain = 18'd138146;
                8'd72: f_c3_gain = 18'd137344;
                8'd73: f_c3_gain = 18'd136546;
                8'd74: f_c3_gain = 18'd135752;
                8'd75: f_c3_gain = 18'd134962;
                8'd76: f_c3_gain = 18'd134176;
                8'd77: f_c3_gain = 18'd133394;
                8'd78: f_c3_gain = 18'd132616;
                8'd79: f_c3_gain = 18'd131842;
                8'd80: f_c3_gain = 18'd131072;
                8'd81: f_c3_gain = 18'd130306;
                8'd82: f_c3_gain = 18'd129544;
                8'd83: f_c3_gain = 18'd128786;
                8'd84: f_c3_gain = 18'd128032;
                8'd85: f_c3_gain = 18'd127282;
                8'd86: f_c3_gain = 18'd126536;
                8'd87: f_c3_gain = 18'd125794;
                8'd88: f_c3_gain = 18'd125056;
                8'd89: f_c3_gain = 18'd124322;
                8'd90: f_c3_gain = 18'd123592;
                8'd91: f_c3_gain = 18'd122866;
                8'd92: f_c3_gain = 18'd122144;
                8'd93: f_c3_gain = 18'd121426;
                8'd94: f_c3_gain = 18'd120712;
                8'd95: f_c3_gain = 18'd120002;
                8'd96: f_c3_gain = 18'd119296;
                8'd97: f_c3_gain = 18'd118594;
                8'd98: f_c3_gain = 18'd117896;
                8'd99: f_c3_gain = 18'd117202;
                8'd100: f_c3_gain = 18'd116512;
                8'd101: f_c3_gain = 18'd115826;
                8'd102: f_c3_gain = 18'd115144;
                8'd103: f_c3_gain = 18'd114466;
                8'd104: f_c3_gain = 18'd113792;
                8'd105: f_c3_gain = 18'd113122;
                8'd106: f_c3_gain = 18'd112456;
                8'd107: f_c3_gain = 18'd111794;
                8'd108: f_c3_gain = 18'd111136;
                8'd109: f_c3_gain = 18'd110482;
                8'd110: f_c3_gain = 18'd109832;
                8'd111: f_c3_gain = 18'd109186;
                8'd112: f_c3_gain = 18'd108544;
                8'd113: f_c3_gain = 18'd107906;
                8'd114: f_c3_gain = 18'd107272;
                8'd115: f_c3_gain = 18'd106642;
                8'd116: f_c3_gain = 18'd106016;
                8'd117: f_c3_gain = 18'd105394;
                8'd118: f_c3_gain = 18'd104776;
                8'd119: f_c3_gain = 18'd104162;
                8'd120: f_c3_gain = 18'd103552;
                8'd121: f_c3_gain = 18'd102946;
                8'd122: f_c3_gain = 18'd102344;
                8'd123: f_c3_gain = 18'd101746;
                8'd124: f_c3_gain = 18'd101152;
                8'd125: f_c3_gain = 18'd100562;
                8'd126: f_c3_gain = 18'd99976;
                8'd127: f_c3_gain = 18'd99394;
                8'd128: f_c3_gain = 18'd98816;
                8'd129: f_c3_gain = 18'd98242;
                8'd130: f_c3_gain = 18'd97672;
                8'd131: f_c3_gain = 18'd97106;
                8'd132: f_c3_gain = 18'd96544;
                8'd133: f_c3_gain = 18'd95986;
                8'd134: f_c3_gain = 18'd95432;
                8'd135: f_c3_gain = 18'd94882;
                8'd136: f_c3_gain = 18'd94336;
                8'd137: f_c3_gain = 18'd93794;
                8'd138: f_c3_gain = 18'd93256;
                8'd139: f_c3_gain = 18'd92722;
                8'd140: f_c3_gain = 18'd92192;
                8'd141: f_c3_gain = 18'd91666;
                8'd142: f_c3_gain = 18'd91144;
                8'd143: f_c3_gain = 18'd90626;
                8'd144: f_c3_gain = 18'd90112;
                8'd145: f_c3_gain = 18'd89602;
                8'd146: f_c3_gain = 18'd89096;
                8'd147: f_c3_gain = 18'd88594;
                8'd148: f_c3_gain = 18'd88096;
                8'd149: f_c3_gain = 18'd87602;
                8'd150: f_c3_gain = 18'd87112;
                8'd151: f_c3_gain = 18'd86626;
                8'd152: f_c3_gain = 18'd86144;
                8'd153: f_c3_gain = 18'd85666;
                8'd154: f_c3_gain = 18'd85192;
                8'd155: f_c3_gain = 18'd84722;
                8'd156: f_c3_gain = 18'd84256;
                8'd157: f_c3_gain = 18'd83794;
                8'd158: f_c3_gain = 18'd83336;
                8'd159: f_c3_gain = 18'd82882;
                8'd160: f_c3_gain = 18'd82432;
                8'd161: f_c3_gain = 18'd81986;
                8'd162: f_c3_gain = 18'd81544;
                8'd163: f_c3_gain = 18'd81106;
                8'd164: f_c3_gain = 18'd80672;
                8'd165: f_c3_gain = 18'd80242;
                8'd166: f_c3_gain = 18'd79816;
                8'd167: f_c3_gain = 18'd79394;
                8'd168: f_c3_gain = 18'd78976;
                8'd169: f_c3_gain = 18'd78562;
                8'd170: f_c3_gain = 18'd78152;
                8'd171: f_c3_gain = 18'd77746;
                8'd172: f_c3_gain = 18'd77344;
                8'd173: f_c3_gain = 18'd76946;
                8'd174: f_c3_gain = 18'd76552;
                8'd175: f_c3_gain = 18'd76162;
                8'd176: f_c3_gain = 18'd75776;
                8'd177: f_c3_gain = 18'd75394;
                8'd178: f_c3_gain = 18'd75016;
                8'd179: f_c3_gain = 18'd74642;
                8'd180: f_c3_gain = 18'd74272;
                8'd181: f_c3_gain = 18'd73906;
                8'd182: f_c3_gain = 18'd73544;
                8'd183: f_c3_gain = 18'd73186;
                8'd184: f_c3_gain = 18'd72832;
                8'd185: f_c3_gain = 18'd72482;
                8'd186: f_c3_gain = 18'd72136;
                8'd187: f_c3_gain = 18'd71794;
                8'd188: f_c3_gain = 18'd71456;
                8'd189: f_c3_gain = 18'd71122;
                8'd190: f_c3_gain = 18'd70792;
                8'd191: f_c3_gain = 18'd70466;
                8'd192: f_c3_gain = 18'd70144;
                8'd193: f_c3_gain = 18'd69826;
                8'd194: f_c3_gain = 18'd69512;
                8'd195: f_c3_gain = 18'd69202;
                8'd196: f_c3_gain = 18'd68896;
                8'd197: f_c3_gain = 18'd68594;
                8'd198: f_c3_gain = 18'd68296;
                8'd199: f_c3_gain = 18'd68002;
                8'd200: f_c3_gain = 18'd67712;
                8'd201: f_c3_gain = 18'd67426;
                8'd202: f_c3_gain = 18'd67144;
                8'd203: f_c3_gain = 18'd66866;
                8'd204: f_c3_gain = 18'd66592;
                8'd205: f_c3_gain = 18'd66322;
                8'd206: f_c3_gain = 18'd66056;
                8'd207: f_c3_gain = 18'd65794;
                default: f_c3_gain = 18'd65536;
            endcase
        end
    endfunction
    wire [47:0] S_shoulder_gains;
    highlight_shoulder_lut u_shoulder_lut (.I_peak(I_peak), .O_gains(S_shoulder_gains));
    reg [17:0] S_gain;
    always @(*) begin
        S_gain = (I_sel[2] && (I_peak < 9'd208)) ? f_c3_gain(I_peak[7:0]) : 18'd65536;
        if (S_wide_enable && (I_peak > 9'd208)) begin
            case (S_profile)
                2'd1: S_gain = {2'b0, S_shoulder_gains[47:32]};
                2'd2: S_gain = {2'b0, S_shoulder_gains[31:16]};
                default: S_gain = {2'b0, S_shoulder_gains[15:0]};
            endcase
        end
    end
    assign O_gain = S_gain;
endmodule

// One shared three-multiplier bank: legacy C0/C3 or wide RGB shoulder.
// I_sel={C3_enable, P[1:0]}; P0=legacy reference, P1/2/3=weak/medium/strong.
// Shading values retain nine integer bits until the common gain is applied.
// No pixel registers, frame/line storage, runtime division or history.
module highlight_tone #(
    parameter integer PRECOMPUTED_PEAK_EN = 0
)(
    input wire I_de,
    input wire I_enable,
    input wire [2:0] I_sel,
    input wire [23:0] I_data, // original clipped img_proc output; non-colour bypass
    input wire [26:0] I_wide_data, // aligned {R9,G9,B9} BEFORE shading clipping
    input wire [8:0] I_peak, // used only with PRECOMPUTED_PEAK_EN=1; aligned with RGB
    output wire O_mask,
    output wire [23:0] O_data
);
    wire [23:0] S_marker;
    highlight_region u_h1 (
        .I_de(I_de), .I_enable(I_enable), .I_sel(2'd1),
        .I_source(I_data), .I_data(I_data), .O_mask(O_mask), .O_data(S_marker)
    );
    wire [1:0] S_profile = I_sel[1:0];
    wire S_wide_enable = (S_profile != 2'd0);
    wire [8:0] S_r = S_wide_enable ? I_wide_data[26:18] : {1'b0, I_data[23:16]};
    wire [8:0] S_g = S_wide_enable ? I_wide_data[17:9] : {1'b0, I_data[15:8]};
    wire [8:0] S_b = S_wide_enable ? I_wide_data[8:0] : {1'b0, I_data[7:0]};
    wire [8:0] S_peak;
    generate
        if (PRECOMPUTED_PEAK_EN != 0) begin : g_registered_peak
            assign S_peak = I_peak;
        end else begin : g_combinational_peak
            wire [8:0] rg_max = (S_r > S_g) ? S_r : S_g;
            assign S_peak = (rg_max > S_b) ? rg_max : S_b;
        end
    endgenerate
    wire [17:0] S_gain;
    highlight_gain u_gain (.I_sel(I_sel), .I_peak(S_peak), .O_gain(S_gain));
    // Exactly three multiplications; both branches select operands BEFORE them.
    wire [26:0] S_pr = S_r * S_gain;
    wire [26:0] S_pg = S_g * S_gain;
    wire [26:0] S_pb = S_b * S_gain;
    function [7:0] f_apply;
        input [26:0] product;
        reg [26:0] rounded;
        begin
            rounded = product + 27'd32768;
            f_apply = (|rounded[26:24]) ? 8'hff : rounded[23:16];
        end
    endfunction
    // H1 still reports the original mask, but must not bypass high compression.
    assign O_data = (!I_de || !I_enable) ? I_data :
                    {f_apply(S_pr), f_apply(S_pg), f_apply(S_pb)};
endmodule
