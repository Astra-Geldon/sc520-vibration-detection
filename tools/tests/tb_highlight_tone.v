`timescale 1ns/1ps

// Independent arithmetic/property checks plus moving video and real debounce
// timing. The sensor clock is 24 MHz, UI clock is 75 MHz; debounce counters
// are NOT forced, accelerated, or overridden.
module tb_highlight_tone;
    reg de = 0, enable = 0;
    reg [2:0] sel = 0;
    reg [23:0] rgb = 0;
    wire mask;
    wire [23:0] shown;
    highlight_tone dut (
        .I_de(de), .I_enable(enable), .I_sel(sel), .I_data(rgb),
        .O_mask(mask), .O_data(shown)
    );

    wire [23:0] old_max_shown;
    highlight_tone_previous previous_max (
        .I_de(de), .I_enable(enable), .I_sel(3'd3), .I_data(rgb),
        .O_mask(), .O_data(old_max_shown)
    );

    integer pixel_checks = 0, property_checks = 0;
    integer frame_index, x, y, hit, frame_hits;
    integer candidate, gray, r, g, b, ray, level, sample;
    integer previous_peak, actual_peak, previous_gray;
    integer out_r, out_g, out_b, in_max;
    integer weak_r, weak_g, weak_b, middle_r, middle_g, middle_b;
    integer seed = 32'h524f4931;
    reg [23:0] vector;
    reg pixels_done = 0, controls_done = 0;

    // Floating-point reference states the curve mathematically; it does not
    // reproduce RTL slices, width-limited products, or saturation branches.
    function integer reference_channel;
        input integer c, peak, choice;
        real scale, result;
        begin
            scale = 0.0;
            if (peak < 208) begin
                case (choice)
                    1: scale = (208-peak)/256.0;
                    2: scale = (208-peak)/256.0 + (208-peak)*(208-peak)/65536.0;
                    3: scale = (208-peak)/256.0 + 2.0*(208-peak)*(208-peak)/65536.0;
                endcase
            end
            result = c * (1.0 + scale);
            reference_channel = $rtoi($floor(result + 0.5));
        end
    endfunction

    function integer max3;
        input integer a, b, c;
        integer ab;
        begin
            ab = a > b ? a : b;
            max3 = ab > c ? ab : c;
        end
    endfunction

    function integer absolute;
        input integer value;
        begin absolute = value < 0 ? -value : value; end
    endfunction

    task check_pixel;
        input pixel_de, pixel_enable;
        input [2:0] choice;
        input [23:0] value;
        integer a, bb, c, peak, expected_r, expected_g, expected_b;
        reg expected_mask;
        reg [23:0] expected_pixel;
        begin
            a = value[23:16]; bb = value[15:8]; c = value[7:0];
            peak = max3(a, bb, c);
            expected_mask = pixel_de && pixel_enable &&
                            ((a + 2*bb + c >= 832) || peak >= 250);
            expected_r = reference_channel(a, peak, choice);
            expected_g = reference_channel(bb, peak, choice);
            expected_b = reference_channel(c, peak, choice);
            expected_pixel = {expected_r[7:0], expected_g[7:0], expected_b[7:0]};
            if (!pixel_de || !pixel_enable || choice == 0 || choice > 4 || expected_mask)
                expected_pixel = value;
            if (pixel_de && pixel_enable && choice == 4 && expected_mask)
                expected_pixel = 24'hff00ff;

            de = pixel_de; enable = pixel_enable; sel = choice; rgb = value;
            #1;
            pixel_checks = pixel_checks + 1;
            if (mask !== expected_mask || shown !== expected_pixel)
                $fatal(1, "Tone mismatch n=%0d sel=%0d de/en=%0b/%0b in=%06x mask=%0b/%0b shown=%06x wanted=%06x",
                       pixel_checks, choice, pixel_de, pixel_enable, value,
                       mask, expected_mask, shown, expected_pixel);

            if (choice == 1 && shown !== old_max_shown)
                $fatal(1, "New C1 differs from previous C3: RGB=%06x new=%06x old=%06x",value,shown,old_max_shown);

            // Independent properties catch common-channel hue or overflow
            // failures even if a future arithmetic reference is edited.
            if (pixel_de && pixel_enable && choice >= 1 && choice <= 3) begin
                out_r = shown[23:16]; out_g = shown[15:8]; out_b = shown[7:0];
                if (out_r < a || out_g < bb || out_b < c)
                    $fatal(1, "Midtone compensation unexpectedly darkened a channel");
                if (peak < 208 && max3(out_r, out_g, out_b) > 208)
                    $fatal(1, "Compensation crossed protected shoulder / introduced clipping");
                if (peak >= 208 && shown !== value)
                    $fatal(1, "Protected high-channel pixel was modified");
                if (2*absolute(out_r*bb - out_g*a) > a + bb ||
                    2*absolute(out_r*c - out_b*a) > a + c ||
                    2*absolute(out_g*c - out_b*bb) > bb + c)
                    $fatal(1, "RGB common-gain ratio exceeded half-code rounding bound");
                if ((a == 0 && out_r != 0) || (bb == 0 && out_g != 0) ||
                    (c == 0 && out_b != 0))
                    $fatal(1, "Zero input channel developed a tint");
                property_checks = property_checks + 1;
            end
        end
    endtask

    // Real, independent physical-key timing for both production clock domains.
    reg ui_clk = 0, sensor_clk = 0;
    reg clocks_running = 1;
    always #6.666667 if (clocks_running) ui_clk = ~ui_clk;
    always #20.833333 if (clocks_running) sensor_clk = ~sensor_clk;
    reg rst_n = 1;
    reg [3:0] keys = 4'b1111;
    wire [2:0] mode, tone_choice;
    wire [1:0] exposure_choice;
    wire src_raw, th_lock, k_step;
    img_mode_sel #(
        .MODE_RST(0), .EXP_RST(3), .REGION_RST(2), .REGION_N(5),
        .CLK_HZ(75000000), .DB_MS(10)
    ) ui (
        .I_clk(ui_clk), .I_rst_n(rst_n), .I_key_n(keys),
        .O_mode(mode), .O_src_raw(src_raw), .O_exp_sel(exposure_choice),
        .O_region_sel(tone_choice), .O_th_lock(th_lock), .O_k_step(k_step)
    );
    reg cam_done = 0, ae_done = 0;
    wire ae_req;
    wire [15:0] exposure, gain;
    integer ae_requests = 0;
    integer expected_request_exposure;
    ae_set #(.EXP_RST(3)) sensor_controls (
        .I_clk(sensor_clk), .I_rst(~rst_n), .I_btn(4'b1111),
        .I_exp_key_n(keys[2]), .I_cam_cfg_done(cam_done),
        .I_ae_cfg_done(ae_done), .O_ae_req(ae_req),
        .O_ae(exposure), .O_ag(gain)
    );
    always @(posedge sensor_clk) begin
        #1;
        if (rst_n && ae_req) begin
            case (ae_requests)
                0: expected_request_exposure = 900;
                1: expected_request_exposure = 1991;
                2: expected_request_exposure = 1600;
                3: expected_request_exposure = 1200;
                4: expected_request_exposure = 900;
                5: expected_request_exposure = 1991; // simultaneous KEY3+KEY4
                default: $fatal(1, "Unexpected repeated AE request %0d", ae_requests);
            endcase
            if (!cam_done || !ae_done || exposure !== expected_request_exposure || gain !== 160)
                $fatal(1, "AE request %0d mismatch: cfg=%0b/%0b AE=%0d wanted=%0d AG=%0d",
                       ae_requests, cam_done, ae_done, exposure, expected_request_exposure, gain);
            ae_requests = ae_requests + 1;
        end
    end

    task check_ui;
        input integer wanted_mode, wanted_exp, wanted_tone;
        begin
            if (mode !== wanted_mode || exposure_choice !== wanted_exp || tone_choice !== wanted_tone)
                $fatal(1, "UI mismatch mode/exp/C=%0d/%0d/%0d wanted=%0d/%0d/%0d",
                       mode, exposure_choice, tone_choice, wanted_mode, wanted_exp, wanted_tone);
            if (src_raw !== 0 || th_lock !== 0 || k_step !== 0)
                $fatal(1, "Candidate key affected original image source / shading / threshold controls");
        end
    endtask

    task press_key;
        input integer key_index;
        input integer hold_ns;
        begin
            @(negedge ui_clk); keys[key_index] = 0;
            #(hold_ns);
            @(negedge ui_clk); keys[key_index] = 1;
            #11000000;
        end
    endtask

    initial begin : controller_checks
        #1 rst_n = 0;
        #1000 rst_n = 1;
        #2000;
        check_ui(0, 3, 2);
        if (ae_requests != 0) $fatal(1, "AE ran with camera/AE configuration incomplete");
        cam_done = 1;
        #2000;
        if (ae_requests != 0) $fatal(1, "AE ignored AE configuration busy state");
        ae_done = 1;
        #2000;
        if (ae_requests != 1 || exposure !== 900 || gain !== 160)
            $fatal(1, "Configured startup did not request AE900/AG160 exactly once");

`ifdef PIXELS_AND_STARTUP
        #2000;
        if (ae_requests != 1) $fatal(1, "AE900 startup repeated without an exposure change");
        $display("PASS startup: gated real AE900/AG160 once; top/UI reset original3/C2");
        controls_done = 1;
        clocks_running = 0;
