// 融合版唯一补亮路径：Tone LUT提供暗部提升/高光压缩包络，控制器在AE稳定后按场景证据逐帧调节公共强度。
// Gamma之后的残余色调曲线：暗部提升，中间调平滑，高光进入肩部压缩。
// 16段线性插值只使用移位加法，不新增DSP；255保持白点。
module fusion_tone_lut(input wire [7:0] I_value, output wire [7:0] O_value);
    // 函数加连续赋值保证输入在时间0为0时也立即得到确定输出，避免仿真器
    // 因组合always块没有经历输入跳变而保留X；综合后仍是相同的移位加法网络。
    function [7:0] tone_map;
        input [7:0] value;
        reg [7:0] base, delta;
        reg [11:0] product;
        begin
            case (value[7:4])
                4'd0:  begin base=8'd0;   delta=8'd18; end
                4'd1:  begin base=8'd18;  delta=8'd18; end
                4'd2:  begin base=8'd36;  delta=8'd18; end
                4'd3:  begin base=8'd54;  delta=8'd18; end
                4'd4:  begin base=8'd72;  delta=8'd18; end
                4'd5:  begin base=8'd90;  delta=8'd18; end
                4'd6:  begin base=8'd108; delta=8'd16; end
                4'd7:  begin base=8'd124; delta=8'd15; end
                4'd8:  begin base=8'd139; delta=8'd14; end
                4'd9:  begin base=8'd153; delta=8'd13; end
                4'd10: begin base=8'd166; delta=8'd12; end
                4'd11: begin base=8'd178; delta=8'd10; end
                4'd12: begin base=8'd188; delta=8'd10; end
                4'd13: begin base=8'd198; delta=8'd12; end
                4'd14: begin base=8'd210; delta=8'd15; end
                default: begin base=8'd225; delta=8'd30; end
            endcase
            product = (value[0] ? {4'd0,delta} : 12'd0) +
                      (value[1] ? {3'd0,delta,1'd0} : 12'd0) +
                      (value[2] ? {2'd0,delta,2'd0} : 12'd0) +
                      (value[3] ? {1'd0,delta,3'd0} : 12'd0) + 12'd8;
            tone_map = (value == 8'hff) ? 8'hff : base + product[11:4];
        end
    endfunction
    assign O_value = tone_map(I_value);
endmodule

// 组合包络复用统一的高光压缩/暗部提升曲线，不增加像素拍数。
module fusion_n1_envelope(
    input wire I_de, input wire I_enable,
    input wire [23:0] I_data, input wire [7:0] I_peak,
    output wire [23:0] O_data
);
    wire [23:0] lifted;
    fusion_tone_lut u_r(.I_value(I_data[23:16]), .O_value(lifted[23:16]));
    fusion_tone_lut u_g(.I_value(I_data[15:8]), .O_value(lifted[15:8]));
    fusion_tone_lut u_b(.I_value(I_data[7:0]), .O_value(lifted[7:0]));
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
        reg direction;
        reg [12:0] p0, p1, p2, p3, p4;
        reg [12:0] a0, a1, product;
        reg [8:0] result;
        begin
            // 支持正负差值：暗部提升走加法，高光肩部压缩走减法。
            direction = (envelope_pixel >= original_pixel);
            delta = direction ? envelope_pixel-original_pixel : original_pixel-envelope_pixel;
            p0 = strength[0] ? {5'd0, delta} : 13'd0;
            p1 = strength[1] ? {4'd0, delta, 1'd0} : 13'd0;
            p2 = strength[2] ? {3'd0, delta, 2'd0} : 13'd0;
            p3 = strength[3] ? {2'd0, delta, 3'd0} : 13'd0;
            p4 = strength[4] ? {1'd0, delta, 4'd0} : 13'd0;
            a0 = p0+p1;
            a1 = p2+p3;
            product = a0+a1+p4+13'd8;
            if (direction) begin
                result = {1'b0, original_pixel}+{1'b0, product[11:4]};
                blend_channel = result[8] ? 8'hff : result[7:0];
            end else begin
                blend_channel = ({1'b0, original_pixel} > {1'b0, product[11:4]}) ?
                                original_pixel-product[11:4] : 8'd0;
            end
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
    localparam [2:0] S_IDLE=0, S_REFERENCE_DIV=1;

    reg vs_d, active, overflow, frame_exposure_good;
    reg [11:0] x;
    reg [10:0] y;
    reg [PHASE_W-1:0] phase;
    reg [15:0] frame_exposure;
    reg [COUNT_W-1:0] sample_count, bright_count, shadow_count, mid_count;
    reg [MID_SUM_W-1:0] raw_sum;
    reg [REGION_SUM_W-1:0] region_sum[0:11];
    integer i;
    wire vs_start = I_vs && !vs_d;
    wire exposure_good = I_exposure_valid && I_exposure >= 16'd128 && I_exposure <= 16'd1991;
    wire frame_good = active && !overflow && frame_exposure_good && exposure_good &&
        I_exposure == frame_exposure && sample_count == EXPECTED_SAMPLES && x == 0 && y == V_ACTIVE;
    wire [9:0] luma_sum = {2'd0,I_data[23:16]}+{1'd0,I_data[15:8],1'b0}+{2'd0,I_data[7:0]};
    wire [5:0] luma6 = luma_sum[9:4];
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
    reg [MID_SUM_W-1:0] pending_raw;
    reg [15:0] pending_exposure;
    // Tone mapping由背景过暗、亮部覆盖或明显反差任一证据触发；高光不再单独驱动降E。
    wire enter_condition = (pending_shadow >= ENTER_SHADOW) ||
        (pending_bright >= ENTER_BRIGHT) ||
        (range_sum >= 16*REGION_SAMPLES);
    wire hold_condition = (pending_shadow >= HOLD_SHADOW) ||
        (pending_bright >= HOLD_BRIGHT) ||
        (range_sum >= 14*REGION_SAMPLES);
    reg [1:0] enter_wait;
    reg [2:0] exit_wait;
    reg [15:0] exposure_stable_value;
    reg [5:0] exposure_stable_count;
    reg baseline_valid;
    reg [15:0] baseline_exposure;
    reg [COUNT_W-1:0] baseline_mid;
    reg [MID_SUM_W-1:0] baseline_raw;
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
    wire exposure_stable_now = pending_good &&
        pending_exposure == exposure_stable_value &&
        exposure_stable_count >= EXPOSURE_STABLE_FRAMES-1;
    wire exposure_exit_stable_now = pending_good &&
        pending_exposure == exposure_stable_value &&
        exposure_stable_count >= EXPOSURE_EXIT_STABLE_FRAMES-1;
    // 场景不再需要曲线、且AE稳定约0.75秒时，退出本轮Tone映射。
    wire baseline_recovered = O_triggered && reference_ready && !hold_condition &&
        exposure_exit_stable_now && (O_strength == 0);

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
            raw_sum<=0;
            evaluate_wait<=0; pending_good<=0; pending_bright<=0; pending_shadow<=0;
            pending_mid<=0; pending_raw<=0; pending_exposure<=0;
            O_strength<=0; O_reference_exposure<=0; O_reference_luma<=0; O_triggered<=0;
            enter_wait<=0; exit_wait<=0; state<=S_IDLE; reference_ready<=0;
            serial_left<=0; div_dividend<=0; div_denominator<=0; div_remainder<=0; div_quotient<=0;
            exposure_stable_value<=0; exposure_stable_count<=0;
            baseline_valid<=0; baseline_exposure<=0; baseline_mid<=0; baseline_raw<=0;
            for(i=0;i<12;i=i+1) region_sum[i]<=0;
        end else begin
            vs_d<=I_vs;
            if (!I_enable) begin
                // 禁用立即清状态；重开后必须从下一VS重新统计完整帧。
                active<=0; overflow<=0; frame_exposure_good<=0; x<=0; y<=0; phase<=0;
                sample_count<=0; bright_count<=0; shadow_count<=0; mid_count<=0;
                raw_sum<=0; evaluate_wait<=0; pending_good<=0;
                O_strength<=0; O_triggered<=0; O_reference_exposure<=0; O_reference_luma<=0;
                enter_wait<=0; exit_wait<=0; state<=S_IDLE; reference_ready<=0;
                exposure_stable_value<=0; exposure_stable_count<=0;
                baseline_valid<=0; baseline_exposure<=0; baseline_mid<=0; baseline_raw<=0;
                for(i=0;i<12;i=i+1) region_sum[i]<=0;
            end else begin
                if (vs_start) begin
                    pending_good<=frame_good;
                    pending_bright<=bright_count; pending_shadow<=shadow_count;
                    pending_mid<=mid_count; pending_raw<=raw_sum;
                    pending_exposure<=frame_exposure; evaluate_wait<=2'd3;
                    active<=1; overflow<=0; frame_exposure_good<=exposure_good;
                    frame_exposure<=I_exposure; x<=0; y<=0; phase<=0;
                    sample_count<=0; bright_count<=0; shadow_count<=0; mid_count<=0;
                    raw_sum<=0;
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
                            reference_ready<=0; enter_wait<=0; exit_wait<=0; state<=S_IDLE;
                        end else if (!hold_condition && exit_wait==7 && exposure_exit_stable_now) begin
                            O_triggered<=0; O_reference_exposure<=0; O_reference_luma<=0;
                            reference_ready<=0; enter_wait<=0; exit_wait<=0; state<=S_IDLE;
                            if (O_strength!=0) O_strength<=O_strength-1'b1;
                        end else begin
                            enter_wait<=0;
                            if (hold_condition) exit_wait<=0;
                            else exit_wait<=exit_wait+1'b1;
                            if (reference_ready) begin
                                // 新目标是统一Tone映射，不再把包络亮度差当作“恢复E前均值”
                                // 的除法问题。AE稳定后按场景证据缓慢推到16档或退回0档。
                                if (!exposure_stable_now) begin
                                    // AE在途时保持当前显示强度，避免亮度变化和曲线同时抖动。
                                end else begin
                                    if (hold_condition && O_strength<5'd16)
                                        O_strength<=O_strength+1'b1;
                                    else if (!hold_condition && O_strength!=0)
                                        O_strength<=O_strength-1'b1;
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
                    default: begin end
                endcase
            end
        end
    end
endmodule
