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
    // Q16 boosts are fully precomputed: remove the serial run-time
    // square/base addition from the pixel path. The mapping is identical.
    function [35:0] f_boost_pair;
        input [7:0] peak;
        begin
            case (peak)
                8'd0: f_boost_pair = {18'd139776, 18'd96512};
                8'd1: f_boost_pair = {18'd138690, 18'd95841};
                8'd2: f_boost_pair = {18'd137608, 18'd95172};
                8'd3: f_boost_pair = {18'd136530, 18'd94505};
                8'd4: f_boost_pair = {18'd135456, 18'd93840};
                8'd5: f_boost_pair = {18'd134386, 18'd93177};
                8'd6: f_boost_pair = {18'd133320, 18'd92516};
                8'd7: f_boost_pair = {18'd132258, 18'd91857};
                8'd8: f_boost_pair = {18'd131200, 18'd91200};
                8'd9: f_boost_pair = {18'd130146, 18'd90545};
                8'd10: f_boost_pair = {18'd129096, 18'd89892};
                8'd11: f_boost_pair = {18'd128050, 18'd89241};
                8'd12: f_boost_pair = {18'd127008, 18'd88592};
                8'd13: f_boost_pair = {18'd125970, 18'd87945};
                8'd14: f_boost_pair = {18'd124936, 18'd87300};
                8'd15: f_boost_pair = {18'd123906, 18'd86657};
                8'd16: f_boost_pair = {18'd122880, 18'd86016};
                8'd17: f_boost_pair = {18'd121858, 18'd85377};
                8'd18: f_boost_pair = {18'd120840, 18'd84740};
                8'd19: f_boost_pair = {18'd119826, 18'd84105};
                8'd20: f_boost_pair = {18'd118816, 18'd83472};
                8'd21: f_boost_pair = {18'd117810, 18'd82841};
                8'd22: f_boost_pair = {18'd116808, 18'd82212};
                8'd23: f_boost_pair = {18'd115810, 18'd81585};
                8'd24: f_boost_pair = {18'd114816, 18'd80960};
                8'd25: f_boost_pair = {18'd113826, 18'd80337};
                8'd26: f_boost_pair = {18'd112840, 18'd79716};
                8'd27: f_boost_pair = {18'd111858, 18'd79097};
                8'd28: f_boost_pair = {18'd110880, 18'd78480};
                8'd29: f_boost_pair = {18'd109906, 18'd77865};
                8'd30: f_boost_pair = {18'd108936, 18'd77252};
                8'd31: f_boost_pair = {18'd107970, 18'd76641};
                8'd32: f_boost_pair = {18'd107008, 18'd76032};
                8'd33: f_boost_pair = {18'd106050, 18'd75425};
                8'd34: f_boost_pair = {18'd105096, 18'd74820};
                8'd35: f_boost_pair = {18'd104146, 18'd74217};
                8'd36: f_boost_pair = {18'd103200, 18'd73616};
                8'd37: f_boost_pair = {18'd102258, 18'd73017};
                8'd38: f_boost_pair = {18'd101320, 18'd72420};
                8'd39: f_boost_pair = {18'd100386, 18'd71825};
                8'd40: f_boost_pair = {18'd99456, 18'd71232};
                8'd41: f_boost_pair = {18'd98530, 18'd70641};
                8'd42: f_boost_pair = {18'd97608, 18'd70052};
                8'd43: f_boost_pair = {18'd96690, 18'd69465};
                8'd44: f_boost_pair = {18'd95776, 18'd68880};
                8'd45: f_boost_pair = {18'd94866, 18'd68297};
                8'd46: f_boost_pair = {18'd93960, 18'd67716};
                8'd47: f_boost_pair = {18'd93058, 18'd67137};
                8'd48: f_boost_pair = {18'd92160, 18'd66560};
                8'd49: f_boost_pair = {18'd91266, 18'd65985};
                8'd50: f_boost_pair = {18'd90376, 18'd65412};
                8'd51: f_boost_pair = {18'd89490, 18'd64841};
                8'd52: f_boost_pair = {18'd88608, 18'd64272};
                8'd53: f_boost_pair = {18'd87730, 18'd63705};
                8'd54: f_boost_pair = {18'd86856, 18'd63140};
                8'd55: f_boost_pair = {18'd85986, 18'd62577};
                8'd56: f_boost_pair = {18'd85120, 18'd62016};
                8'd57: f_boost_pair = {18'd84258, 18'd61457};
                8'd58: f_boost_pair = {18'd83400, 18'd60900};
                8'd59: f_boost_pair = {18'd82546, 18'd60345};
                8'd60: f_boost_pair = {18'd81696, 18'd59792};
                8'd61: f_boost_pair = {18'd80850, 18'd59241};
                8'd62: f_boost_pair = {18'd80008, 18'd58692};
                8'd63: f_boost_pair = {18'd79170, 18'd58145};
                8'd64: f_boost_pair = {18'd78336, 18'd57600};
                8'd65: f_boost_pair = {18'd77506, 18'd57057};
                8'd66: f_boost_pair = {18'd76680, 18'd56516};
                8'd67: f_boost_pair = {18'd75858, 18'd55977};
                8'd68: f_boost_pair = {18'd75040, 18'd55440};
                8'd69: f_boost_pair = {18'd74226, 18'd54905};
                8'd70: f_boost_pair = {18'd73416, 18'd54372};
                8'd71: f_boost_pair = {18'd72610, 18'd53841};
                8'd72: f_boost_pair = {18'd71808, 18'd53312};
                8'd73: f_boost_pair = {18'd71010, 18'd52785};
                8'd74: f_boost_pair = {18'd70216, 18'd52260};
                8'd75: f_boost_pair = {18'd69426, 18'd51737};
                8'd76: f_boost_pair = {18'd68640, 18'd51216};
                8'd77: f_boost_pair = {18'd67858, 18'd50697};
                8'd78: f_boost_pair = {18'd67080, 18'd50180};
                8'd79: f_boost_pair = {18'd66306, 18'd49665};
                8'd80: f_boost_pair = {18'd65536, 18'd49152};
                8'd81: f_boost_pair = {18'd64770, 18'd48641};
                8'd82: f_boost_pair = {18'd64008, 18'd48132};
                8'd83: f_boost_pair = {18'd63250, 18'd47625};
                8'd84: f_boost_pair = {18'd62496, 18'd47120};
                8'd85: f_boost_pair = {18'd61746, 18'd46617};
                8'd86: f_boost_pair = {18'd61000, 18'd46116};
                8'd87: f_boost_pair = {18'd60258, 18'd45617};
                8'd88: f_boost_pair = {18'd59520, 18'd45120};
                8'd89: f_boost_pair = {18'd58786, 18'd44625};
                8'd90: f_boost_pair = {18'd58056, 18'd44132};
                8'd91: f_boost_pair = {18'd57330, 18'd43641};
                8'd92: f_boost_pair = {18'd56608, 18'd43152};
                8'd93: f_boost_pair = {18'd55890, 18'd42665};
                8'd94: f_boost_pair = {18'd55176, 18'd42180};
                8'd95: f_boost_pair = {18'd54466, 18'd41697};
                8'd96: f_boost_pair = {18'd53760, 18'd41216};
                8'd97: f_boost_pair = {18'd53058, 18'd40737};
                8'd98: f_boost_pair = {18'd52360, 18'd40260};
                8'd99: f_boost_pair = {18'd51666, 18'd39785};
                8'd100: f_boost_pair = {18'd50976, 18'd39312};
                8'd101: f_boost_pair = {18'd50290, 18'd38841};
                8'd102: f_boost_pair = {18'd49608, 18'd38372};
                8'd103: f_boost_pair = {18'd48930, 18'd37905};
                8'd104: f_boost_pair = {18'd48256, 18'd37440};
                8'd105: f_boost_pair = {18'd47586, 18'd36977};
                8'd106: f_boost_pair = {18'd46920, 18'd36516};
                8'd107: f_boost_pair = {18'd46258, 18'd36057};
                8'd108: f_boost_pair = {18'd45600, 18'd35600};
                8'd109: f_boost_pair = {18'd44946, 18'd35145};
                8'd110: f_boost_pair = {18'd44296, 18'd34692};
                8'd111: f_boost_pair = {18'd43650, 18'd34241};
                8'd112: f_boost_pair = {18'd43008, 18'd33792};
                8'd113: f_boost_pair = {18'd42370, 18'd33345};
                8'd114: f_boost_pair = {18'd41736, 18'd32900};
                8'd115: f_boost_pair = {18'd41106, 18'd32457};
                8'd116: f_boost_pair = {18'd40480, 18'd32016};
                8'd117: f_boost_pair = {18'd39858, 18'd31577};
                8'd118: f_boost_pair = {18'd39240, 18'd31140};
                8'd119: f_boost_pair = {18'd38626, 18'd30705};
                8'd120: f_boost_pair = {18'd38016, 18'd30272};
                8'd121: f_boost_pair = {18'd37410, 18'd29841};
                8'd122: f_boost_pair = {18'd36808, 18'd29412};
                8'd123: f_boost_pair = {18'd36210, 18'd28985};
                8'd124: f_boost_pair = {18'd35616, 18'd28560};
                8'd125: f_boost_pair = {18'd35026, 18'd28137};
                8'd126: f_boost_pair = {18'd34440, 18'd27716};
                8'd127: f_boost_pair = {18'd33858, 18'd27297};
                8'd128: f_boost_pair = {18'd33280, 18'd26880};
                8'd129: f_boost_pair = {18'd32706, 18'd26465};
                8'd130: f_boost_pair = {18'd32136, 18'd26052};
                8'd131: f_boost_pair = {18'd31570, 18'd25641};
                8'd132: f_boost_pair = {18'd31008, 18'd25232};
                8'd133: f_boost_pair = {18'd30450, 18'd24825};
                8'd134: f_boost_pair = {18'd29896, 18'd24420};
                8'd135: f_boost_pair = {18'd29346, 18'd24017};
                8'd136: f_boost_pair = {18'd28800, 18'd23616};
                8'd137: f_boost_pair = {18'd28258, 18'd23217};
                8'd138: f_boost_pair = {18'd27720, 18'd22820};
                8'd139: f_boost_pair = {18'd27186, 18'd22425};
                8'd140: f_boost_pair = {18'd26656, 18'd22032};
                8'd141: f_boost_pair = {18'd26130, 18'd21641};
                8'd142: f_boost_pair = {18'd25608, 18'd21252};
                8'd143: f_boost_pair = {18'd25090, 18'd20865};
                8'd144: f_boost_pair = {18'd24576, 18'd20480};
                8'd145: f_boost_pair = {18'd24066, 18'd20097};
                8'd146: f_boost_pair = {18'd23560, 18'd19716};
                8'd147: f_boost_pair = {18'd23058, 18'd19337};
                8'd148: f_boost_pair = {18'd22560, 18'd18960};
                8'd149: f_boost_pair = {18'd22066, 18'd18585};
                8'd150: f_boost_pair = {18'd21576, 18'd18212};
                8'd151: f_boost_pair = {18'd21090, 18'd17841};
                8'd152: f_boost_pair = {18'd20608, 18'd17472};
                8'd153: f_boost_pair = {18'd20130, 18'd17105};
                8'd154: f_boost_pair = {18'd19656, 18'd16740};
                8'd155: f_boost_pair = {18'd19186, 18'd16377};
                8'd156: f_boost_pair = {18'd18720, 18'd16016};
                8'd157: f_boost_pair = {18'd18258, 18'd15657};
                8'd158: f_boost_pair = {18'd17800, 18'd15300};
                8'd159: f_boost_pair = {18'd17346, 18'd14945};
                8'd160: f_boost_pair = {18'd16896, 18'd14592};
                8'd161: f_boost_pair = {18'd16450, 18'd14241};
                8'd162: f_boost_pair = {18'd16008, 18'd13892};
                8'd163: f_boost_pair = {18'd15570, 18'd13545};
                8'd164: f_boost_pair = {18'd15136, 18'd13200};
                8'd165: f_boost_pair = {18'd14706, 18'd12857};
                8'd166: f_boost_pair = {18'd14280, 18'd12516};
                8'd167: f_boost_pair = {18'd13858, 18'd12177};
                8'd168: f_boost_pair = {18'd13440, 18'd11840};
                8'd169: f_boost_pair = {18'd13026, 18'd11505};
                8'd170: f_boost_pair = {18'd12616, 18'd11172};
                8'd171: f_boost_pair = {18'd12210, 18'd10841};
                8'd172: f_boost_pair = {18'd11808, 18'd10512};
                8'd173: f_boost_pair = {18'd11410, 18'd10185};
                8'd174: f_boost_pair = {18'd11016, 18'd9860};
                8'd175: f_boost_pair = {18'd10626, 18'd9537};
                8'd176: f_boost_pair = {18'd10240, 18'd9216};
                8'd177: f_boost_pair = {18'd9858, 18'd8897};
                8'd178: f_boost_pair = {18'd9480, 18'd8580};
                8'd179: f_boost_pair = {18'd9106, 18'd8265};
                8'd180: f_boost_pair = {18'd8736, 18'd7952};
                8'd181: f_boost_pair = {18'd8370, 18'd7641};
                8'd182: f_boost_pair = {18'd8008, 18'd7332};
                8'd183: f_boost_pair = {18'd7650, 18'd7025};
                8'd184: f_boost_pair = {18'd7296, 18'd6720};
                8'd185: f_boost_pair = {18'd6946, 18'd6417};
                8'd186: f_boost_pair = {18'd6600, 18'd6116};
                8'd187: f_boost_pair = {18'd6258, 18'd5817};
                8'd188: f_boost_pair = {18'd5920, 18'd5520};
                8'd189: f_boost_pair = {18'd5586, 18'd5225};
                8'd190: f_boost_pair = {18'd5256, 18'd4932};
                8'd191: f_boost_pair = {18'd4930, 18'd4641};
                8'd192: f_boost_pair = {18'd4608, 18'd4352};
                8'd193: f_boost_pair = {18'd4290, 18'd4065};
                8'd194: f_boost_pair = {18'd3976, 18'd3780};
                8'd195: f_boost_pair = {18'd3666, 18'd3497};
                8'd196: f_boost_pair = {18'd3360, 18'd3216};
                8'd197: f_boost_pair = {18'd3058, 18'd2937};
                8'd198: f_boost_pair = {18'd2760, 18'd2660};
                8'd199: f_boost_pair = {18'd2466, 18'd2385};
                8'd200: f_boost_pair = {18'd2176, 18'd2112};
                8'd201: f_boost_pair = {18'd1890, 18'd1841};
                8'd202: f_boost_pair = {18'd1608, 18'd1572};
                8'd203: f_boost_pair = {18'd1330, 18'd1305};
                8'd204: f_boost_pair = {18'd1056, 18'd1040};
                8'd205: f_boost_pair = {18'd786, 18'd777};
                8'd206: f_boost_pair = {18'd520, 18'd516};
                8'd207: f_boost_pair = {18'd258, 18'd257};
                default: f_boost_pair = 36'd0;
            endcase
        end
    endfunction
    wire [35:0] S_boost_pair = f_boost_pair(S_max);
    wire [17:0] S_base_boost = {2'b0, S_room, 8'b0};
    reg [17:0] S_boost;
    always @(*) begin
        case (I_sel)
            3'd1: S_boost = S_base_boost;
            3'd2: S_boost = S_boost_pair[17:0];
            3'd3: S_boost = S_boost_pair[35:18];
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
