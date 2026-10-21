`timescale 1ns/1ps
// Invert only CH0 sync bits in control periods and identified data islands.
// Combinational output: no additional pixel latency, CH1/CH2/clock untouched.
module hdmi_sync_polarity (
    input wire pixel_clk, rst,
    input wire [9:0] ch0, ch1, ch2,
    output reg [9:0] out_ch0
);
    function is_control;
        input [9:0] word;
        begin
            is_control = word == 10'h354 || word == 10'h0ab ||
                         word == 10'h154 || word == 10'h2ab;
        end
    endfunction
    localparam IDLE=2'd0, LEAD=2'd1, PAYLOAD=2'd2, TRAIL=2'd3;
    reg [1:0] state = IDLE;
    reg preamble_last = 0;
    reg [4:0] packet_position = 0;
    wire preamble = is_control(ch0) && ch1 == 10'h0ab && ch2 == 10'h0ab;
    wire guard = ch1 == 10'h133 && ch2 == 10'h133;
    wire leading = guard && preamble_last;
    wire control_period = is_control(ch0) && is_control(ch1) && is_control(ch2);
    wire payload_period = (state == LEAD || state == PAYLOAD) && !guard;
    wire bit3_low_codes = payload_period; // Trial: every island payload symbol has bit3=1.
    wire bit3_high_codes = 1'b1; // Preserve high bit3 in guards; force high in payload.
    wire island_period = leading || state == LEAD || state == PAYLOAD || (state == TRAIL && guard);
    always @(posedge pixel_clk) begin
        if (rst) begin state <= IDLE; preamble_last <= 0; packet_position <= 0; end
        else begin
            preamble_last <= preamble;
            if (leading || guard || state == IDLE || state == TRAIL)
                packet_position <= 0;
            else if (payload_period)
                packet_position <= packet_position + 1'b1;
            case (state)
                IDLE: if (leading) state <= LEAD;
                LEAD: if (!guard) state <= PAYLOAD;
                PAYLOAD: if (guard) state <= TRAIL;
                TRAIL: if (!guard) state <= IDLE;
            endcase
        end
    end
    always @* begin
        out_ch0 = ch0;
        if (control_period) begin
            case (ch0)
                10'h354: out_ch0 = 10'h2ab;
                10'h0ab: out_ch0 = 10'h154;
                10'h154: out_ch0 = 10'h0ab;
                10'h2ab: out_ch0 = 10'h354;
                default: out_ch0 = ch0;
            endcase
        end else if (island_period) begin
            // Preserve header bit2, invert sync bits, set payload bit3 high for this experiment.
            // Guard-band bit3 is preserved; only payload bit3 is forced high.
            case (ch0)
                10'h29c: out_ch0 = bit3_low_codes ? 10'h2c6 : 10'h2e2;
                10'h263: out_ch0 = bit3_low_codes ? 10'h19c : 10'h2e4;
                10'h2e4: out_ch0 = bit3_low_codes ? 10'h139 : 10'h263;
                10'h2e2: out_ch0 = bit3_low_codes ? 10'h2cc : 10'h29c;
                10'h171: out_ch0 = bit3_low_codes ? 10'h2c3 : 10'h13c;
                10'h11e: out_ch0 = bit3_low_codes ? 10'h163 : 10'h18e;
                10'h18e: out_ch0 = bit3_low_codes ? 10'h271 : 10'h11e;
                10'h13c: out_ch0 = bit3_low_codes ? 10'h28e : 10'h171;
                10'h2cc: out_ch0 = bit3_high_codes ? 10'h2c6 : 10'h2e2;
                10'h139: out_ch0 = bit3_high_codes ? 10'h19c : 10'h2e4;
                10'h19c: out_ch0 = bit3_high_codes ? 10'h139 : 10'h263;
                10'h2c6: out_ch0 = bit3_high_codes ? 10'h2cc : 10'h29c;
                10'h28e: out_ch0 = bit3_high_codes ? 10'h2c3 : 10'h13c;
                10'h271: out_ch0 = bit3_high_codes ? 10'h163 : 10'h18e;
                10'h163: out_ch0 = bit3_high_codes ? 10'h271 : 10'h11e;
                10'h2c3: out_ch0 = bit3_high_codes ? 10'h28e : 10'h171;
                default: out_ch0 = ch0;
            endcase
        end
    end
endmodule
