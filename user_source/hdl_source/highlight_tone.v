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
    // Constant square ROM: no additional DSP is used for the shoulder.
    // Indexed by the current maximum, so max/ROM and max/subtract run in parallel.
    function [15:0] f_shoulder_square;
        input [7:0] peak;
        begin
            case (peak)
                8'd0: f_shoulder_square = 16'd43264;
                8'd1: f_shoulder_square = 16'd42849;
                8'd2: f_shoulder_square = 16'd42436;
                8'd3: f_shoulder_square = 16'd42025;
                8'd4: f_shoulder_square = 16'd41616;
                8'd5: f_shoulder_square = 16'd41209;
                8'd6: f_shoulder_square = 16'd40804;
                8'd7: f_shoulder_square = 16'd40401;
                8'd8: f_shoulder_square = 16'd40000;
                8'd9: f_shoulder_square = 16'd39601;
                8'd10: f_shoulder_square = 16'd39204;
                8'd11: f_shoulder_square = 16'd38809;
                8'd12: f_shoulder_square = 16'd38416;
                8'd13: f_shoulder_square = 16'd38025;
                8'd14: f_shoulder_square = 16'd37636;
                8'd15: f_shoulder_square = 16'd37249;
                8'd16: f_shoulder_square = 16'd36864;
                8'd17: f_shoulder_square = 16'd36481;
                8'd18: f_shoulder_square = 16'd36100;
                8'd19: f_shoulder_square = 16'd35721;
                8'd20: f_shoulder_square = 16'd35344;
                8'd21: f_shoulder_square = 16'd34969;
                8'd22: f_shoulder_square = 16'd34596;
                8'd23: f_shoulder_square = 16'd34225;
                8'd24: f_shoulder_square = 16'd33856;
                8'd25: f_shoulder_square = 16'd33489;
                8'd26: f_shoulder_square = 16'd33124;
                8'd27: f_shoulder_square = 16'd32761;
                8'd28: f_shoulder_square = 16'd32400;
                8'd29: f_shoulder_square = 16'd32041;
                8'd30: f_shoulder_square = 16'd31684;
                8'd31: f_shoulder_square = 16'd31329;
                8'd32: f_shoulder_square = 16'd30976;
                8'd33: f_shoulder_square = 16'd30625;
                8'd34: f_shoulder_square = 16'd30276;
                8'd35: f_shoulder_square = 16'd29929;
                8'd36: f_shoulder_square = 16'd29584;
                8'd37: f_shoulder_square = 16'd29241;
                8'd38: f_shoulder_square = 16'd28900;
                8'd39: f_shoulder_square = 16'd28561;
                8'd40: f_shoulder_square = 16'd28224;
                8'd41: f_shoulder_square = 16'd27889;
                8'd42: f_shoulder_square = 16'd27556;
                8'd43: f_shoulder_square = 16'd27225;
                8'd44: f_shoulder_square = 16'd26896;
                8'd45: f_shoulder_square = 16'd26569;
                8'd46: f_shoulder_square = 16'd26244;
                8'd47: f_shoulder_square = 16'd25921;
                8'd48: f_shoulder_square = 16'd25600;
                8'd49: f_shoulder_square = 16'd25281;
                8'd50: f_shoulder_square = 16'd24964;
                8'd51: f_shoulder_square = 16'd24649;
                8'd52: f_shoulder_square = 16'd24336;
                8'd53: f_shoulder_square = 16'd24025;
                8'd54: f_shoulder_square = 16'd23716;
                8'd55: f_shoulder_square = 16'd23409;
                8'd56: f_shoulder_square = 16'd23104;
                8'd57: f_shoulder_square = 16'd22801;
                8'd58: f_shoulder_square = 16'd22500;
                8'd59: f_shoulder_square = 16'd22201;
                8'd60: f_shoulder_square = 16'd21904;
                8'd61: f_shoulder_square = 16'd21609;
                8'd62: f_shoulder_square = 16'd21316;
                8'd63: f_shoulder_square = 16'd21025;
                8'd64: f_shoulder_square = 16'd20736;
                8'd65: f_shoulder_square = 16'd20449;
                8'd66: f_shoulder_square = 16'd20164;
                8'd67: f_shoulder_square = 16'd19881;
                8'd68: f_shoulder_square = 16'd19600;
                8'd69: f_shoulder_square = 16'd19321;
                8'd70: f_shoulder_square = 16'd19044;
                8'd71: f_shoulder_square = 16'd18769;
                8'd72: f_shoulder_square = 16'd18496;
                8'd73: f_shoulder_square = 16'd18225;
                8'd74: f_shoulder_square = 16'd17956;
                8'd75: f_shoulder_square = 16'd17689;
                8'd76: f_shoulder_square = 16'd17424;
                8'd77: f_shoulder_square = 16'd17161;
                8'd78: f_shoulder_square = 16'd16900;
                8'd79: f_shoulder_square = 16'd16641;
                8'd80: f_shoulder_square = 16'd16384;
                8'd81: f_shoulder_square = 16'd16129;
                8'd82: f_shoulder_square = 16'd15876;
                8'd83: f_shoulder_square = 16'd15625;
                8'd84: f_shoulder_square = 16'd15376;
                8'd85: f_shoulder_square = 16'd15129;
                8'd86: f_shoulder_square = 16'd14884;
                8'd87: f_shoulder_square = 16'd14641;
                8'd88: f_shoulder_square = 16'd14400;
                8'd89: f_shoulder_square = 16'd14161;
                8'd90: f_shoulder_square = 16'd13924;
                8'd91: f_shoulder_square = 16'd13689;
                8'd92: f_shoulder_square = 16'd13456;
                8'd93: f_shoulder_square = 16'd13225;
                8'd94: f_shoulder_square = 16'd12996;
                8'd95: f_shoulder_square = 16'd12769;
                8'd96: f_shoulder_square = 16'd12544;
                8'd97: f_shoulder_square = 16'd12321;
                8'd98: f_shoulder_square = 16'd12100;
                8'd99: f_shoulder_square = 16'd11881;
                8'd100: f_shoulder_square = 16'd11664;
                8'd101: f_shoulder_square = 16'd11449;
                8'd102: f_shoulder_square = 16'd11236;
                8'd103: f_shoulder_square = 16'd11025;
                8'd104: f_shoulder_square = 16'd10816;
                8'd105: f_shoulder_square = 16'd10609;
                8'd106: f_shoulder_square = 16'd10404;
                8'd107: f_shoulder_square = 16'd10201;
                8'd108: f_shoulder_square = 16'd10000;
                8'd109: f_shoulder_square = 16'd9801;
                8'd110: f_shoulder_square = 16'd9604;
                8'd111: f_shoulder_square = 16'd9409;
                8'd112: f_shoulder_square = 16'd9216;
                8'd113: f_shoulder_square = 16'd9025;
                8'd114: f_shoulder_square = 16'd8836;
                8'd115: f_shoulder_square = 16'd8649;
                8'd116: f_shoulder_square = 16'd8464;
                8'd117: f_shoulder_square = 16'd8281;
                8'd118: f_shoulder_square = 16'd8100;
                8'd119: f_shoulder_square = 16'd7921;
                8'd120: f_shoulder_square = 16'd7744;
                8'd121: f_shoulder_square = 16'd7569;
                8'd122: f_shoulder_square = 16'd7396;
                8'd123: f_shoulder_square = 16'd7225;
                8'd124: f_shoulder_square = 16'd7056;
                8'd125: f_shoulder_square = 16'd6889;
                8'd126: f_shoulder_square = 16'd6724;
                8'd127: f_shoulder_square = 16'd6561;
                8'd128: f_shoulder_square = 16'd6400;
                8'd129: f_shoulder_square = 16'd6241;
                8'd130: f_shoulder_square = 16'd6084;
                8'd131: f_shoulder_square = 16'd5929;
                8'd132: f_shoulder_square = 16'd5776;
                8'd133: f_shoulder_square = 16'd5625;
                8'd134: f_shoulder_square = 16'd5476;
                8'd135: f_shoulder_square = 16'd5329;
                8'd136: f_shoulder_square = 16'd5184;
                8'd137: f_shoulder_square = 16'd5041;
                8'd138: f_shoulder_square = 16'd4900;
                8'd139: f_shoulder_square = 16'd4761;
                8'd140: f_shoulder_square = 16'd4624;
                8'd141: f_shoulder_square = 16'd4489;
                8'd142: f_shoulder_square = 16'd4356;
                8'd143: f_shoulder_square = 16'd4225;
                8'd144: f_shoulder_square = 16'd4096;
                8'd145: f_shoulder_square = 16'd3969;
                8'd146: f_shoulder_square = 16'd3844;
                8'd147: f_shoulder_square = 16'd3721;
                8'd148: f_shoulder_square = 16'd3600;
                8'd149: f_shoulder_square = 16'd3481;
                8'd150: f_shoulder_square = 16'd3364;
                8'd151: f_shoulder_square = 16'd3249;
                8'd152: f_shoulder_square = 16'd3136;
                8'd153: f_shoulder_square = 16'd3025;
                8'd154: f_shoulder_square = 16'd2916;
                8'd155: f_shoulder_square = 16'd2809;
                8'd156: f_shoulder_square = 16'd2704;
                8'd157: f_shoulder_square = 16'd2601;
                8'd158: f_shoulder_square = 16'd2500;
                8'd159: f_shoulder_square = 16'd2401;
                8'd160: f_shoulder_square = 16'd2304;
                8'd161: f_shoulder_square = 16'd2209;
                8'd162: f_shoulder_square = 16'd2116;
                8'd163: f_shoulder_square = 16'd2025;
                8'd164: f_shoulder_square = 16'd1936;
                8'd165: f_shoulder_square = 16'd1849;
                8'd166: f_shoulder_square = 16'd1764;
                8'd167: f_shoulder_square = 16'd1681;
                8'd168: f_shoulder_square = 16'd1600;
                8'd169: f_shoulder_square = 16'd1521;
                8'd170: f_shoulder_square = 16'd1444;
                8'd171: f_shoulder_square = 16'd1369;
                8'd172: f_shoulder_square = 16'd1296;
                8'd173: f_shoulder_square = 16'd1225;
                8'd174: f_shoulder_square = 16'd1156;
                8'd175: f_shoulder_square = 16'd1089;
                8'd176: f_shoulder_square = 16'd1024;
                8'd177: f_shoulder_square = 16'd961;
                8'd178: f_shoulder_square = 16'd900;
                8'd179: f_shoulder_square = 16'd841;
                8'd180: f_shoulder_square = 16'd784;
                8'd181: f_shoulder_square = 16'd729;
                8'd182: f_shoulder_square = 16'd676;
                8'd183: f_shoulder_square = 16'd625;
                8'd184: f_shoulder_square = 16'd576;
                8'd185: f_shoulder_square = 16'd529;
                8'd186: f_shoulder_square = 16'd484;
                8'd187: f_shoulder_square = 16'd441;
                8'd188: f_shoulder_square = 16'd400;
                8'd189: f_shoulder_square = 16'd361;
                8'd190: f_shoulder_square = 16'd324;
                8'd191: f_shoulder_square = 16'd289;
                8'd192: f_shoulder_square = 16'd256;
                8'd193: f_shoulder_square = 16'd225;
                8'd194: f_shoulder_square = 16'd196;
                8'd195: f_shoulder_square = 16'd169;
                8'd196: f_shoulder_square = 16'd144;
                8'd197: f_shoulder_square = 16'd121;
                8'd198: f_shoulder_square = 16'd100;
                8'd199: f_shoulder_square = 16'd81;
                8'd200: f_shoulder_square = 16'd64;
                8'd201: f_shoulder_square = 16'd49;
                8'd202: f_shoulder_square = 16'd36;
                8'd203: f_shoulder_square = 16'd25;
                8'd204: f_shoulder_square = 16'd16;
                8'd205: f_shoulder_square = 16'd9;
                8'd206: f_shoulder_square = 16'd4;
                8'd207: f_shoulder_square = 16'd1;
                default: f_shoulder_square = 16'd0;
            endcase
        end
    endfunction
    wire [15:0] S_square = f_shoulder_square(S_max);
    // Q16 common boost; C1 is bit-exact old C3. C2/C3 add a stronger
    // cubic shoulder without changing any pixel whose maximum is >=208.
    wire [17:0] S_base_boost = {2'b0, S_room, 8'b0};
    reg [17:0] S_boost;
    always @(*) begin
        case (I_sel)
            3'd1: S_boost = S_base_boost;
            3'd2: S_boost = S_base_boost + {2'b0, S_square};
            3'd3: S_boost = S_base_boost + {1'b0, S_square, 1'b0};
            default: S_boost = 18'd0;
        endcase
    end
    wire [25:0] S_pr = S_r * S_boost;
    wire [25:0] S_pg = S_g * S_boost;
    wire [25:0] S_pb = S_b * S_boost;

    function [7:0] f_lift;
        input [7:0] value;
        input [25:0] product;
        reg [25:0] rounded;
        reg [10:0] lifted;
        begin
            rounded = product + 26'd32768;
            lifted = {3'b0, value} + {1'b0, rounded[25:16]};
            f_lift = (|lifted[10:8]) ? 8'hff : lifted[7:0];
        end
    endfunction
    wire [23:0] S_lifted = {f_lift(S_r, S_pr),
                            f_lift(S_g, S_pg),
                            f_lift(S_b, S_pb)};
    assign O_data = (!I_de || !I_enable) ? I_data :
                    (I_sel == 3'd4) ? S_marker :
                    O_mask ? I_data : S_lifted;
endmodule
