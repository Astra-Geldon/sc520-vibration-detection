// Fixed E900/G12 production lift, copied bit-for-bit from accepted N1.
// One Q8 gain for all RGB channels; peak>=192 is exact unity.
// No candidate selector, DSP multiplication, frame buffers or extra latency.
module fixed_n1_gain(input wire [7:0] I_peak, output reg [10:0] O_gain);
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

// Explicit bit partial products and balanced tree. No multiply operator;
// the full TD resource report, not source syntax, confirms DSP usage.
module fixed_n1_channel(input wire [7:0] I_pixel,input wire [10:0] I_gain,output wire [7:0] O_pixel);
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


// 自适应强度只在显示端按帧更新。参数为0时保留原N1逐位结果。
module fixed_n1_adaptive_channel(input wire [7:0] I_pixel,
    input wire [7:0] I_peak, input wire [10:0] I_base_gain,
    input wire [3:0] I_strength, output wire [7:0] O_pixel);
    wire [7:0] base_pixel;
    fixed_n1_channel u_base(.I_pixel(I_pixel), .I_gain(I_base_gain), .O_pixel(base_pixel));
    fixed_n1_extra_channel u_extra(.I_base_pixel(base_pixel), .I_peak(I_peak),
        .I_strength(I_strength), .O_pixel(O_pixel));
endmodule

// 只处理原N1已经完成取整的8位结果，便于跨既有寄存器拆分计算。
module fixed_n1_extra_channel(input wire [7:0] I_base_pixel,
    input wire [7:0] I_peak, input wire [3:0] I_strength, output wire [7:0] O_pixel);
    wire [7:0] base_pixel = I_base_pixel;
    // 按strength/128计算附加提亮，使用显式移位加法，避免新增乘法器。
    wire [11:0] p0 = I_strength[0] ? {4'd0, base_pixel} : 12'd0;
    wire [11:0] p1 = I_strength[1] ? {3'd0, base_pixel, 1'd0} : 12'd0;
    wire [11:0] p2 = I_strength[2] ? {2'd0, base_pixel, 2'd0} : 12'd0;
    wire [11:0] p3 = I_strength[3] ? {1'd0, base_pixel, 3'd0} : 12'd0;
    wire [11:0] extra_num = p0 + p1 + p2 + p3;
    wire [8:0] boosted = {1'b0, base_pixel} + ((extra_num + 12'd64) >> 7);
    wire [8:0] limited = (I_peak < 8'd192 && boosted > 9'd192) ? 9'd192 : boosted;
    assign O_pixel = (I_peak >= 8'd192 || I_strength == 0) ? base_pixel : limited[7:0];
endmodule

module fixed_n1_extra_lift(input wire I_de, input wire I_enable,
    input wire [23:0] I_data, input wire [7:0] I_peak,
    input wire [3:0] I_extra_strength, output wire [23:0] O_data);
    wire [23:0] lifted;
    fixed_n1_extra_channel r(.I_base_pixel(I_data[23:16]), .I_peak(I_peak),
        .I_strength(I_extra_strength), .O_pixel(lifted[23:16]));
    fixed_n1_extra_channel g(.I_base_pixel(I_data[15:8]), .I_peak(I_peak),
        .I_strength(I_extra_strength), .O_pixel(lifted[15:8]));
    fixed_n1_extra_channel b(.I_base_pixel(I_data[7:0]), .I_peak(I_peak),
        .I_strength(I_extra_strength), .O_pixel(lifted[7:0]));
    assign O_data = (!I_de || !I_enable) ? I_data : lifted;
endmodule

module fixed_n1_lift #(parameter integer ADAPTIVE = 0) (
    input wire I_de, input wire I_enable,
    input wire [23:0] I_data, input wire [7:0] I_peak,
    input wire [3:0] I_extra_strength, output wire [23:0] O_data);
    wire [10:0] gain;
    wire [23:0] lifted;
    fixed_n1_gain u_gain(.I_peak(I_peak), .O_gain(gain));
    generate
        if (ADAPTIVE != 0) begin : gen_adaptive
            fixed_n1_adaptive_channel r(.I_pixel(I_data[23:16]), .I_peak(I_peak),
                .I_base_gain(gain), .I_strength(I_extra_strength), .O_pixel(lifted[23:16]));
            fixed_n1_adaptive_channel g(.I_pixel(I_data[15:8]), .I_peak(I_peak),
                .I_base_gain(gain), .I_strength(I_extra_strength), .O_pixel(lifted[15:8]));
            fixed_n1_adaptive_channel b(.I_pixel(I_data[7:0]), .I_peak(I_peak),
                .I_base_gain(gain), .I_strength(I_extra_strength), .O_pixel(lifted[7:0]));
        end else begin : gen_baseline
            fixed_n1_channel r(.I_pixel(I_data[23:16]), .I_gain(gain), .O_pixel(lifted[23:16]));
            fixed_n1_channel g(.I_pixel(I_data[15:8]), .I_gain(gain), .O_pixel(lifted[15:8]));
            fixed_n1_channel b(.I_pixel(I_data[7:0]), .I_gain(gain), .O_pixel(lifted[7:0]));
        end
    endgenerate
    assign O_data = (!I_de || !I_enable) ? I_data : lifted;
