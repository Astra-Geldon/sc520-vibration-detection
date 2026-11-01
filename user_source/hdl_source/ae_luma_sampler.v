// Passive, unweighted exposure metering before AWB/Gamma. Every valid beat
// contributes to the decimation phase; no skin/saturation rejection is used.
// The default 4-pixel stream samples one pixel per 16 beats (1/64 of 720p).
(* dsp_style = "no" *)
module ae_luma_sampler #(
    parameter integer EXPECTED_SAMPLES = 14400,
    parameter integer LOW_LUMA = 16,
    parameter integer HIGH_LUMA = 24,
    parameter integer SAMPLE_LOG2 = 4
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire I_frame_start,
    input wire I_valid,
    input wire I_enable,
    input wire [5:0] I_luma,
    // {new-frame sequence, classification}: normal/dark/bright/invalid.
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

    reg [COUNT_W-1:0] sample_count;
    reg [SUM_W-1:0] luma_sum;
    reg [PHASE_W-1:0] phase;
    reg frame_armed, frame_enabled, overflow, frame_start_d;
    wire frame_start = I_frame_start && !frame_start_d;
    wire frame_complete = frame_enabled && !overflow &&
                          (sample_count == EXPECTED_SAMPLES) && (phase == 0);
    wire [1:0] classification = !frame_complete ? 2'b11 :
                                ((luma_sum < LOW_SUM) ? 2'b01 :
                                 ((luma_sum > HIGH_SUM) ? 2'b10 : 2'b00));

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sample_count <= 0;
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
                    // Invalid frames also advance the sequence: the receiver
                    // must distinguish fresh invalid data from a stopped input.
                    O_measure <= {O_measure[5:2] + 4'd1, classification};
                    O_valid <= 1;
                end
                frame_armed <= 1;
                frame_enabled <= I_enable;
                overflow <= 0;
                // Frame-start may be coincident with the first valid beat.
                sample_count <= I_valid ? 1 : 0;
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
                        end else begin
                            // Never wrap the counter or sum on a malformed
                            // long frame, which could otherwise look valid.
                            overflow <= 1;
                        end
                    end
                end
            end
        end
    end
endmodule
