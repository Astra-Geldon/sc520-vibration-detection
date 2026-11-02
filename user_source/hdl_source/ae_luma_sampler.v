// AWB/Gamma前的独立测光，不使用显示端补亮结果作为曝光反馈。
// 默认每16个四像素包抽取一个像素，保留原完整帧校验及序号协议。
// 背景优先测光：排除56以上高光后，用8桶亮度统计近似P60控制E。
(* dsp_style = "no" *)
module ae_luma_sampler #(
    parameter integer EXPECTED_SAMPLES = 14400,
    parameter integer LOW_LUMA = 16,
    parameter integer HIGH_LUMA = 24,
    parameter integer SAMPLE_LOG2 = 4,
    parameter integer HIGHLIGHT_GUARD = 1,
    parameter integer NEAR_CLIP_LUMA = 60,
    parameter integer HEADROOM_LUMA = 48,
    parameter integer SHADOW_LUMA = 12,
    parameter integer HIGHLIGHT_PERCENT = 2,
    parameter integer SHADOW_PERCENT = 20,
    parameter integer SHADOW_MEAN_FLOOR = 8,
    parameter integer BG_LOW_LUMA = 22,
    parameter integer BG_HIGH_LUMA = 30,
    parameter integer EMERGENCY_CLIP_PERCENT = 10,
    parameter integer BACKGROUND_MIN_PERCENT = 40
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire I_frame_start,
    input wire I_valid,
    input wire I_enable,
    input wire [5:0] I_luma,
    // 高4位为新帧序号，低2位依次表示保持、增曝、减曝、无效。
    output reg [5:0] O_measure,
    output reg O_valid
);
    localparam integer COUNT_W = (EXPECTED_SAMPLES < 2) ? 1 :
                                  $clog2(EXPECTED_SAMPLES + 1);
    localparam integer SUM_W = (EXPECTED_SAMPLES < 2) ? 6 :
                                $clog2(EXPECTED_SAMPLES * 63 + 1);
    localparam integer PHASE_W = (SAMPLE_LOG2 < 1) ? 1 : SAMPLE_LOG2;
    localparam [SUM_W-1:0] LOW_SUM = EXPECTED_SAMPLES * LOW_LUMA;
    localparam [SUM_W-1:0] HIGH_SUM = EXPECTED_SAMPLES * HIGH_LUMA;
    localparam [SUM_W-1:0] SHADOW_FLOOR_SUM = EXPECTED_SAMPLES * SHADOW_MEAN_FLOOR;
    // 比例门限仅在展开阶段计算，不产生运行时乘除法。
    localparam [COUNT_W-1:0] HIGHLIGHT_COUNT =
                                (EXPECTED_SAMPLES * HIGHLIGHT_PERCENT + 99) / 100;
    localparam [COUNT_W-1:0] SHADOW_COUNT =
                                (EXPECTED_SAMPLES * SHADOW_PERCENT + 99) / 100;
    localparam [COUNT_W-1:0] EMERGENCY_CLIP_COUNT =
                                (EXPECTED_SAMPLES * EMERGENCY_CLIP_PERCENT + 99) / 100;
    localparam [COUNT_W-1:0] BACKGROUND_MIN_COUNT =
                                (EXPECTED_SAMPLES * BACKGROUND_MIN_PERCENT + 99) / 100;

    reg [COUNT_W-1:0] sample_count;
    reg [COUNT_W-1:0] near_clip_count, headroom_count, shadow_count;
    reg [COUNT_W-1:0] hist0, hist1, hist2, hist3, hist4, hist5, hist6, hist7;
    reg [SUM_W-1:0] luma_sum;
    reg [PHASE_W-1:0] phase;
    reg frame_armed, frame_enabled, overflow, frame_start_d;
    wire frame_start = I_frame_start && !frame_start_d;
    wire frame_complete = frame_enabled && !overflow &&
                          (sample_count == EXPECTED_SAMPLES) && (phase == 0);
    wire [COUNT_W:0] bg_count = hist0 + hist1 + hist2 + hist3 +
                                 hist4 + hist5 + hist6;
    wire [COUNT_W:0] bg_c0 = hist0;
    wire [COUNT_W:0] bg_c1 = bg_c0 + hist1;
    wire [COUNT_W:0] bg_c2 = bg_c1 + hist2;
    wire [COUNT_W:0] bg_c3 = bg_c2 + hist3;
    wire [COUNT_W:0] bg_c4 = bg_c3 + hist4;
    wire [COUNT_W:0] bg_c5 = bg_c4 + hist5;
    wire [COUNT_W:0] bg_c6 = bg_c5 + hist6;
    // P60判断使用5*cumulative >= 3*total，常数乘法只由移位加法实现。
    // 先扩展再移位；若直接在COUNT_W+1位上计算，14400样本的5倍会溢出。
    wire [COUNT_W+2:0] bg_count_wide = {{2{1'b0}},bg_count};
    wire [COUNT_W+2:0] bg_c0_wide = {{2{1'b0}},bg_c0};
    wire [COUNT_W+2:0] bg_c1_wide = {{2{1'b0}},bg_c1};
    wire [COUNT_W+2:0] bg_c2_wide = {{2{1'b0}},bg_c2};
    wire [COUNT_W+2:0] bg_c3_wide = {{2{1'b0}},bg_c3};
    wire [COUNT_W+2:0] bg_c4_wide = {{2{1'b0}},bg_c4};
    wire [COUNT_W+2:0] bg_c5_wide = {{2{1'b0}},bg_c5};
    wire [COUNT_W+2:0] bg_c6_wide = {{2{1'b0}},bg_c6};
    wire [COUNT_W+2:0] bg_3x = (bg_count_wide << 1) + bg_count_wide;
    wire [COUNT_W+2:0] c0_5x = (bg_c0_wide << 2) + bg_c0_wide;
    wire [COUNT_W+2:0] c1_5x = (bg_c1_wide << 2) + bg_c1_wide;
    wire [COUNT_W+2:0] c2_5x = (bg_c2_wide << 2) + bg_c2_wide;
    wire [COUNT_W+2:0] c3_5x = (bg_c3_wide << 2) + bg_c3_wide;
    wire [COUNT_W+2:0] c4_5x = (bg_c4_wide << 2) + bg_c4_wide;
    wire [COUNT_W+2:0] c5_5x = (bg_c5_wide << 2) + bg_c5_wide;
    wire [COUNT_W+2:0] c6_5x = (bg_c6_wide << 2) + bg_c6_wide;
    wire [5:0] background_p60 =
        (c0_5x >= bg_3x) ? 6'd3  :
        (c1_5x >= bg_3x) ? 6'd11 :
        (c2_5x >= bg_3x) ? 6'd19 :
        (c3_5x >= bg_3x) ? 6'd27 :
        (c4_5x >= bg_3x) ? 6'd35 :
        (c5_5x >= bg_3x) ? 6'd43 :
        (c6_5x >= bg_3x) ? 6'd51 : 6'd59;
    wire background_valid = bg_count >= BACKGROUND_MIN_COUNT;
    wire emergency_clip = near_clip_count >= EMERGENCY_CLIP_COUNT;
    // 小面积高光不再压暗背景；只有接近饱和像素达到10%才触发紧急减E。
    wire [1:0] classification = !frame_complete ? 2'b11 :
                                (emergency_clip ? 2'b10 :
                                 (!background_valid ? 2'b00 :
                                  ((background_p60 < BG_LOW_LUMA) ? 2'b01 :
                                   ((background_p60 > BG_HIGH_LUMA) ? 2'b10 : 2'b00))));

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sample_count <= 0;
            near_clip_count <= 0;
            headroom_count <= 0;
            shadow_count <= 0;
            hist0 <= 0; hist1 <= 0; hist2 <= 0; hist3 <= 0;
            hist4 <= 0; hist5 <= 0; hist6 <= 0; hist7 <= 0;
            luma_sum <= 0;
            phase <= 0;
            frame_armed <= 0;
            frame_enabled <= 0;
            overflow <= 0;
            frame_start_d <= 0;
            O_measure <= 0;
            O_valid <= 0;
        end else begin
            frame_start_d <= I_frame_start;
            if (frame_start) begin
                if (frame_armed) begin
                    // 无效帧也推进序号，接收端不能把旧统计重新当作新反馈。
                    O_measure <= {O_measure[5:2] + 4'd1, classification};
                    O_valid <= 1;
                end
                frame_armed <= 1;
                frame_enabled <= I_enable;
                overflow <= 0;
                // 帧首可以与首个有效包同拍，三个计数器必须同步计入。
                sample_count <= I_valid ? 1 : 0;
                near_clip_count <= (I_valid && (I_luma >= NEAR_CLIP_LUMA)) ? 1 : 0;
                headroom_count <= (I_valid && (I_luma >= HEADROOM_LUMA)) ? 1 : 0;
                shadow_count <= (I_valid && (I_luma <= SHADOW_LUMA)) ? 1 : 0;
                hist0 <= 0; hist1 <= 0; hist2 <= 0; hist3 <= 0;
                hist4 <= 0; hist5 <= 0; hist6 <= 0; hist7 <= 0;
                if (I_valid) begin
                    case (I_luma[5:3])
                        3'd0: hist0 <= 1;
                        3'd1: hist1 <= 1;
                        3'd2: hist2 <= 1;
                        3'd3: hist3 <= 1;
                        3'd4: hist4 <= 1;
                        3'd5: hist5 <= 1;
                        3'd6: hist6 <= 1;
                        default: hist7 <= 1;
                    endcase
                end
                luma_sum <= I_valid ? {{(SUM_W-6){1'b0}}, I_luma} : 0;
                phase <= (I_valid && (SAMPLE_LOG2 != 0)) ? 1 : 0;
            end else if (frame_armed) begin
                if (!I_enable) frame_enabled <= 0;
                if (I_valid) begin
                    if (SAMPLE_LOG2 != 0) phase <= phase + 1'b1;
                    if (phase == 0) begin
                        if (sample_count < EXPECTED_SAMPLES) begin
                            luma_sum <= luma_sum + {{(SUM_W-6){1'b0}}, I_luma};
                            sample_count <= sample_count + 1'b1;
                            if (I_luma >= NEAR_CLIP_LUMA)
                                near_clip_count <= near_clip_count + 1'b1;
                            if (I_luma >= HEADROOM_LUMA)
                                headroom_count <= headroom_count + 1'b1;
                            if (I_luma <= SHADOW_LUMA)
                                shadow_count <= shadow_count + 1'b1;
                            case (I_luma[5:3])
                                3'd0: hist0 <= hist0 + 1'b1;
                                3'd1: hist1 <= hist1 + 1'b1;
                                3'd2: hist2 <= hist2 + 1'b1;
                                3'd3: hist3 <= hist3 + 1'b1;
                                3'd4: hist4 <= hist4 + 1'b1;
                                3'd5: hist5 <= hist5 + 1'b1;
                                3'd6: hist6 <= hist6 + 1'b1;
                                default: hist7 <= hist7 + 1'b1;
                            endcase
                        end else begin
                            // 异常长帧不得让统计回绕后伪装成合法帧。
                            overflow <= 1;
                        end
                    end
                end
            end
        end
    end
endmodule
