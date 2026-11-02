// 融合版唯一补亮路径：原N1曲线只作为最大包络，实际补偿由曝光与参考亮度共同约束。
module fusion_n1_gain(input wire [7:0] I_peak, output reg [10:0] O_gain);
    always @(*) begin
        case (I_peak)
            8'd0: O_gain = 11'd256;
            8'd1: O_gain = 11'd512;
            8'd2: O_gain = 11'd512;
            8'd3: O_gain = 11'd427;
            8'd4: O_gain = 11'd448;
            8'd5: O_gain = 11'd461;
            8'd6: O_gain = 11'd469;
            8'd7: O_gain = 11'd439;
            8'd8: O_gain = 11'd448;
            8'd9: O_gain = 11'd455;
            8'd10: O_gain = 11'd461;
            8'd11: O_gain = 11'd442;
            8'd12: O_gain = 11'd448;
            8'd13: O_gain = 11'd453;
            8'd14: O_gain = 11'd457;
            8'd15: O_gain = 11'd444;
            8'd16: O_gain = 11'd448;
            8'd17: O_gain = 11'd452;
            8'd18: O_gain = 11'd441;
            8'd19: O_gain = 11'd445;
            8'd20: O_gain = 11'd435;
            8'd21: O_gain = 11'd439;
            8'd22: O_gain = 11'd431;
            8'd23: O_gain = 11'd434;
            8'd24: O_gain = 11'd427;
            8'd25: O_gain = 11'd430;
            8'd26: O_gain = 11'd423;
            8'd27: O_gain = 11'd427;
            8'd28: O_gain = 11'd421;
            8'd29: O_gain = 11'd424;
            8'd30: O_gain = 11'd418;
            8'd31: O_gain = 11'd421;
            8'd32: O_gain = 11'd416;
            8'd33: O_gain = 11'd419;
            8'd34: O_gain = 11'd414;
            8'd35: O_gain = 11'd417;
            8'd36: O_gain = 11'd412;
            8'd37: O_gain = 11'd415;
            8'd38: O_gain = 11'd411;
            8'd39: O_gain = 11'd414;
            8'd40: O_gain = 11'd410;
            8'd41: O_gain = 11'd412;
            8'd42: O_gain = 11'd408;
            8'd43: O_gain = 11'd411;
            8'd44: O_gain = 11'd407;
            8'd45: O_gain = 11'd410;
            8'd46: O_gain = 11'd406;
            8'd47: O_gain = 11'd409;
            8'd48: O_gain = 11'd405;
            8'd49: O_gain = 11'd408;
            8'd50: O_gain = 11'd404;
            8'd51: O_gain = 11'd407;
            8'd52: O_gain = 11'd404;
            8'd53: O_gain = 11'd406;
            8'd54: O_gain = 11'd403;
            8'd55: O_gain = 11'd405;
            8'd56: O_gain = 11'd402;
            8'd57: O_gain = 11'd404;
            8'd58: O_gain = 11'd402;
            8'd59: O_gain = 11'd404;
            8'd60: O_gain = 11'd401;
            8'd61: O_gain = 11'd403;
            8'd62: O_gain = 11'd401;
            8'd63: O_gain = 11'd402;
            8'd64: O_gain = 11'd400;
            8'd65: O_gain = 11'd398;
            8'd66: O_gain = 11'd396;
            8'd67: O_gain = 11'd394;
            8'd68: O_gain = 11'd395;
            8'd69: O_gain = 11'd393;
            8'd70: O_gain = 11'd391;
            8'd71: O_gain = 11'd389;
            8'd72: O_gain = 11'd388;
            8'd73: O_gain = 11'd386;
            8'd74: O_gain = 11'd384;
            8'd75: O_gain = 11'd382;
            8'd76: O_gain = 11'd384;
            8'd77: O_gain = 11'd382;
            8'd78: O_gain = 11'd381;
            8'd79: O_gain = 11'd379;
            8'd80: O_gain = 11'd378;
            8'd81: O_gain = 11'd376;
            8'd82: O_gain = 11'd375;
            8'd83: O_gain = 11'd373;
            8'd84: O_gain = 11'd375;
            8'd85: O_gain = 11'd373;
            8'd86: O_gain = 11'd372;
            8'd87: O_gain = 11'd371;
            8'd88: O_gain = 11'd369;
            8'd89: O_gain = 11'd368;
            8'd90: O_gain = 11'd367;
            8'd91: O_gain = 11'd366;
            8'd92: O_gain = 11'd367;
            8'd93: O_gain = 11'd366;
            8'd94: O_gain = 11'd365;
            8'd95: O_gain = 11'd364;
            8'd96: O_gain = 11'd363;
            8'd97: O_gain = 11'd362;
            8'd98: O_gain = 11'd360;
            8'd99: O_gain = 11'd357;
            8'd100: O_gain = 11'd356;
            8'd101: O_gain = 11'd355;
            8'd102: O_gain = 11'd354;
            8'd103: O_gain = 11'd350;
            8'd104: O_gain = 11'd350;
            8'd105: O_gain = 11'd349;
            8'd106: O_gain = 11'd348;
            8'd107: O_gain = 11'd345;
            8'd108: O_gain = 11'd344;
            8'd109: O_gain = 11'd343;
            8'd110: O_gain = 11'd342;
            8'd111: O_gain = 11'd339;
            8'd112: O_gain = 11'd338;
            8'd113: O_gain = 11'd338;
            8'd114: O_gain = 11'd337;
            8'd115: O_gain = 11'd334;
            8'd116: O_gain = 11'd333;
            8'd117: O_gain = 11'd333;
            8'd118: O_gain = 11'd332;
            8'd119: O_gain = 11'd329;
            8'd120: O_gain = 11'd329;
            8'd121: O_gain = 11'd328;
            8'd122: O_gain = 11'd327;
            8'd123: O_gain = 11'd325;
            8'd124: O_gain = 11'd324;
            8'd125: O_gain = 11'd324;
            8'd126: O_gain = 11'd323;
            8'd127: O_gain = 11'd321;
            8'd128: O_gain = 11'd320;
            8'd129: O_gain = 11'd320;
            8'd130: O_gain = 11'd317;
            8'd131: O_gain = 11'd317;
            8'd132: O_gain = 11'd314;
            8'd133: O_gain = 11'd314;
            8'd134: O_gain = 11'd311;
            8'd135: O_gain = 11'd311;
            8'd136: O_gain = 11'd309;
            8'd137: O_gain = 11'd308;
            8'd138: O_gain = 11'd306;
            8'd139: O_gain = 11'd306;
            8'd140: O_gain = 11'd304;
            8'd141: O_gain = 11'd303;
            8'd142: O_gain = 11'd301;
            8'd143: O_gain = 11'd301;
            8'd144: O_gain = 11'd299;
            8'd145: O_gain = 11'd298;
            8'd146: O_gain = 11'd296;
            8'd147: O_gain = 11'd296;
            8'd148: O_gain = 11'd294;
            8'd149: O_gain = 11'd294;
            8'd150: O_gain = 11'd292;
            8'd151: O_gain = 11'd292;
            8'd152: O_gain = 11'd290;
            8'd153: O_gain = 11'd289;
            8'd154: O_gain = 11'd288;
            8'd155: O_gain = 11'd287;
            8'd156: O_gain = 11'd286;
            8'd157: O_gain = 11'd285;
            8'd158: O_gain = 11'd284;
            8'd159: O_gain = 11'd283;
            8'd160: O_gain = 11'd282;
            8'd161: O_gain = 11'd281;
            8'd162: O_gain = 11'd280;
            8'd163: O_gain = 11'd280;
            8'd164: O_gain = 11'd278;
            8'd165: O_gain = 11'd278;
            8'd166: O_gain = 11'd276;
            8'd167: O_gain = 11'd276;
            8'd168: O_gain = 11'd274;
            8'd169: O_gain = 11'd274;
            8'd170: O_gain = 11'd273;
            8'd171: O_gain = 11'd272;
            8'd172: O_gain = 11'd271;
            8'd173: O_gain = 11'd271;
            8'd174: O_gain = 11'd269;
            8'd175: O_gain = 11'd269;
            8'd176: O_gain = 11'd268;
            8'd177: O_gain = 11'd268;
            8'd178: O_gain = 11'd266;
            8'd179: O_gain = 11'd266;
            8'd180: O_gain = 11'd265;
            8'd181: O_gain = 11'd264;
            8'd182: O_gain = 11'd263;
            8'd183: O_gain = 11'd263;
            8'd184: O_gain = 11'd262;
            8'd185: O_gain = 11'd262;
            8'd186: O_gain = 11'd260;
            8'd187: O_gain = 11'd260;
            8'd188: O_gain = 11'd259;
            8'd189: O_gain = 11'd259;
            8'd190: O_gain = 11'd257;
            8'd191: O_gain = 11'd257;
            8'd192: O_gain = 11'd256;
            8'd193: O_gain = 11'd256;
            8'd194: O_gain = 11'd256;
            8'd195: O_gain = 11'd256;
            8'd196: O_gain = 11'd256;
            8'd197: O_gain = 11'd256;
            8'd198: O_gain = 11'd256;
            8'd199: O_gain = 11'd256;
            8'd200: O_gain = 11'd256;
            8'd201: O_gain = 11'd256;
            8'd202: O_gain = 11'd256;
            8'd203: O_gain = 11'd256;
            8'd204: O_gain = 11'd256;
            8'd205: O_gain = 11'd256;
            8'd206: O_gain = 11'd256;
            8'd207: O_gain = 11'd256;
            8'd208: O_gain = 11'd256;
            8'd209: O_gain = 11'd256;
            8'd210: O_gain = 11'd256;
            8'd211: O_gain = 11'd256;
            8'd212: O_gain = 11'd256;
            8'd213: O_gain = 11'd256;
            8'd214: O_gain = 11'd256;
            8'd215: O_gain = 11'd256;
            8'd216: O_gain = 11'd256;
            8'd217: O_gain = 11'd256;
            8'd218: O_gain = 11'd256;
            8'd219: O_gain = 11'd256;
            8'd220: O_gain = 11'd256;
            8'd221: O_gain = 11'd256;
            8'd222: O_gain = 11'd256;
            8'd223: O_gain = 11'd256;
            8'd224: O_gain = 11'd256;
            8'd225: O_gain = 11'd256;
            8'd226: O_gain = 11'd256;
            8'd227: O_gain = 11'd256;
            8'd228: O_gain = 11'd256;
            8'd229: O_gain = 11'd256;
            8'd230: O_gain = 11'd256;
            8'd231: O_gain = 11'd256;
            8'd232: O_gain = 11'd256;
            8'd233: O_gain = 11'd256;
            8'd234: O_gain = 11'd256;
            8'd235: O_gain = 11'd256;
            8'd236: O_gain = 11'd256;
            8'd237: O_gain = 11'd256;
            8'd238: O_gain = 11'd256;
            8'd239: O_gain = 11'd256;
            8'd240: O_gain = 11'd256;
            8'd241: O_gain = 11'd256;
            8'd242: O_gain = 11'd256;
            8'd243: O_gain = 11'd256;
            8'd244: O_gain = 11'd256;
            8'd245: O_gain = 11'd256;
            8'd246: O_gain = 11'd256;
            8'd247: O_gain = 11'd256;
            8'd248: O_gain = 11'd256;
            8'd249: O_gain = 11'd256;
            8'd250: O_gain = 11'd256;
            8'd251: O_gain = 11'd256;
            8'd252: O_gain = 11'd256;
            8'd253: O_gain = 11'd256;
            8'd254: O_gain = 11'd256;
            8'd255: O_gain = 11'd256;
            default: O_gain = 11'd256;
        endcase
    end
