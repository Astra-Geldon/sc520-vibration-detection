// AWB/Gamma前的独立测光，不使用显示端补亮结果作为曝光反馈。
// 默认每16个四像素包抽取一个像素，保留原完整帧校验及序号协议。
// 明暗并存时使用亮端60/48的死区约束曝光，避免刚解除饱和就重新加曝。
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
    parameter integer SHADOW_MEAN_FLOOR = 8
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

    reg [COUNT_W-1:0] sample_count;
    reg [COUNT_W-1:0] near_clip_count, headroom_count, shadow_count;
    reg [SUM_W-1:0] luma_sum;
    reg [PHASE_W-1:0] phase;
    reg frame_armed, frame_enabled, overflow, frame_start_d;
    wire frame_start = I_frame_start && !frame_start_d;
    wire frame_complete = frame_enabled && !overflow &&
                          (sample_count == EXPECTED_SAMPLES) && (phase == 0);
    wire mixed_scene = (HIGHLIGHT_GUARD != 0) &&
                       (headroom_count >= HIGHLIGHT_COUNT) &&
                       (shadow_count >= SHADOW_COUNT);
    wire highlight_pressure = mixed_scene &&
                              (near_clip_count >= HIGHLIGHT_COUNT) &&
                              (luma_sum >= SHADOW_FLOOR_SUM);
    // 亮端仍有明显覆盖时，禁止原均值AE因暗部而反向加曝。
    // 整体已经过暗时只保持，不再为了高光继续降低曝光。
    wire [1:0] classification = !frame_complete ? 2'b11 :
                                (highlight_pressure ? 2'b10 :
                                 ((luma_sum < LOW_SUM) ?
                                  (mixed_scene ? 2'b00 : 2'b01) :
                                  ((luma_sum > HIGH_SUM) ? 2'b10 : 2'b00)));

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sample_count <= 0;
            near_clip_count <= 0;
            headroom_count <= 0;
            shadow_count <= 0;
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