endmodule

// 按4×3粗分区统计显示端原始像素，只输出一帧一个统一强度。
// 分区用于判断明暗差，不给不同区域套不同增益，因此不会出现拼块边界。
(* dsp_style = "no" *)
module adaptive_n1_control #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer EXPECTED_SAMPLES = 14400,
    parameter integer SAMPLE_LOG2 = 6
) (
    input wire I_clk, input wire I_rst_n,
    input wire I_vs, input wire I_de, input wire I_enable,
    input wire [23:0] I_data, output reg [3:0] O_strength
);
    localparam integer COUNT_W = (EXPECTED_SAMPLES < 2) ? 1 : $clog2(EXPECTED_SAMPLES + 1);
    localparam integer SUM_W = 18;
    localparam integer MIX_COUNT = (EXPECTED_SAMPLES * 2 + 99) / 100;
    localparam integer SHADOW_COUNT = (EXPECTED_SAMPLES * 20 + 99) / 100;
    localparam integer REGION_SAMPLES = (EXPECTED_SAMPLES < 12) ? 1 : (EXPECTED_SAMPLES / 12);
    localparam integer PHASE_W = (SAMPLE_LOG2 < 1) ? 1 : SAMPLE_LOG2;
    localparam integer EXIT_REGION_SAMPLES = (REGION_SAMPLES * 3 + 3) / 4;
    localparam integer REGION_RANGE = 18;
    localparam integer H4 = H_ACTIVE / 4;
    localparam integer V3 = V_ACTIVE / 3;
    reg vs_d, active, overflow;
    reg [11:0] x;
    reg [10:0] y;
    reg [PHASE_W-1:0] phase;
    reg [COUNT_W-1:0] sample_count, bright_count, shadow_count;
    reg [SUM_W-1:0] region_sum [0:11];
    integer i;
    reg [SUM_W-1:0] min_sum, max_sum;
    // 平衡比较树分三拍归约。每64像素采样一次，最后样本距行尾仍有63拍，
    // 因而完整帧在场首读取到的极值及门限结果与原算法相同。
    wire [SUM_W-1:0] min01 = (region_sum[0] < region_sum[1]) ? region_sum[0] : region_sum[1];
    wire [SUM_W-1:0] min23 = (region_sum[2] < region_sum[3]) ? region_sum[2] : region_sum[3];
    wire [SUM_W-1:0] min45 = (region_sum[4] < region_sum[5]) ? region_sum[4] : region_sum[5];
    wire [SUM_W-1:0] min67 = (region_sum[6] < region_sum[7]) ? region_sum[6] : region_sum[7];
    wire [SUM_W-1:0] min89 = (region_sum[8] < region_sum[9]) ? region_sum[8] : region_sum[9];
    wire [SUM_W-1:0] minAB = (region_sum[10] < region_sum[11]) ? region_sum[10] : region_sum[11];
    reg [SUM_W-1:0] min0123, min4567, min89AB;
    wire [SUM_W-1:0] min01234567 = (min0123 < min4567) ? min0123 : min4567;
    wire [SUM_W-1:0] min_tree = (min01234567 < min89AB) ? min01234567 : min89AB;
    wire [SUM_W-1:0] max01 = (region_sum[0] > region_sum[1]) ? region_sum[0] : region_sum[1];
    wire [SUM_W-1:0] max23 = (region_sum[2] > region_sum[3]) ? region_sum[2] : region_sum[3];
    wire [SUM_W-1:0] max45 = (region_sum[4] > region_sum[5]) ? region_sum[4] : region_sum[5];
    wire [SUM_W-1:0] max67 = (region_sum[6] > region_sum[7]) ? region_sum[6] : region_sum[7];
    wire [SUM_W-1:0] max89 = (region_sum[8] > region_sum[9]) ? region_sum[8] : region_sum[9];
    wire [SUM_W-1:0] maxAB = (region_sum[10] > region_sum[11]) ? region_sum[10] : region_sum[11];
    reg [SUM_W-1:0] max0123, max4567, max89AB;
    wire [SUM_W-1:0] max01234567 = (max0123 > max4567) ? max0123 : max4567;
    wire [SUM_W-1:0] max_tree = (max01234567 > max89AB) ? max01234567 : max89AB;
    reg [SUM_W-1:0] range_sum;
    reg contrast_enter, contrast_exit;
    reg [2:0] rise_wait, fall_wait;
    wire vs_start = I_vs && !vs_d;
    wire [11:0] luma_sum = {4'd0, I_data[23:16]} +
                            {3'd0, I_data[15:8], 1'b0} + {4'd0, I_data[7:0]};
    wire [5:0] luma6 = luma_sum[9:4];
    wire sample_now = I_de && (phase == 0) && (sample_count < EXPECTED_SAMPLES);
    wire [1:0] col = (x < H4) ? 2'd0 : ((x < H4*2) ? 2'd1 :
                         ((x < H4*3) ? 2'd2 : 2'd3));
    wire [1:0] row = (y < V3) ? 2'd0 : ((y < V3*2) ? 2'd1 : 2'd2);
    wire [3:0] region_index = {row, 2'b00} + col;
    wire frame_geometry_good = (x == 0) && (y == V_ACTIVE-1);
    wire frame_good = active && !overflow && (sample_count == EXPECTED_SAMPLES) && frame_geometry_good;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            min0123 <= 0; min4567 <= 0; min89AB <= 0;
            max0123 <= 0; max4567 <= 0; max89AB <= 0;
            min_sum <= 0; max_sum <= 0; range_sum <= 0;
        end else begin
            min0123 <= (min01 < min23) ? min01 : min23;
            min4567 <= (min45 < min67) ? min45 : min67;
            min89AB <= (min89 < minAB) ? min89 : minAB;
            max0123 <= (max01 > max23) ? max01 : max23;
            max4567 <= (max45 > max67) ? max45 : max67;
            max89AB <= (max89 > maxAB) ? max89 : maxAB;
            min_sum <= min_tree;
            max_sum <= max_tree;
            range_sum <= max_sum - min_sum;
        end
    end

    always @(*) begin
        contrast_enter = frame_good && (range_sum >= (REGION_RANGE * REGION_SAMPLES)) &&
                         (bright_count >= MIX_COUNT) && (shadow_count >= SHADOW_COUNT);
        contrast_exit = !contrast_enter || (range_sum < (REGION_RANGE * EXIT_REGION_SAMPLES)) ||
                        (bright_count < (MIX_COUNT / 2)) || (shadow_count < (SHADOW_COUNT / 2));
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            vs_d <= 0; active <= 0; overflow <= 0; x <= 0; y <= 0; phase <= 0;
            sample_count <= 0; bright_count <= 0; shadow_count <= 0;
            O_strength <= 0; rise_wait <= 0; fall_wait <= 0;
            for (i = 0; i < 12; i = i + 1) region_sum[i] <= 0;
        end else begin
            vs_d <= I_vs;
            if (vs_start) begin
                if (active && I_enable && frame_good) begin
                    if (contrast_enter) begin
                        fall_wait <= 0;
                        if (rise_wait == 3'd3) begin
                            rise_wait <= 0;
                            if (O_strength < 4'd8) O_strength <= O_strength + 1'b1;
                        end else rise_wait <= rise_wait + 1'b1;
                    end else if (contrast_exit) begin
                        rise_wait <= 0;
                        if (fall_wait == 3'd7) begin
                            fall_wait <= 0;
                            if (O_strength != 0) O_strength <= O_strength - 1'b1;
                        end else fall_wait <= fall_wait + 1'b1;
                    end
                end
                active <= I_enable;
                overflow <= 0; x <= 0; y <= 0; phase <= 0;
                sample_count <= 0; bright_count <= 0; shadow_count <= 0;
                for (i = 0; i < 12; i = i + 1) region_sum[i] <= 0;
                if (!I_enable) begin O_strength <= 0; rise_wait <= 0; fall_wait <= 0; end
            end else if (active && I_de) begin
                if (phase == {PHASE_W{1'b1}}) phase <= 0;
                else phase <= phase + 1'b1;
                if (sample_now) begin
                    sample_count <= sample_count + 1'b1;
                    region_sum[region_index] <= region_sum[region_index] + luma6;
                    if (luma6 >= 6'd48) bright_count <= bright_count + 1'b1;
                    if (luma6 <= 6'd12) shadow_count <= shadow_count + 1'b1;
                end
                if (x == H_ACTIVE-1) begin x <= 0; if (y < V_ACTIVE-1) y <= y + 1'b1; end
                else x <= x + 1'b1;
            end
            // 采样数量达到预期后不再累加；帧边界负责提交本帧统计。
        end
    end
endmodule