endmodule

// 该组合包络复用已经验收的N1增益表及RGB公共增益，不增加像素拍数。
module fusion_n1_envelope(
    input wire I_de, input wire I_enable,
    input wire [23:0] I_data, input wire [7:0] I_peak,
    output wire [23:0] O_data
);
    wire [10:0] gain;
    wire [23:0] lifted;
    fusion_n1_gain u_gain(.I_peak(I_peak), .O_gain(gain));
    fusion_n1_channel u_r(.I_pixel(I_data[23:16]), .I_gain(gain), .O_pixel(lifted[23:16]));
    fusion_n1_channel u_g(.I_pixel(I_data[15:8]), .I_gain(gain), .O_pixel(lifted[15:8]));
    fusion_n1_channel u_b(.I_pixel(I_data[7:0]), .I_gain(gain), .O_pixel(lifted[7:0]));
    assign O_data = (!I_de || !I_enable) ? I_data : lifted;
endmodule

// 公共混合强度作用于RGB三通道，0档逐位旁路，16档逐位等于包络。
(* dsp_style = "no" *)
module fusion_lift_blend(
    input wire I_de, input wire I_enable,
    input wire [23:0] I_original, input wire [23:0] I_envelope,
    input wire [4:0] I_strength, output wire [23:0] O_data
);
    function [7:0] blend_channel;
        input [7:0] original_pixel, envelope_pixel;
        input [4:0] strength;
        reg [7:0] delta;
        reg [12:0] p0, p1, p2, p3, p4;
        reg [12:0] a0, a1, product;
        reg [8:0] result;
        begin
            // 包络保证不低于原值；防御性处理异常包络，避免无符号下溢。
            delta = (envelope_pixel >= original_pixel) ? envelope_pixel-original_pixel : 8'd0;
            p0 = strength[0] ? {5'd0, delta} : 13'd0;
            p1 = strength[1] ? {4'd0, delta, 1'd0} : 13'd0;
            p2 = strength[2] ? {3'd0, delta, 2'd0} : 13'd0;
            p3 = strength[3] ? {2'd0, delta, 3'd0} : 13'd0;
            p4 = strength[4] ? {1'd0, delta, 4'd0} : 13'd0;
            a0 = p0+p1;
            a1 = p2+p3;
            product = a0+a1+p4+13'd8;
            result = {1'b0, original_pixel}+{1'b0, product[11:4]};
            blend_channel = result[8] ? 8'hff : result[7:0];
        end
    endfunction
    wire [4:0] bounded_strength = (I_strength > 5'd16) ? 5'd16 : I_strength;
    wire [23:0] lifted = {
        blend_channel(I_original[23:16], I_envelope[23:16], bounded_strength),
        blend_channel(I_original[15:8], I_envelope[15:8], bounded_strength),
        blend_channel(I_original[7:0], I_envelope[7:0], bounded_strength)
    };
    assign O_data = (!I_de || !I_enable || bounded_strength == 0) ? I_original : lifted;
endmodule

// 4×3分区只判断场景，不为分区分别施加增益，避免接缝。
// 只用生效且整帧稳定的E：触发时记录中间调平均亮度，之后最多恢复到该水平。
(* dsp_style = "no" *)
module fusion_lift_control #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer EXPECTED_SAMPLES = 14400,
    parameter integer SAMPLE_LOG2 = 6
) (
    input wire I_clk, input wire I_rst_n,
    input wire I_vs, input wire I_de, input wire I_enable,
    input wire [23:0] I_data, input wire [23:0] I_envelope_data,
    input wire [15:0] I_exposure, input wire I_exposure_valid,
    output reg [4:0] O_strength,
    output reg [15:0] O_reference_exposure,
    output reg [9:0] O_reference_luma,
    output reg O_triggered
);
    localparam integer COUNT_W = (EXPECTED_SAMPLES < 2) ? 1 : $clog2(EXPECTED_SAMPLES+1);
    localparam integer REGION_SUM_W = 18;
    localparam integer MID_SUM_W = (EXPECTED_SAMPLES < 2) ? 6 : $clog2(EXPECTED_SAMPLES*63+1);
    localparam integer ACC_W = MID_SUM_W+4;
    localparam integer PHASE_W = (SAMPLE_LOG2 < 1) ? 1 : SAMPLE_LOG2;
    localparam integer REGION_SAMPLES = (EXPECTED_SAMPLES < 12) ? 1 : EXPECTED_SAMPLES/12;
    // 第一轮触发不能等到高光已经让AE先改E；适度放宽进入门限，保留更宽的退出迟滞。
    localparam integer ENTER_BRIGHT = (EXPECTED_SAMPLES+99)/100;
    localparam integer HOLD_BRIGHT = (EXPECTED_SAMPLES+99)/100;
    localparam integer ENTER_SHADOW = (EXPECTED_SAMPLES*15+99)/100;
    localparam integer HOLD_SHADOW = (EXPECTED_SAMPLES*15+99)/100;
    localparam integer H4 = H_ACTIVE/4;
    localparam integer V3 = V_ACTIVE/3;
    // 曝光连续稳定若干完整帧后，补亮才重新计算目标；退出必须再稳定约0.75秒。
    localparam integer EXPOSURE_STABLE_FRAMES = 3;
    localparam integer EXPOSURE_EXIT_STABLE_FRAMES = 45;
    localparam integer EXPOSURE_CAP_MARGIN = 4;
    localparam integer EXPOSURE_TOLERANCE = 32;
    localparam [2:0] S_IDLE=0, S_REFERENCE_DIV=1, S_REFERENCE_MUL=2,
                     S_EXPOSURE_CAP=3, S_LUMA_SEARCH=4;

    reg vs_d, active, overflow, frame_exposure_good;
    reg [11:0] x;
    reg [10:0] y;
    reg [PHASE_W-1:0] phase;
    reg [15:0] frame_exposure;
    reg [COUNT_W-1:0] sample_count, bright_count, shadow_count, mid_count;
    reg [MID_SUM_W-1:0] raw_sum, envelope_sum;
    reg [REGION_SUM_W-1:0] region_sum[0:11];
    integer i;
    wire vs_start = I_vs && !vs_d;
    wire exposure_good = I_exposure_valid && I_exposure >= 16'd128 && I_exposure <= 16'd1991;
    wire frame_good = active && !overflow && frame_exposure_good && exposure_good &&
        I_exposure == frame_exposure && sample_count == EXPECTED_SAMPLES && x == 0 && y == V_ACTIVE;
    wire [9:0] luma_sum = {2'd0,I_data[23:16]}+{1'd0,I_data[15:8],1'b0}+{2'd0,I_data[7:0]};
    wire [9:0] envelope_luma_sum = {2'd0,I_envelope_data[23:16]}+
        {1'd0,I_envelope_data[15:8],1'b0}+{2'd0,I_envelope_data[7:0]};
    wire [5:0] luma6 = luma_sum[9:4];
    wire [5:0] envelope_luma6 = envelope_luma_sum[9:4];
    wire [7:0] peak_rg = (I_data[23:16] > I_data[15:8]) ? I_data[23:16] : I_data[15:8];
    wire [7:0] peak = (peak_rg > I_data[7:0]) ? peak_rg : I_data[7:0];
    wire sample_now = I_de && y < V_ACTIVE && (SAMPLE_LOG2 == 0 || phase == 0) &&
        sample_count < EXPECTED_SAMPLES;
    wire [1:0] col = (x < H4) ? 2'd0 : ((x < H4*2) ? 2'd1 : ((x < H4*3) ? 2'd2 : 2'd3));
    wire [1:0] row = (y < V3) ? 2'd0 : ((y < V3*2) ? 2'd1 : 2'd2);
    wire [3:0] region_index = {row,2'b00}+col;

    wire [REGION_SUM_W-1:0] min01=(region_sum[0]<region_sum[1])?region_sum[0]:region_sum[1];
    wire [REGION_SUM_W-1:0] min23=(region_sum[2]<region_sum[3])?region_sum[2]:region_sum[3];
    wire [REGION_SUM_W-1:0] min45=(region_sum[4]<region_sum[5])?region_sum[4]:region_sum[5];
    wire [REGION_SUM_W-1:0] min67=(region_sum[6]<region_sum[7])?region_sum[6]:region_sum[7];
    wire [REGION_SUM_W-1:0] min89=(region_sum[8]<region_sum[9])?region_sum[8]:region_sum[9];
    wire [REGION_SUM_W-1:0] minAB=(region_sum[10]<region_sum[11])?region_sum[10]:region_sum[11];
    wire [REGION_SUM_W-1:0] max01=(region_sum[0]>region_sum[1])?region_sum[0]:region_sum[1];
    wire [REGION_SUM_W-1:0] max23=(region_sum[2]>region_sum[3])?region_sum[2]:region_sum[3];
    wire [REGION_SUM_W-1:0] max45=(region_sum[4]>region_sum[5])?region_sum[4]:region_sum[5];
    wire [REGION_SUM_W-1:0] max67=(region_sum[6]>region_sum[7])?region_sum[6]:region_sum[7];
    wire [REGION_SUM_W-1:0] max89=(region_sum[8]>region_sum[9])?region_sum[8]:region_sum[9];
    wire [REGION_SUM_W-1:0] maxAB=(region_sum[10]>region_sum[11])?region_sum[10]:region_sum[11];
    reg [REGION_SUM_W-1:0] min0123,min4567,min89AB,max0123,max4567,max89AB;
    wire [REGION_SUM_W-1:0] min_first=(min0123<min4567)?min0123:min4567;
    wire [REGION_SUM_W-1:0] max_first=(max0123>max4567)?max0123:max4567;
    reg [REGION_SUM_W-1:0] min_sum,max_sum,range_sum;
    reg [1:0] evaluate_wait;
    reg pending_good;
    reg [COUNT_W-1:0] pending_bright,pending_shadow,pending_mid;
    reg [MID_SUM_W-1:0] pending_raw,pending_envelope;
    reg [15:0] pending_exposure;
    wire enter_condition = range_sum >= 16*REGION_SAMPLES &&
        pending_bright >= ENTER_BRIGHT && pending_shadow >= ENTER_SHADOW;
    wire hold_condition = range_sum >= 14*REGION_SAMPLES &&
        pending_bright >= HOLD_BRIGHT && pending_shadow >= HOLD_SHADOW;
    reg [1:0] enter_wait;
    reg [2:0] exit_wait;
    reg [15:0] exposure_stable_value;
    reg [5:0] exposure_stable_count;
    reg baseline_valid;
    reg [15:0] baseline_exposure;
    reg [COUNT_W-1:0] baseline_mid;
    reg [MID_SUM_W-1:0] baseline_raw;
    reg [4:0] target_strength;
    reg target_valid;
    reg [15:0] target_exposure;
    reg [COUNT_W-1:0] target_mid;
    reg [MID_SUM_W-1:0] target_raw,target_envelope;


    reg [2:0] state;
    reg reference_ready;
    reg [5:0] serial_left;
    reg [ACC_W-1:0] div_dividend;
    reg [COUNT_W-1:0] div_denominator;
    reg [COUNT_W:0] div_remainder;
    reg [9:0] div_quotient;
    wire [COUNT_W:0] div_shifted = {div_remainder[COUNT_W-1:0],div_dividend[ACC_W-1]};
    wire div_subtract = div_shifted >= {1'b0,div_denominator};
    wire [9:0] div_next_quotient = {div_quotient[8:0],div_subtract};
    reg [COUNT_W-1:0] multiply_bits;
    reg [ACC_W-1:0] multiply_term,multiply_acc,raw_scaled,luma_remaining;
    reg [MID_SUM_W-1:0] envelope_delta;
    wire [ACC_W-1:0] multiply_next = multiply_acc+(multiply_bits[0]?multiply_term:{ACC_W{1'b0}});
    reg [19:0] exposure_remaining;
    reg [15:0] exposure_denominator;
    reg [4:0] exposure_steps,exposure_cap,luma_steps;
    wire [15:0] exposure_difference = O_reference_exposure-pending_exposure;
    wire exposure_stable_now = pending_good &&
        pending_exposure == exposure_stable_value &&
        exposure_stable_count >= EXPOSURE_STABLE_FRAMES-1;
    wire exposure_exit_stable_now = pending_good &&
        pending_exposure == exposure_stable_value &&
        exposure_stable_count >= EXPOSURE_EXIT_STABLE_FRAMES-1;
    wire [15:0] reference_exposure_delta = (pending_exposure >= O_reference_exposure) ?
        pending_exposure-O_reference_exposure : O_reference_exposure-pending_exposure;
    wire exposure_near_reference = reference_exposure_delta <= EXPOSURE_TOLERANCE;
    // 基线附近、E已稳定且当前场景已不再满足保持条件时，提前结束本轮保护。
    // 保留保持门限，避免仅因一帧明暗差变小就切断仍在进行的保护。
    wire baseline_recovered = O_triggered && reference_ready && !hold_condition &&
        exposure_exit_stable_now && exposure_near_reference && (O_strength == 0);
    wire target_input_same = target_valid &&
        pending_exposure == target_exposure && pending_mid == target_mid &&
        pending_raw == target_raw && pending_envelope == target_envelope;

    // 三拍归约持续运行。VS先锁存计数，随后等三拍才读取旧帧range，
    // 即使最后一个样本紧邻VS也不会误用尚未完成的极值。
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            min0123<=0; min4567<=0; min89AB<=0;
            max0123<=0; max4567<=0; max89AB<=0;
            min_sum<=0; max_sum<=0; range_sum<=0;
        end else begin
            min0123<=(min01<min23)?min01:min23;
            min4567<=(min45<min67)?min45:min67;
            min89AB<=(min89<minAB)?min89:minAB;
            max0123<=(max01>max23)?max01:max23;
            max4567<=(max45>max67)?max45:max67;
            max89AB<=(max89>maxAB)?max89:maxAB;
            min_sum<=(min_first<min89AB)?min_first:min89AB;
            max_sum<=(max_first>max89AB)?max_first:max89AB;
            range_sum<=max_sum-min_sum;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            vs_d<=0; active<=0; overflow<=0; frame_exposure_good<=0;
            x<=0; y<=0; phase<=0; frame_exposure<=0;
            sample_count<=0; bright_count<=0; shadow_count<=0; mid_count<=0;
            raw_sum<=0; envelope_sum<=0;
            evaluate_wait<=0; pending_good<=0; pending_bright<=0; pending_shadow<=0;
            pending_mid<=0; pending_raw<=0; pending_envelope<=0; pending_exposure<=0;
            O_strength<=0; O_reference_exposure<=0; O_reference_luma<=0; O_triggered<=0;
            enter_wait<=0; exit_wait<=0; state<=S_IDLE; reference_ready<=0;
            serial_left<=0; div_dividend<=0; div_denominator<=0; div_remainder<=0; div_quotient<=0;
            multiply_bits<=0; multiply_term<=0; multiply_acc<=0; raw_scaled<=0; luma_remaining<=0;
            envelope_delta<=0; exposure_remaining<=0; exposure_denominator<=0;
            exposure_steps<=0; exposure_cap<=0; luma_steps<=0;
            exposure_stable_value<=0; exposure_stable_count<=0;
            baseline_valid<=0; baseline_exposure<=0; baseline_mid<=0; baseline_raw<=0;
            target_strength<=0; target_valid<=0; target_exposure<=0; target_mid<=0;
            target_raw<=0; target_envelope<=0;
            for(i=0;i<12;i=i+1) region_sum[i]<=0;
        end else begin
            vs_d<=I_vs;
            if (!I_enable) begin
                // 禁用立即清状态；重开后必须从下一VS重新统计完整帧。
                active<=0; overflow<=0; frame_exposure_good<=0; x<=0; y<=0; phase<=0;
                sample_count<=0; bright_count<=0; shadow_count<=0; mid_count<=0;
                raw_sum<=0; envelope_sum<=0; evaluate_wait<=0; pending_good<=0;
                O_strength<=0; O_triggered<=0; O_reference_exposure<=0; O_reference_luma<=0;
                enter_wait<=0; exit_wait<=0; state<=S_IDLE; reference_ready<=0;
                exposure_stable_value<=0; exposure_stable_count<=0;
                baseline_valid<=0; baseline_exposure<=0; baseline_mid<=0; baseline_raw<=0;
                target_strength<=0; target_valid<=0; target_exposure<=0; target_mid<=0;
                target_raw<=0; target_envelope<=0;
                for(i=0;i<12;i=i+1) region_sum[i]<=0;
            end else begin
                if (vs_start) begin
                    pending_good<=frame_good;
                    pending_bright<=bright_count; pending_shadow<=shadow_count;
                    pending_mid<=mid_count; pending_raw<=raw_sum; pending_envelope<=envelope_sum;
                    pending_exposure<=frame_exposure; evaluate_wait<=2'd3;
                    active<=1; overflow<=0; frame_exposure_good<=exposure_good;
                    frame_exposure<=I_exposure; x<=0; y<=0; phase<=0;
                    sample_count<=0; bright_count<=0; shadow_count<=0; mid_count<=0;
                    raw_sum<=0; envelope_sum<=0;
                    for(i=0;i<12;i=i+1) region_sum[i]<=0;
                end else if (active) begin
                    if (!exposure_good || I_exposure != frame_exposure) frame_exposure_good<=0;
                    if (I_de) begin
                        if (y >= V_ACTIVE) overflow<=1;
                        if (SAMPLE_LOG2 != 0) phase<=phase+1'b1;
                        if (sample_now) begin
                            sample_count<=sample_count+1'b1;
                            region_sum[region_index]<=region_sum[region_index]+luma6;
                            if (luma6>=6'd48) bright_count<=bright_count+1'b1;
                            if (luma6<=6'd12) shadow_count<=shadow_count+1'b1;
                            if (peak>=8'd8 && peak<8'd192) begin
                                mid_count<=mid_count+1'b1;
                                raw_sum<=raw_sum+luma6;
                                envelope_sum<=envelope_sum+envelope_luma6;
                            end
                        end
                        if (x==H_ACTIVE-1) begin
                            x<=0;
                            if (y<V_ACTIVE) y<=y+1'b1;
                        end else x<=x+1'b1;
                    end
                end

                if (!vs_start && evaluate_wait!=0) begin
                    evaluate_wait<=evaluate_wait-1'b1;
                    if (evaluate_wait==1) begin
                        // 只把连续完整有效帧中的同一E视为稳定，避免补亮追着AE在途值计算。
                        if (!pending_good) begin
                            exposure_stable_count<=0;
                        end else if (pending_exposure != exposure_stable_value) begin
                            exposure_stable_value<=pending_exposure;
                            exposure_stable_count<=1;
                        end else if (exposure_stable_count < EXPOSURE_EXIT_STABLE_FRAMES) begin
                            exposure_stable_count<=exposure_stable_count+1'b1;
                        end
                        // 在SW5允许且场景尚未进入高光保护时，持续保存稳定正常基线。
                        // 高光进入后即使AE先进入在途，也继续使用这份基线。
                        if (pending_good && state==S_IDLE && !O_triggered && O_strength==0 &&
                            pending_mid!=0 && !enter_condition) begin
                            baseline_valid<=1;
                            baseline_exposure<=pending_exposure;
                            baseline_mid<=pending_mid;
                            baseline_raw<=pending_raw;
                        end
                        if (!pending_good || state!=S_IDLE) begin
                            // 无效帧及串行计算忙时暂停证据，不丢弃降曝前候选参考。
                        end else if (!O_triggered) begin
                            exit_wait<=0;
                            if (O_strength!=0) begin
                                // 上一场景先完整渐退到0，再允许捕获新的参考。
                                O_strength<=O_strength-1'b1;
                                enter_wait<=0;
                            end else if (enter_condition && pending_mid!=0) begin
                                if (enter_wait==0) begin
                                    // 第一有效帧就保存候选，避免AE先压暗再取参考。
                                    enter_wait<=1;
                                    O_reference_exposure<=baseline_valid ? baseline_exposure : pending_exposure;
                                    O_reference_luma<=0; reference_ready<=0;
                                    target_valid<=0;
                                    div_dividend<=baseline_valid ? {baseline_raw,4'd0} : {pending_raw,4'd0};
                                    div_denominator<=baseline_valid ? baseline_mid : pending_mid;
                                    div_remainder<=0; div_quotient<=0;
                                    serial_left<=ACC_W; state<=S_REFERENCE_DIV;
                                end else if (enter_wait==2 && reference_ready) begin
                                    enter_wait<=0; O_triggered<=1;
                                end else enter_wait<=enter_wait+1'b1;
                            end else begin
                                enter_wait<=0; O_reference_exposure<=0; O_reference_luma<=0;
                                reference_ready<=0;
                            end
                        end else if (baseline_recovered) begin
                            // E已经回到基线附近且连续稳定，当前场景也不再保持高反差；
                            // 直接结束本轮保护，避免无意义地继续运行串行计算。
                            O_strength<=0; O_triggered<=0; O_reference_exposure<=0; O_reference_luma<=0;
                            reference_ready<=0; target_valid<=0; enter_wait<=0; exit_wait<=0; state<=S_IDLE;
                        end else if (!hold_condition && exit_wait==7 && exposure_exit_stable_now) begin
                            O_triggered<=0; O_reference_exposure<=0; O_reference_luma<=0;
                            reference_ready<=0; target_valid<=0; enter_wait<=0; exit_wait<=0; state<=S_IDLE;
                            if (O_strength!=0) O_strength<=O_strength-1'b1;
                        end else begin
                            enter_wait<=0;
                            if (hold_condition) exit_wait<=0;
                            else exit_wait<=exit_wait+1'b1;
                            if (reference_ready) begin
                                if (!exposure_stable_now) begin
                                    // AE仍在改变E时只保留当前强度；稳定后再算一次目标。
                                end else if (target_input_same) begin
                                    // 输入没有变化时沿用上次目标，只做一拍一级的渐变。
                                    if (O_strength<target_strength) O_strength<=O_strength+1'b1;
                                    else if (O_strength>target_strength) O_strength<=O_strength-1'b1;
                                end else if (pending_exposure>=O_reference_exposure || pending_mid==0 ||
                                             pending_envelope<=pending_raw) begin
                                    target_strength<=0; target_valid<=1;
                                    target_exposure<=pending_exposure; target_mid<=pending_mid;
                                    target_raw<=pending_raw; target_envelope<=pending_envelope;
                                    if (O_strength!=0) O_strength<=O_strength-1'b1;
                                end else begin
                                    // 先串行计算参考均值×当前同类像素数。
                                    target_valid<=0;
                                    target_exposure<=pending_exposure; target_mid<=pending_mid;
                                    target_raw<=pending_raw; target_envelope<=pending_envelope;
                                    multiply_bits<=pending_mid;
                                    multiply_term<=O_reference_luma; multiply_acc<=0;
                                    raw_scaled<={pending_raw,4'd0};
                                    envelope_delta<=pending_envelope-pending_raw;
                                    // 目标亮度计算本身已经按参考均值停止；不再用E比例
                                    // 提前截断，避免E900->675时最多只有5档而补亮不足。
                                    exposure_remaining<={exposure_difference,4'd0};
                                    exposure_denominator<=pending_exposure;
                                    serial_left<=COUNT_W; state<=S_REFERENCE_MUL;
                                end
                            end
                        end
                    end
                end

                case (state)
                    S_REFERENCE_DIV: begin
                        div_dividend<=div_dividend<<1;
                        div_remainder<=div_subtract ? div_shifted-{1'b0,div_denominator} : div_shifted;
                        div_quotient<=div_next_quotient;
                        serial_left<=serial_left-1'b1;
                        if (serial_left==1) begin
                            O_reference_luma<=div_next_quotient;
                            reference_ready<=1; state<=S_IDLE;
                        end
                    end
                    S_REFERENCE_MUL: begin
                        multiply_acc<=multiply_next; multiply_term<=multiply_term<<1;
                        multiply_bits<=multiply_bits>>1; serial_left<=serial_left-1'b1;
                        if (serial_left==1) begin
                            if (multiply_next<=raw_scaled) begin
                                target_strength<=0; target_valid<=1;
                                if (O_strength!=0) O_strength<=O_strength-1'b1;
                                state<=S_IDLE;
                            end else begin
                                luma_remaining<=multiply_next-raw_scaled;
                                exposure_steps<=0; state<=S_EXPOSURE_CAP;
                            end
                        end
                    end
                    S_EXPOSURE_CAP: begin
                        if (exposure_steps<5'd16 && exposure_remaining>={4'd0,exposure_denominator}) begin
                            exposure_remaining<=exposure_remaining-{4'd0,exposure_denominator};
                            exposure_steps<=exposure_steps+1'b1;
                        end else if (exposure_steps==0) begin
                            target_strength<=0; target_valid<=1;
                            if (O_strength!=0) O_strength<=O_strength-1'b1;
                            state<=S_IDLE;
                        end else begin
                            // 在E比例上增加有限余量，避免E900->675时只有5档；
                            // 仍保留上限16，防止补亮失控。
                            exposure_cap<=((exposure_steps + EXPOSURE_CAP_MARGIN) > 16) ?
                                5'd16 : exposure_steps + EXPOSURE_CAP_MARGIN;
                            luma_steps<=0; state<=S_LUMA_SEARCH;
                        end
                    end
                    S_LUMA_SEARCH: begin
                        if (luma_steps<exposure_cap && luma_remaining>=envelope_delta) begin
                            luma_remaining<=luma_remaining-envelope_delta;
                            luma_steps<=luma_steps+1'b1;
                        end else begin
                            target_strength<=luma_steps; target_valid<=1;
                            if (O_strength<luma_steps) O_strength<=O_strength+1'b1;
                            else if (O_strength>luma_steps) O_strength<=O_strength-1'b1;
                            state<=S_IDLE;
                        end
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule

// 显式位积与平衡加法树，不使用乘法运算符。
module fusion_n1_channel(input wire [7:0] I_pixel,input wire [10:0] I_gain,output wire [7:0] O_pixel);
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


