// Passive frame-age observer. No pixel, FIFO, DDR command or ready signal is
// generated here. The slot hooks are the EXACT events used by video_in/out.
// 6667 cycles at the existing 66.666667 MHz user clock = 100.005 us.
// Saturating ages avoid timestamp wrap when the camera stops or a slot repeats.
(* dsp_style = "no" *)
module video_latency_monitor #(
    parameter integer TICK_CYCLES = 6667
)(
    input wire I_rst_n,
    input wire I_ddr_clk,
    input wire I_camera_toggle,
    input wire I_write_start,
    input wire [1:0] I_write_slot,
    input wire I_read_start,
    input wire [1:0] I_read_slot,
    input wire I_pixel_clk,
    input wire I_output_vs,
    input wire I_output_de,
    output wire [15:0] O_bcd,
    output wire O_valid
);
    localparam integer CW = (TICK_CYCLES < 2) ? 1 : $clog2(TICK_CYCLES);
    localparam [13:0] EXPIRED = 14'd10000;
    reg [CW-1:0] tick_count;
    wire tick = (tick_count == TICK_CYCLES - 1);
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if (!I_rst_n) tick_count <= 0;
        else if (tick) tick_count <= 0;
        else tick_count <= tick_count + 1'b1;
    end

    // Only one event per frame crosses each boundary, using toggle + two FFs.
    (* async_reg = "true", preserve = "true" *) reg camera_s1, camera_s2;
    (* async_reg = "true", preserve = "true" *) reg output_s1, output_s2;
    reg camera_seen, output_seen;
    wire camera_event = camera_s2 ^ camera_seen;
    wire output_event = output_s2 ^ output_seen;
    (* preserve = "true" *) reg output_toggle;
    reg output_armed;
    always @(posedge I_pixel_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            output_toggle <= 0;
            output_armed <= 0;
        end else if (I_output_vs) begin
            output_armed <= 1;
        end else if (I_output_de && output_armed) begin
            // The first active output pixel, once per complete display frame.
            output_toggle <= ~output_toggle;
            output_armed <= 0;
        end
    end
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            camera_s1 <= 0; camera_s2 <= 0; camera_seen <= 0;
            output_s1 <= 0; output_s2 <= 0; output_seen <= 0;
        end else begin
            camera_s1 <= I_camera_toggle; camera_s2 <= camera_s1;
            camera_seen <= camera_s2;
            output_s1 <= output_toggle; output_s2 <= output_s1;
            output_seen <= output_s2;
        end
    end

    reg [13:0] camera_age;
    reg camera_pending;
    reg [13:0] slot_age [0:3];
    reg [3:0] slot_complete;
    reg [1:0] pending_slot;
    reg pending_valid;
    reg [13:0] selected_age;
    reg [1:0] selected_slot;
    reg selected_valid;
    // The next camera-frame event commits the previous slot's metadata. A
    // partially acquired/startup frame must never produce a plausible latency.
    integer k;
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            camera_age <= EXPIRED; camera_pending <= 0;
            slot_complete <= 0; pending_slot <= 0; pending_valid <= 0;
            selected_age <= EXPIRED; selected_slot <= 0; selected_valid <= 0;
            for (k = 0; k < 4; k = k + 1) slot_age[k] <= EXPIRED;
        end else begin
            if (tick) begin
                if (camera_age < EXPIRED) camera_age <= camera_age + 1'b1;
                if (selected_age < EXPIRED) selected_age <= selected_age + 1'b1;
                for (k = 0; k < 4; k = k + 1)
                    if (slot_age[k] < EXPIRED) slot_age[k] <= slot_age[k] + 1'b1;
            end
            if (camera_event) begin
                camera_age <= 0;
                camera_pending <= 1;
            end
            if (I_write_start) begin
                if (pending_valid && pending_slot != I_write_slot)
                    slot_complete[pending_slot] <= 1;
                slot_complete[I_write_slot] <= 0;
                slot_age[I_write_slot] <= camera_event ? 14'd0 :
                    ((tick && camera_age < EXPIRED) ? camera_age + 1'b1 : camera_age);
                pending_slot <= I_write_slot;
                pending_valid <= camera_event || (camera_pending && camera_age < EXPIRED);
                camera_pending <= 0;
                if (selected_slot == I_write_slot) selected_valid <= 0;
            end
            if (I_read_start) begin
                // Capture the slot chosen by video_out NOW, not its later rp.
                selected_age <= (tick && slot_age[I_read_slot] < EXPIRED) ?
                                slot_age[I_read_slot] + 1'b1 : slot_age[I_read_slot];
                selected_slot <= I_read_slot;
                selected_valid <= slot_complete[I_read_slot] &&
                    !(I_write_start && I_write_slot == I_read_slot);
            end
        end
    end

    // Binary tenths of a millisecond -> packed decimal, one bit per cycle.
    // All arithmetic is small add/compare/shift; there is no multiplier/divider.
    reg [13:0] binary_work;
    reg [15:0] bcd_work;
    reg [4:0] bits_left;
    reg [16:0] result;
    reg [15:0] bcd_adjust;
    integer d;
    always @(*) begin
        bcd_adjust = bcd_work;
        for (d = 0; d < 4; d = d + 1)
            if (bcd_work[d*4 +: 4] >= 5)
                bcd_adjust[d*4 +: 4] = bcd_work[d*4 +: 4] + 4'd3;
    end
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            binary_work <= 0; bcd_work <= 0; bits_left <= 0; result <= 0;
        end else if (output_event) begin
            if (selected_valid && selected_age < EXPIRED &&
                !(tick && selected_age == 14'd9999) &&
                !(I_read_start || (I_write_start && I_write_slot == selected_slot))) begin
                binary_work <= selected_age + (tick ? 14'd1 : 14'd0);
                bcd_work <= 0;
                bits_left <= 14;
            end else begin
                result <= 0; // invalid / expired => LAT ---.- MS placeholder
                bits_left <= 0;
            end
        end else if (bits_left != 0) begin
            bcd_work <= {bcd_adjust[14:0], binary_work[13]};
            binary_work <= {binary_work[12:0], 1'b0};
            bits_left <= bits_left - 1'b1;
            if (bits_left == 1)
                result <= {1'b1, bcd_adjust[14:0], binary_work[13]};
        end
    end

    // Transfer only complete measurements. osd_overlay latches the result at
    // vertical blanking, so digits show a completed frame without tearing.
    wire [16:0] display_result;
    demo_control_cdc #(.WIDTH(17), .INITIAL(17'd0)) u_result_cdc (
        .I_src_clk(I_ddr_clk), .I_src_rst_n(I_rst_n),
        .I_src_data(result), .I_src_valid(1'b1),
        .I_dst_clk(I_pixel_clk), .I_dst_rst_n(I_rst_n),
        .I_dst_apply(1'b1), .O_dst_data(display_result), .O_dst_valid()
    );
    assign O_valid = display_result[16];
    assign O_bcd = display_result[15:0];
endmodule