`else
        // 2 ms physical bounce is below both real debounce thresholds.
        repeat (3) begin
            keys[3] = 0; #2000000; keys[3] = 1; #2000000;
            keys[2] = 0; #2000000; keys[2] = 1; #2000000;
        end
        #11000000;
        check_ui(0, 3, 2);
        if (ae_requests != 1) $fatal(1, "Sensor accepted a short bounce as exposure key");

        // Long hold must produce only one candidate transition.
        press_key(3, 25000000); check_ui(0, 3, 3);
        press_key(3, 11000000); check_ui(0, 3, 4);
        press_key(3, 11000000); check_ui(0, 3, 0);
        press_key(3, 11000000); check_ui(0, 3, 1);
        press_key(3, 11000000); check_ui(0, 3, 2);

        press_key(2, 25000000); check_ui(0, 0, 2);
        if (ae_requests != 2 || exposure !== 1991) $fatal(1, "KEY3 hold did not select real exposure1991 once");
        press_key(2, 11000000); check_ui(0, 1, 2);
        press_key(2, 11000000); check_ui(0, 2, 2);
        press_key(2, 11000000); check_ui(0, 3, 2);
        if (ae_requests != 5 || exposure !== 900) $fatal(1, "KEY3 UI/sensor four-state cycle diverged");

        press_key(1, 11000000); check_ui(1, 3, 2);
        press_key(1, 11000000); check_ui(2, 3, 2);
        press_key(1, 11000000); check_ui(3, 3, 2);
        press_key(1, 11000000); check_ui(1, 3, 2);
        press_key(0, 11000000); check_ui(0, 3, 2);

        @(negedge ui_clk); keys[3:2] = 2'b00;
        #11000000;
        @(negedge ui_clk); keys[3:2] = 2'b11;
        #11000000;
        check_ui(0, 0, 3);
        if (ae_requests != 6 || exposure !== 1991)
            $fatal(1, "Simultaneous KEY3/4 did not maintain independent sensor/UI controls");
        $display("PASS keys: actual75MHz UI / actual24MHz sensor, five-state KEY4, bounce/long hold, KEY1/2 and simultaneous KEY3+KEY4");
        $display("PASS sensor: busy/config-gated AE900/AG160 startup once; KEY3 actual sequence900->1991->1600->1200->900->1991");
        controls_done = 1;
        clocks_running = 0;
`endif
    end

    initial begin : pixel_checks_block
        // Entire grayscale ramps prove monotonic shoulder and candidate order.
        for (candidate = 0; candidate <= 3; candidate = candidate + 1) begin
            previous_gray = -1;
            for (gray = 0; gray < 256; gray = gray + 1) begin
                check_pixel(1, 1, candidate, {gray[7:0], gray[7:0], gray[7:0]});
                if ((previous_gray >= 0 && shown[23:16] < previous_gray) ||
                    shown[23:16] !== shown[15:8] || shown[15:8] !== shown[7:0])
                    $fatal(1, "Gray curve inverted or acquired a tint at %0d C%0d", gray, candidate);
                previous_gray = shown[23:16];
            end
        end

        // Color cube includes skin-like ratios, saturated channels and corners.
        for (r = 0; r <= 255; r = r + 17)
            for (g = 0; g <= 255; g = g + 17)
                for (b = 0; b <= 255; b = b + 17) begin
                    vector = {r[7:0], g[7:0], b[7:0]};
                    check_pixel(1, 1, 1, vector);
                    weak_r = shown[23:16]; weak_g = shown[15:8]; weak_b = shown[7:0];
                    check_pixel(1, 1, 2, vector);
                    middle_r = shown[23:16]; middle_g = shown[15:8]; middle_b = shown[7:0];
                    if (middle_r < weak_r || middle_g < weak_g || middle_b < weak_b)
                        $fatal(1, "Medium compensation was weaker than weak candidate");
                    check_pixel(1, 1, 3, vector);
                    if (shown[23:16] < middle_r || shown[15:8] < middle_g || shown[7:0] < middle_b)
                        $fatal(1, "Strong compensation was weaker than medium candidate");
                    check_pixel(1, 1, 4, vector);
                end

        // Several rays retain their chromatic direction across all peak levels.
        for (candidate = 1; candidate <= 3; candidate = candidate + 1)
            for (ray = 0; ray < 7; ray = ray + 1) begin
                previous_peak = -1;
                for (level = 0; level <= 255; level = level + 1) begin
                    case (ray)
                        0: begin r=level; g=0; b=0; end
                        1: begin r=0; g=level; b=0; end
                        2: begin r=0; g=0; b=level; end
                        3: begin r=level; g=level*3/4; b=level/2; end
                        4: begin r=level/2; g=level; b=level*3/4; end
                        5: begin r=level*3/4; g=level/2; b=level; end
                        6: begin r=level; g=level; b=level/2; end
                    endcase
                    check_pixel(1, 1, candidate, {r[7:0], g[7:0], b[7:0]});
                    actual_peak = max3(shown[23:16], shown[15:8], shown[7:0]);
                    if (actual_peak < previous_peak) $fatal(1, "Peak curve inverted on chromatic ray");
                    previous_peak = actual_peak;
                end
            end

        // Exact threshold edges and all invalid/disable/blank combinations.
        for (candidate = 0; candidate < 8; candidate = candidate + 1) begin
            check_pixel(1, 1, candidate, 24'hcfd0d0); // Y4=831
            check_pixel(1, 1, candidate, 24'hd0d0d0); // Y4=832
            check_pixel(1, 1, candidate, 24'hf90000); // max=249
            check_pixel(1, 1, candidate, 24'hfa0000); // max=250
            check_pixel(1, 1, candidate, 24'h00fa00);
            check_pixel(1, 1, candidate, 24'h0000fa);
            check_pixel(1, 1, candidate, 24'h000000);
            check_pixel(1, 1, candidate, 24'hffffff);
            check_pixel(0, 1, candidate, 24'hffffff);
            check_pixel(1, 0, candidate, 24'hffffff);
            check_pixel(0, 0, candidate, 24'h4c382c);
            check_pixel(0, 1, candidate, 24'h4c382c);
            check_pixel(1, 0, candidate, 24'h4c382c);
        end
        for (sample = 0; sample < 20000; sample = sample + 1) begin
            vector = $random(seed);
            for (candidate = 0; candidate < 8; candidate = candidate + 1)
                check_pixel(1, 1, candidate, vector);
        end
        $display("PASS colors: %0d samples; all gray codes, color cube, chromatic rays, clipping boundaries, invalid/disable/blank, ratio bound", pixel_checks);

        // Consecutive complete frames move three high-risk regions over a
        // skin-like background. Selection follows current geometry, so former
        // object locations must immediately return to the compensated skin.
        for (frame_index = 0; frame_index < 3; frame_index = frame_index + 1) begin
            frame_hits = 0;
            for (y = 0; y < 720; y = y + 1) begin
                for (x = 0; x < 1280; x = x + 1) begin
                    hit =
                        (x >= 40+120*frame_index && x < 136+120*frame_index &&
                         y >= 50+80*frame_index && y < 98+80*frame_index) ||
                        (x >= 400+120*frame_index && x < 480+120*frame_index &&
                         y >= 260+70*frame_index && y < 300+70*frame_index) ||
                        (x >= 850+120*frame_index && x < 914+120*frame_index &&
                         y >= 480+50*frame_index && y < 536+50*frame_index);
                    check_pixel(1, 1, frame_index+1, hit ? 24'hffffff : 24'h6e503f);
                    if (mask !== (hit != 0)) $fatal(1, "Moving-frame geometry disagrees with H1 mask");
                    if (mask) frame_hits = frame_hits + 1;
                end
                repeat (3) check_pixel(0, 1, frame_index+1, 24'hffffff);
            end
            if (frame_hits != 11392) $fatal(1, "Moving frame area mismatch %0d", frame_hits);
            repeat (20) check_pixel(0, 1, frame_index+1, 24'h6e503f);
            $display("PASS frame %0d: complete1280x720, 11392 moving H1 pixels, midtone restoration outside mask, no trail", frame_index);
        end
        $display("PASS tone_pixels: %0d checked pixel/blank cycles; %0d hue/shoulder/no-clipping property checks", pixel_checks, property_checks);
        pixels_done = 1;
    end

    initial begin
        wait (pixels_done && controls_done);
        $display("PASS highlight_tone: pixel math/properties/video and real-clock sensor/UI controls");
        $finish;
    end
    initial begin
        #500000000;
        $fatal(1, "Tone test timed out");
    end
endmodule
