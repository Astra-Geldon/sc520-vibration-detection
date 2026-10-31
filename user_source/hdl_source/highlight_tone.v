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
// rounded peak targets. L1 preserves the G12 reference; L2/N1 and L3/N2
// restore mild/medium non-highlight contrast. Peak>=208 equals L1 in all
// three profiles. No RGB9 shoulder, channel LUTs, DSP or frame processing.
module gain8_lift_gain(input wire [7:0] I_peak,input wire [1:0] I_sel,output wire [10:0] O_gain);
 reg [32:0] values;
 always @(*) begin
  case(I_peak)
            8'd0: values=33'h040080100;
            8'd1: values=33'h0be97d2fa;
            8'd2: values=33'h0bd17a2f4;
            8'd3: values=33'h0bb9772c0;
            8'd4: values=33'h0ba574ac0;
            8'd5: values=33'h0b8d57a91;
            8'd6: values=33'h0b755ba99;
            8'd7: values=33'h0b615ea9e;
            8'd8: values=33'h0b4d60aa3;
            8'd9: values=33'h0b3554a8a;
            8'd10: values=33'h0b215628a;
            8'd11: values=33'h0b0d4c277;
            8'd12: values=33'h0af94e279;
            8'd13: values=33'h0ae546a69;
            8'd14: values=33'h0ad148a6c;
            8'd15: values=33'h0abd42a60;
            8'd16: values=33'h0aa944a62;
            8'd17: values=33'h0a993fa58;
            8'd18: values=33'h0a853b24f;
            8'd19: values=33'h0a713d252;
            8'd20: values=33'h0a613924a;
            8'd21: values=33'h0a4d35a44;
            8'd22: values=33'h0a3d3223d;
            8'd23: values=33'h0a2d2f237;
            8'd24: values=33'h0a193123a;
            8'd25: values=33'h0a092ea35;
            8'd26: values=33'h09f92ca32;
            8'd27: values=33'h09e92b231;
            8'd28: values=33'h09d92a231;
            8'd29: values=33'h09c928a30;
            8'd30: values=33'h09b927a2f;
            8'd31: values=33'h09a926a2f;
            8'd32: values=33'h099925a2f;
            8'd33: values=33'h098924a2e;
            8'd34: values=33'h097d2422e;
            8'd35: values=33'h096d1fa25;
            8'd36: values=33'h095d1ea25;
            8'd37: values=33'h094d1e225;
            8'd38: values=33'h09411da26;
            8'd39: values=33'h09311d225;
            8'd40: values=33'h09251921e;
            8'd41: values=33'h091518a1e;
            8'd42: values=33'h090918a1e;
            8'd43: values=33'h08f915218;
            8'd44: values=33'h08ed14a18;
            8'd45: values=33'h08e114a18;
            8'd46: values=33'h08d111212;
            8'd47: values=33'h08c511213;
            8'd48: values=33'h08b911213;
            8'd49: values=33'h08ad0e20e;
            8'd50: values=33'h08a10e20e;
            8'd51: values=33'h08950b209;
            8'd52: values=33'h08890b20a;
            8'd53: values=33'h087908a05;
            8'd54: values=33'h087108a05;
            8'd55: values=33'h086506201;
            8'd56: values=33'h085906201;
            8'd57: values=33'h084d041fd;
            8'd58: values=33'h0841041fe;
            8'd59: values=33'h0835019fa;
            8'd60: values=33'h0828ff9f6;
            8'd61: values=33'h081cff9f7;
            8'd62: values=33'h0814fd9f3;
            8'd63: values=33'h0808fc1ef;
            8'd64: values=33'h07fcfc1f0;
            8'd65: values=33'h07f4fa1ed;
            8'd66: values=33'h07e8f89ea;
            8'd67: values=33'h07dcf89ea;
            8'd68: values=33'h07d4f71e8;
            8'd69: values=33'h07c8f59e5;
            8'd70: values=33'h07c0f59e6;
            8'd71: values=33'h07b4f41e3;
            8'd72: values=33'h07acf31e0;
            8'd73: values=33'h07a0f19dd;
            8'd74: values=33'h0798f01db;
            8'd75: values=33'h0790f01dc;
            8'd76: values=33'h0784ee9da;
            8'd77: values=33'h077ced9d7;
            8'd78: values=33'h0770ec1d4;
            8'd79: values=33'h0768eb1d2;
            8'd80: values=33'h075ce99d0;
            8'd81: values=33'h0758ea1d1;
            8'd82: values=33'h074ce89cf;
            8'd83: values=33'h0744e79cc;
            8'd84: values=33'h073ce69ca;
            8'd85: values=33'h0734e59c9;
            8'd86: values=33'h072ce41c6;
            8'd87: values=33'h0724e31c4;
            8'd88: values=33'h0718e21c2;
            8'd89: values=33'h0710e11c0;
            8'd90: values=33'h0708e11bf;
            8'd91: values=33'h0700e01bd;
            8'd92: values=33'h06f8df1bb;
            8'd93: values=33'h06f0de1b9;
            8'd94: values=33'h06e8dd1b7;
            8'd95: values=33'h06e0dc1b8;
            8'd96: values=33'h06d8db1b6;
            8'd97: values=33'h06d0da1b4;
            8'd98: values=33'h06c8d91b2;
            8'd99: values=33'h06c0d81b0;
            8'd100: values=33'h06b8d71ae;
            8'd101: values=33'h06b4d69ad;
            8'd102: values=33'h06acd59ab;
            8'd103: values=33'h06a4d49a9;
            8'd104: values=33'h069cd39a9;
            8'd105: values=33'h0694d29a8;
            8'd106: values=33'h0690d21a6;
            8'd107: values=33'h0688d11a5;
            8'd108: values=33'h067ccf9a1;
            8'd109: values=33'h0678cf9a0;
            8'd110: values=33'h0670cf19f;
            8'd111: values=33'h066cce19d;
            8'd112: values=33'h0664cd99c;
            8'd113: values=33'h065ccc99c;
            8'd114: values=33'h0658cc19a;
            8'd115: values=33'h0650ca997;
            8'd116: values=33'h0648ca196;
            8'd117: values=33'h0640c9195;
            8'd118: values=33'h063cc8994;
            8'd119: values=33'h0634c8193;
            8'd120: values=33'h062cc698f;
            8'd121: values=33'h0628c618e;
            8'd122: values=33'h0620c598d;
            8'd123: values=33'h061cc518d;
            8'd124: values=33'h0618c498c;
            8'd125: values=33'h0610c3189;
            8'd126: values=33'h0608c2988;
            8'd127: values=33'h0604c2187;
            8'd128: values=33'h05fcc1986;
            8'd129: values=33'h05f8c0183;
            8'd130: values=33'h05f0c0182;
            8'd131: values=33'h05ecbf981;
            8'd132: values=33'h05e8bf180;
            8'd133: values=33'h05e0bd97e;
            8'd134: values=33'h05d8bd17e;
            8'd135: values=33'h05d4bc97d;
            8'd136: values=33'h05ccbb17a;
            8'd137: values=33'h05c8ba979;
            8'd138: values=33'h05c4ba978;
            8'd139: values=33'h05c0ba178;
            8'd140: values=33'h05b8b8975;
            8'd141: values=33'h05b4b8974;
            8'd142: values=33'h05b0b8173;
            8'd143: values=33'h05a8b6971;
            8'd144: values=33'h05a4b6170;
            8'd145: values=33'h05a0b616f;
            8'd146: values=33'h0598b496c;
            8'd147: values=33'h0594b416c;
            8'd148: values=33'h058cb3169;
            8'd149: values=33'h0588b2968;
            8'd150: values=33'h0584b2168;
            8'd151: values=33'h057cb1165;
            8'd152: values=33'h0578b0965;
            8'd153: values=33'h0574b0964;
            8'd154: values=33'h0570af162;
            8'd155: values=33'h056caf161;
            8'd156: values=33'h0564ae15f;
            8'd157: values=33'h0560ad95d;
            8'd158: values=33'h055cad15d;
            8'd159: values=33'h0558ac15a;
            8'd160: values=33'h0554ac15a;
            8'd161: values=33'h054cab158;
            8'd162: values=33'h0548aa957;
            8'd163: values=33'h0544aa957;
            8'd164: values=33'h0540a9155;
            8'd165: values=33'h053ca9154;
            8'd166: values=33'h0534a8152;
            8'd167: values=33'h0530a7951;
            8'd168: values=33'h052ca694f;
            8'd169: values=33'h0528a694f;
            8'd170: values=33'h0528a694e;
            8'd171: values=33'h0520a594c;
            8'd172: values=33'h051ca514c;
            8'd173: values=33'h0518a414a;
            8'd174: values=33'h0514a3949;
            8'd175: values=33'h0510a2947;
            8'd176: values=33'h050ca2947;
            8'd177: values=33'h0504a1945;
            8'd178: values=33'h0504a1144;
            8'd179: values=33'h04fca0942;
            8'd180: values=33'h04f8a0142;
            8'd181: values=33'h04f49f140;
            8'd182: values=33'h04f09f13f;
            8'd183: values=33'h04ec9e13e;
            8'd184: values=33'h04e89e13d;
            8'd185: values=33'h04e49d13b;
            8'd186: values=33'h04e09d13b;
            8'd187: values=33'h04dc9c139;
            8'd188: values=33'h04d89c139;
            8'd189: values=33'h04d49b137;
            8'd190: values=33'h04d09b136;
            8'd191: values=33'h04cc9a134;
            8'd192: values=33'h04c89a134;
            8'd193: values=33'h04c499133;
            8'd194: values=33'h04c499132;
            8'd195: values=33'h04bc98131;
            8'd196: values=33'h04bc97930;
            8'd197: values=33'h04b89712f;
            8'd198: values=33'h04b49692e;
            8'd199: values=33'h04b09612d;
            8'd200: values=33'h04ac9592d;
            8'd201: values=33'h04a89512b;
            8'd202: values=33'h04a49492a;
            8'd203: values=33'h04a094128;
            8'd204: values=33'h049c93927;
            8'd205: values=33'h049c93927;
            8'd206: values=33'h049492925;
            8'd207: values=33'h049492925;
            8'd208: values=33'h049092124;
            8'd209: values=33'h048c91923;
            8'd210: values=33'h048891122;
            8'd211: values=33'h048490921;
            8'd212: values=33'h048090120;
            8'd213: values=33'h047c8f91f;
            8'd214: values=33'h047c8f91f;
            8'd215: values=33'h04788f11e;
            8'd216: values=33'h04788f11e;
            8'd217: values=33'h04708e11c;
            8'd218: values=33'h046c8d91b;
            8'd219: values=33'h046c8d91b;
            8'd220: values=33'h04688d11a;
            8'd221: values=33'h04648c919;
            8'd222: values=33'h04608c118;
            8'd223: values=33'h045c8b917;
            8'd224: values=33'h045c8b917;
            8'd225: values=33'h04588b116;
            8'd226: values=33'h04548a915;
            8'd227: values=33'h04508a114;
            8'd228: values=33'h044c89913;
            8'd229: values=33'h044c89913;
            8'd230: values=33'h044889112;
            8'd231: values=33'h044488911;
            8'd232: values=33'h044088110;
            8'd233: values=33'h043c8790f;
            8'd234: values=33'h043c8790f;
            8'd235: values=33'h04388710e;
            8'd236: values=33'h04348690d;
            8'd237: values=33'h04348690d;
            8'd238: values=33'h04308610c;
            8'd239: values=33'h042c8590b;
            8'd240: values=33'h042c8590b;
            8'd241: values=33'h04288510a;
            8'd242: values=33'h042484909;
            8'd243: values=33'h042084108;
            8'd244: values=33'h041c83907;
            8'd245: values=33'h041c83907;
            8'd246: values=33'h041883106;
            8'd247: values=33'h041482905;
            8'd248: values=33'h041482905;
            8'd249: values=33'h041082104;
            8'd250: values=33'h040c81903;
            8'd251: values=33'h040c81903;
            8'd252: values=33'h040881102;
            8'd253: values=33'h040480901;
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
