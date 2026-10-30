`timescale 1ns/1ps

// Behavioral contract checks for the streaming mask and its physical-key UI.
// Three complete 1280x720 frames move three disconnected highlight objects;
// every output pixel is checked against object geometry, not an RTL replica.
module tb_highlight_region;
    reg de = 0;
    reg enable = 0;
    reg [1:0] sel = 0;
    reg [23:0] source = 0;
    reg [23:0] display_data = 0;
    wire mask;
    wire [23:0] result;
    integer pixel_checks = 0;
    integer color_checks = 0;
    integer frame_index, x, y, object_hit, frame_hits;
    integer gray, selection;
    integer gray_hits;

    highlight_region dut (
        .I_de(de), .I_enable(enable), .I_sel(sel),
        .I_source(source), .I_data(display_data),
        .O_mask(mask), .O_data(result)
    );

    reg clk = 0;
    reg run_clock = 1;
    always #5 if (run_clock) clk = ~clk;
    reg rst_n = 1;
    reg [3:0] key_n = 4'b1111;
    wire [2:0] mode;
    wire [1:0] exp_sel, region_sel;
    wire src_raw, th_lock, k_step;
    img_mode_sel #(
        .MODE_RST(0), .EXP_RST(0), .REGION_RST(1),
        .CLK_HZ(1000), .DB_MS(1)
    ) ui (
        .I_clk(clk), .I_rst_n(rst_n), .I_key_n(key_n),
        .O_mode(mode), .O_src_raw(src_raw), .O_exp_sel(exp_sel),
        .O_region_sel(region_sel), .O_th_lock(th_lock), .O_k_step(k_step)
    );

    reg cam_cfg_done = 0;
    reg ae_cfg_done = 1;
    wire ae_req;
    wire [15:0] exposure, gain;
    integer ae_requests = 0;
    ae_set sensor_controls (
        .I_clk(clk), .I_rst(~rst_n), .I_btn(4'b1111),
        .I_exp_key_n(1'b1), .I_cam_cfg_done(cam_cfg_done),
        .I_ae_cfg_done(ae_cfg_done), .O_ae_req(ae_req),
        .O_ae(exposure), .O_ag(gain)
    );
    always @(posedge clk) begin
        #1;
        if (rst_n && ae_req) begin
            ae_requests = ae_requests + 1;
            if (!cam_cfg_done || exposure !== 16'd1991 || gain !== 16'd160)
                $fatal(1, "Wrong initial sensor request: ae=%0d ag=%0d cfg=%0b",
                       exposure, gain, cam_cfg_done);
        end
    end

    task check_pixel;
        input pixel_de, pixel_enable;
        input [1:0] candidate;
        input [23:0] rgb, shown;
        input expected_mask;
        begin
            de = pixel_de;
            enable = pixel_enable;
            sel = candidate;
            source = rgb;
            display_data = shown;
            #1;
            pixel_checks = pixel_checks + 1;
            if (mask !== expected_mask)
                $fatal(1, "Mask mismatch check=%0d sel=%0d rgb=%06x expected=%0b got=%0b",
                       pixel_checks, candidate, rgb, expected_mask, mask);
            if (result !== (expected_mask ? 24'hff00ff : shown))
                $fatal(1, "Pixel pass/marker mismatch check=%0d shown=%06x got=%06x mask=%0b",
                       pixel_checks, shown, result, expected_mask);
        end
    endtask

    task cycles;
        input integer count;
        integer c;
        begin
            for (c = 0; c < count; c = c + 1) begin
                @(posedge clk); #2;
            end
        end
    endtask

    task press_key;
        input integer key_index;
        input integer hold_cycles;
        begin
            @(negedge clk); key_n[key_index] = 0;
            cycles(hold_cycles);
            @(negedge clk); key_n[key_index] = 1;
            cycles(14);
        end
    endtask

    task check_ui;
        input [2:0] wanted_mode;
        input [1:0] wanted_exp, wanted_region;
        begin
            if (mode !== wanted_mode || exp_sel !== wanted_exp || region_sel !== wanted_region)
                $fatal(1, "UI mismatch: mode/exp/region=%0d/%0d/%0d want=%0d/%0d/%0d",
                       mode, exp_sel, region_sel, wanted_mode, wanted_exp, wanted_region);
            if (src_raw !== 0 || th_lock !== 0 || k_step !== 0)
                $fatal(1, "Region key unexpectedly changed raw/shading/threshold controls");
        end
    endtask

    initial begin
        // Force an actual reset edge, including the active-high AE reset.
        #1 rst_n = 0;
        cycles(4);
        @(negedge clk); rst_n = 1;
        cycles(14);
        check_ui(0, 0, 1);
        if (ae_requests != 0) $fatal(1, "AE wrote before camera configuration completed");
        @(negedge clk); cam_cfg_done = 1;
        cycles(14);
        if (ae_requests != 1 || exposure !== 1991 || gain !== 160)
            $fatal(1, "Original0 startup exposure/gain was not requested exactly once");

        // Single-cycle spikes must not count as KEY4 presses (CNT_MAX=1).
        repeat (3) begin
            @(negedge clk); key_n[3] = 0;
            @(negedge clk); key_n[3] = 1;
        end
        cycles(14);
        check_ui(0, 0, 1);
        // A long hold counts once. Threshold choices are independent of exposure.
        press_key(3, 100);
        check_ui(0, 0, 2);
        press_key(3, 14); check_ui(0, 0, 3);
        press_key(3, 14); check_ui(0, 0, 0);
        press_key(3, 14); check_ui(0, 0, 1);
        press_key(2, 100); check_ui(0, 1, 1);
        press_key(2, 14);  check_ui(0, 2, 1);
        press_key(2, 14);  check_ui(0, 3, 1);
        press_key(2, 14);  check_ui(0, 0, 1);
        press_key(1, 14);  check_ui(1, 0, 1);
        press_key(1, 14);  check_ui(2, 0, 1);
        press_key(1, 14);  check_ui(3, 0, 1);
        press_key(1, 14);  check_ui(1, 0, 1);
        press_key(0, 14);  check_ui(0, 0, 1);
        // KEY3 and KEY4 are deliberately independent when pressed together.
        @(negedge clk); key_n[3:2] = 0;
        cycles(14);
        @(negedge clk); key_n[3:2] = 2'b11;
        cycles(14);
        check_ui(0, 1, 2);
        if (ae_requests != 1) $fatal(1, "Unexpected repeated startup AE writes");
        $display("PASS keys: KEY4 bounce/hold/0..3, KEY3 hold/0..3, KEY1/KEY2, simultaneous KEY3+KEY4");
        $display("PASS sensor: config gating and exactly one original0 AE=1991 AG=160 request");
        run_clock = 0;

        // Neutral and colored boundary samples. Y is integer floor of
        // (R+2G+B)/4; saturated single channels are an independent risk.
        for (selection = 1; selection <= 3; selection = selection + 1) begin
            check_pixel(1, 1, selection, 24'hffffff, 24'h123456, 1);
            check_pixel(1, 1, selection, 24'h000000, 24'hffffff, 0);
            check_pixel(1, 1, selection, 24'h996652, 24'hffffff, 0);
            check_pixel(1, 1, selection, 24'hfa0000, 24'h123456, 1);
            check_pixel(1, 1, selection, 24'h00fa00, 24'h123456, 1);
            check_pixel(1, 1, selection, 24'h0000fa, 24'h123456, 1);
            check_pixel(1, 1, selection, 24'hf90000, 24'hffffff, 0);
            check_pixel(1, 1, selection, 24'h00f900, 24'hffffff, 0);
            check_pixel(1, 1, selection, 24'h0000f9, 24'hffffff, 0);
            // Whole ramp checks the complete decision span and nested masks.
            gray_hits = 0;
            for (gray = 0; gray < 256; gray = gray + 1) begin
                check_pixel(1, 1, selection, {gray[7:0], gray[7:0], gray[7:0]},
                            24'h315a7c, gray >= (192 + selection*16));
                if (mask) gray_hits = gray_hits + 1;
            end
            if (gray_hits != (64 - selection*16))
                $fatal(1, "Gray-ramp highlight area wrong: selection=%0d hits=%0d", selection, gray_hits);
        end
        // Fractional values immediately below each weighted threshold, then on it.
        check_pixel(1, 1, 1, 24'hcfd0d0, 24'h123456, 0); // Y4=831
        check_pixel(1, 1, 1, 24'hd0d0d0, 24'h123456, 1); // Y4=832
        check_pixel(1, 1, 2, 24'hdfe0e0, 24'h123456, 0); // Y4=895
        check_pixel(1, 1, 2, 24'he0e0e0, 24'h123456, 1); // Y4=896
        check_pixel(1, 1, 3, 24'heff0f0, 24'h123456, 0); // Y4=959
        check_pixel(1, 1, 3, 24'hf0f0f0, 24'h123456, 1); // Y4=960
        // No control may replace source data during blanking/off/disable.
        for (selection = 0; selection < 4; selection = selection + 1) begin
            check_pixel(0, 1, selection, 24'hffffff, 24'h123456, 0);
            check_pixel(1, 0, selection, 24'hffffff, 24'h654321, 0);
        end
        check_pixel(1, 1, 0, 24'hffffff, 24'habcd10, 0);
        color_checks = pixel_checks;
        $display("PASS colors: %0d cases including all-gray ramps, threshold edges, white overflow and channel clipping", color_checks);

        for (frame_index = 0; frame_index < 3; frame_index = frame_index + 1) begin
            frame_hits = 0;
            for (y = 0; y < 720; y = y + 1) begin
                for (x = 0; x < 1280; x = x + 1) begin
                    object_hit =
                        (x >= (40 + 120*frame_index) && x < (136 + 120*frame_index) &&
                         y >= (50 + 80*frame_index) && y < (98 + 80*frame_index)) ||
                        (x >= (400 + 120*frame_index) && x < (480 + 120*frame_index) &&
                         y >= (260 + 70*frame_index) && y < (300 + 70*frame_index)) ||
                        (x >= (850 + 120*frame_index) && x < (914 + 120*frame_index) &&
                         y >= (480 + 50*frame_index) && y < (536 + 50*frame_index));
                    check_pixel(1, 1, frame_index + 1,
                                object_hit ? 24'hffffff : 24'h996652,
                                {x[7:0], y[7:0], frame_index[7:0]}, object_hit);
                    if (mask) frame_hits = frame_hits + 1;
                end
                // Highlight-looking blank cycles must never leak a selection.
                repeat (3) check_pixel(0, 1, frame_index + 1, 24'hffffff, 24'h03ac71, 0);
            end
            if (frame_hits != 11392)
                $fatal(1, "Frame %0d mask area=%0d, expected three rectangles totaling 11392", frame_index, frame_hits);
            repeat (20) check_pixel(0, 1, frame_index + 1, 24'hffffff, 24'h029ba5, 0);
            $display("PASS frame %0d: 1280x720 active pixels, three moving regions, 11392 mask pixels, no trail", frame_index);
        end
        $display("PASS highlight_region: %0d checked pixel/blank cycles, 3 consecutive 720p frames", pixel_checks);
        $finish;
    end

    initial begin
        #10000000;
        $fatal(1, "Testbench timed out");
    end
endmodule
