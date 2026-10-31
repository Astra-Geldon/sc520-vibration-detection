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

// Shared scalar lift from accepted RGB8. Q8 gains constrained to monotone
// rounded peak targets. L1 preserves the old G12 reference; N1/N2 lift
// only mid-dark pixels and return to exact unity at peak>=192. N2 lifts
// shadows more strongly, with a flatter shoulder. Common RGB scaling;
// no RGB9 shoulder, channel LUTs, DSP or frame processing.
module gain8_lift_gain(input wire [7:0] I_peak,input wire [1:0] I_sel,output wire [10:0] O_gain);
 reg [32:0] values;
 always @(*) begin
  case(I_peak)
            8'd0: values=33'h040080100;
            8'd1: values=33'h0be900300;
            8'd2: values=33'h0bd100280;
            8'd3: values=33'h0bb8d5aab;
            8'd4: values=33'h0ba4e0280;
            8'd5: values=33'h0b8ce6a9a;
            8'd6: values=33'h0b74eaa80;
            8'd7: values=33'h0b60dba92;
            8'd8: values=33'h0b4ce0280;
            8'd9: values=33'h0b34e3a8e;
            8'd10: values=33'h0b20e6a80;
            8'd11: values=33'h0b0cdd28c;
            8'd12: values=33'h0af8e0280;
            8'd13: values=33'h0ae4e2a8a;
            8'd14: values=33'h0ad0e4a80;
            8'd15: values=33'h0abcde289;
            8'd16: values=33'h0aa8e0280;
            8'd17: values=33'h0a98e2278;
            8'd18: values=33'h0a84dca72;
            8'd19: values=33'h0a70dea6c;
            8'd20: values=33'h0a60d9a66;
            8'd21: values=33'h0a4cdba62;
            8'd22: values=33'h0a3cd7a5d;
            8'd23: values=33'h0a2cd9259;
            8'd24: values=33'h0a18d5a55;
            8'd25: values=33'h0a08d7252;
            8'd26: values=33'h09f8d3a4f;
            8'd27: values=33'h09e8d5a4c;
            8'd28: values=33'h09d8d2a49;
            8'd29: values=33'h09c8d4247;
            8'd30: values=33'h09b8d1244;
            8'd31: values=33'h09a8d2a42;
            8'd32: values=33'h0998d0240;
            8'd33: values=33'h0988d1a3e;
            8'd34: values=33'h097ccf235;
            8'd35: values=33'h096cd0a33;
            8'd36: values=33'h095cce232;
            8'd37: values=33'h094ccfa2a;
            8'd38: values=33'h0940cda28;
            8'd39: values=33'h0930cf221;
            8'd40: values=33'h0924cd220;
            8'd41: values=33'h0914ce21f;
            8'd42: values=33'h0908cc218;
            8'd43: values=33'h08f8cda18;
            8'd44: values=33'h08eccba17;
            8'd45: values=33'h08e0cd211;
            8'd46: values=33'h08d0cb211;
            8'd47: values=33'h08c4cca0b;
            8'd48: values=33'h08b8caa0b;
            8'd49: values=33'h08accc20a;
            8'd50: values=33'h08a0ca205;
            8'd51: values=33'h0894cba05;
            8'd52: values=33'h0888ca205;
            8'd53: values=33'h0878cb200;
            8'd54: values=33'h0870c9a00;
            8'd55: values=33'h0864ca9fb;
            8'd56: values=33'h0858c91fb;
            8'd57: values=33'h084cca1fc;
            8'd58: values=33'h0840c91f7;
            8'd59: values=33'h0834ca1f7;
            8'd60: values=33'h0828c89f7;
            8'd61: values=33'h081cc99f3;
            8'd62: values=33'h0814c89f4;
            8'd63: values=33'h0808c91f0;
            8'd64: values=33'h07fcc81f0;
            8'd65: values=33'h07f4c71ec;
            8'd66: values=33'h07e8c61e9;
            8'd67: values=33'h07dcc51e5;
            8'd68: values=33'h07d4c59e2;
            8'd69: values=33'h07c8c49df;
            8'd70: values=33'h07c0c39db;
            8'd71: values=33'h07b4c29d8;
            8'd72: values=33'h07acc21d5;
            8'd73: values=33'h07a0c11d2;
            8'd74: values=33'h0798c01d0;
            8'd75: values=33'h0790bf1cd;
            8'd76: values=33'h0784c01ca;
            8'd77: values=33'h077cbf1c7;
            8'd78: values=33'h0770be9c5;
            8'd79: values=33'h0768bd9c2;
            8'd80: values=33'h075cbd1c0;
            8'd81: values=33'h0758bc1be;
            8'd82: values=33'h074cbb9bb;
            8'd83: values=33'h0744ba9b9;
            8'd84: values=33'h073cbb9b7;
            8'd85: values=33'h0734ba9b5;
            8'd86: values=33'h072cba1b3;
            8'd87: values=33'h0724b99b1;
            8'd88: values=33'h0718b89af;
            8'd89: values=33'h0710b81ad;
            8'd90: values=33'h0708b79ab;
            8'd91: values=33'h0700b71a9;
            8'd92: values=33'h06f8b79a7;
            8'd93: values=33'h06f0b71a5;
            8'd94: values=33'h06e8b69a3;
            8'd95: values=33'h06e0b61a2;
            8'd96: values=33'h06d8b59a0;
            8'd97: values=33'h06d0b519e;
            8'd98: values=33'h06c8b419a;
            8'd99: values=33'h06c0b2999;
            8'd100: values=33'h06b8b2197;
            8'd101: values=33'h06b4b1993;
            8'd102: values=33'h06acb1192;
            8'd103: values=33'h06a4af18e;
            8'd104: values=33'h069caf18c;
            8'd105: values=33'h0694ae98b;
            8'd106: values=33'h0690ae187;
            8'd107: values=33'h0688ac986;
            8'd108: values=33'h067cac185;
            8'd109: values=33'h0678ab981;
            8'd110: values=33'h0670ab180;
            8'd111: values=33'h066ca997d;
            8'd112: values=33'h0664a917b;
            8'd113: values=33'h065ca917a;
            8'd114: values=33'h0658a8977;
            8'd115: values=33'h0650a7176;
            8'd116: values=33'h0648a6975;
            8'd117: values=33'h0640a6972;
            8'd118: values=33'h063ca6171;
            8'd119: values=33'h0634a496e;
            8'd120: values=33'h062ca496d;
            8'd121: values=33'h0628a416c;
            8'd122: values=33'h0620a3969;
            8'd123: values=33'h061ca2968;
            8'd124: values=33'h0618a2167;
            8'd125: values=33'h0610a2164;
            8'd126: values=33'h0608a1964;
            8'd127: values=33'h0604a0961;
            8'd128: values=33'h05fca0160;
            8'd129: values=33'h05f8a015d;
            8'd130: values=33'h05f09e95d;
            8'd131: values=33'h05ec9e95a;
            8'd132: values=33'h05e89d157;
            8'd133: values=33'h05e09d155;
            8'd134: values=33'h05d89b954;
            8'd135: values=33'h05d49b952;
            8'd136: values=33'h05cc9a94f;
            8'd137: values=33'h05c89a14d;
            8'd138: values=33'h05c49914c;
            8'd139: values=33'h05c09914a;
            8'd140: values=33'h05b898147;
            8'd141: values=33'h05b497945;
            8'd142: values=33'h05b096945;
            8'd143: values=33'h05a896942;
            8'd144: values=33'h05a495940;
            8'd145: values=33'h05a09513e;
            8'd146: values=33'h05989413d;
            8'd147: values=33'h05949413b;
            8'd148: values=33'h058c93139;
            8'd149: values=33'h058893137;
            8'd150: values=33'h058492137;
            8'd151: values=33'h057c92135;
            8'd152: values=33'h057891133;
            8'd153: values=33'h057490931;
            8'd154: values=33'h057090130;
            8'd155: values=33'h056c8f92e;
            8'd156: values=33'h05648f12c;
            8'd157: values=33'h05608e92a;
            8'd158: values=33'h055c8e12a;
            8'd159: values=33'h05588d928;
            8'd160: values=33'h05548d126;
            8'd161: values=33'h054c8c925;
            8'd162: values=33'h05488c124;
            8'd163: values=33'h05448c123;
            8'd164: values=33'h05408b121;
            8'd165: values=33'h053c8b11f;
            8'd166: values=33'h05348a11f;
            8'd167: values=33'h05308a11d;
            8'd168: values=33'h052c8911b;
            8'd169: values=33'h05288911a;
            8'd170: values=33'h05288891a;
            8'd171: values=33'h052088118;
            8'd172: values=33'h051c87916;
            8'd173: values=33'h051887915;
            8'd174: values=33'h051486915;
            8'd175: values=33'h051086913;
            8'd176: values=33'h050c86111;
            8'd177: values=33'h050486110;
            8'd178: values=33'h050485110;
            8'd179: values=33'h04fc8510e;
            8'd180: values=33'h04f88490d;
            8'd181: values=33'h04f48410b;
            8'd182: values=33'h04f08390b;
            8'd183: values=33'h04ec8390a;
            8'd184: values=33'h04e883108;
            8'd185: values=33'h04e483107;
            8'd186: values=33'h04e082107;
            8'd187: values=33'h04dc82105;
            8'd188: values=33'h04d881904;
            8'd189: values=33'h04d481903;
            8'd190: values=33'h04d080903;
            8'd191: values=33'h04cc80901;
            8'd192: values=33'h04c880100;
            8'd193: values=33'h04c480100;
            8'd194: values=33'h04c480100;
            8'd195: values=33'h04bc80100;
            8'd196: values=33'h04bc80100;
            8'd197: values=33'h04b880100;
            8'd198: values=33'h04b480100;
            8'd199: values=33'h04b080100;
            8'd200: values=33'h04ac80100;
            8'd201: values=33'h04a880100;
            8'd202: values=33'h04a480100;
            8'd203: values=33'h04a080100;
            8'd204: values=33'h049c80100;
            8'd205: values=33'h049c80100;
            8'd206: values=33'h049480100;
            8'd207: values=33'h049480100;
            8'd208: values=33'h049080100;
            8'd209: values=33'h048c80100;
            8'd210: values=33'h048880100;
            8'd211: values=33'h048480100;
            8'd212: values=33'h048080100;
            8'd213: values=33'h047c80100;
            8'd214: values=33'h047c80100;
            8'd215: values=33'h047880100;
            8'd216: values=33'h047880100;
            8'd217: values=33'h047080100;
            8'd218: values=33'h046c80100;
            8'd219: values=33'h046c80100;
            8'd220: values=33'h046880100;
            8'd221: values=33'h046480100;
            8'd222: values=33'h046080100;
            8'd223: values=33'h045c80100;
            8'd224: values=33'h045c80100;
            8'd225: values=33'h045880100;
            8'd226: values=33'h045480100;
            8'd227: values=33'h045080100;
            8'd228: values=33'h044c80100;
            8'd229: values=33'h044c80100;
            8'd230: values=33'h044880100;
            8'd231: values=33'h044480100;
            8'd232: values=33'h044080100;
            8'd233: values=33'h043c80100;
            8'd234: values=33'h043c80100;
            8'd235: values=33'h043880100;
            8'd236: values=33'h043480100;
            8'd237: values=33'h043480100;
            8'd238: values=33'h043080100;
            8'd239: values=33'h042c80100;
            8'd240: values=33'h042c80100;
            8'd241: values=33'h042880100;
            8'd242: values=33'h042480100;
            8'd243: values=33'h042080100;
            8'd244: values=33'h041c80100;
            8'd245: values=33'h041c80100;
            8'd246: values=33'h041880100;
            8'd247: values=33'h041480100;
            8'd248: values=33'h041480100;
            8'd249: values=33'h041080100;
            8'd250: values=33'h040c80100;
            8'd251: values=33'h040c80100;
            8'd252: values=33'h040880100;
            8'd253: values=33'h040480100;
            8'd254: values=33'h040080100;
            8'd255: values=33'h040080100;
   default: values={11'd256,11'd256,11'd256};
  endcase
 end
 assign O_gain=(I_sel==0)?11'd256:(I_sel==1)?values[32:22]:(I_sel==2)?values[21:11]:values[10:0];
endmodule

// Explicit bit partial products and balanced tree. No multiply operator;
// the full TD resource report, not source syntax, confirms DSP usage.
module gain8_lift_channel(input wire [7:0] I_pixel,input wire [10:0] I_gain,output wire [7:0] O_pixel);
        wire [18:0] t0 = I_gain[0] ? { 11'd0, I_pixel } : 19'd0;
        wire [18:0] t1 = I_gain[1] ? { 10'd0, I_pixel, 1'd0 } : 19'd0;
        wire [18:0] t2 = I_gain[2] ? { 9'd0, I_pixel, 2'd0 } : 19'd0;
        wire [18:0] t3 = I_gain[3] ? { 8'd0, I_pixel, 3'd0 } : 19'd0;
        wire [18:0] t4 = I_gain[4] ? { 7'd0, I_pixel, 4'd0 } : 19'd0;
        wire [18:0] t5 = I_gain[5] ? { 6'd0, I_pixel, 5'd0 } : 19'd0;
        wire [18:0] t6 = I_gain[6] ? { 5'd0, I_pixel, 6'd0 } : 19'd0;
        wire [18:0] t7 = I_gain[7] ? { 4'd0, I_pixel, 7'd0 } : 19'd0;
        wire [18:0] t8 = I_gain[8] ? { 3'd0, I_pixel, 8'd0 } : 19'd0;
        wire [18:0] t9 = I_gain[9] ? { 2'd0, I_pixel, 9'd0 } : 19'd0;
        wire [18:0] t10 = I_gain[10] ? { 1'd0, I_pixel, 10'd0 } : 19'd0;
 wire [18:0] a0=t0+t1,a1=t2+t3,a2=t4+t5,a3=t6+t7,a4=t8+t9;
 wire [18:0] b0=a0+a1,b1=a2+a3,b2=a4+t10;
 wire [18:0] c0=b0+b1;
 wire [18:0] rounded=c0+b2+19'd128;
 assign O_pixel=(|rounded[18:16])?8'hff:rounded[15:8];
endmodule

module gain8_lift(input wire I_de,input wire I_enable,input wire [1:0] I_sel,
 input wire [23:0] I_data,input wire [7:0] I_peak,output wire [23:0] O_data);
 wire [10:0] gain;
 wire [23:0] lifted;
 gain8_lift_gain u_gain(.I_peak(I_peak),.I_sel(I_sel),.O_gain(gain));
 gain8_lift_channel r(.I_pixel(I_data[23:16]),.I_gain(gain),.O_pixel(lifted[23:16]));
 gain8_lift_channel g(.I_pixel(I_data[15:8]),.I_gain(gain),.O_pixel(lifted[15:8]));
 gain8_lift_channel b(.I_pixel(I_data[7:0]),.I_gain(gain),.O_pixel(lifted[7:0]));
 assign O_data=(!I_de||!I_enable||I_sel==0)?I_data:lifted;
endmodule
