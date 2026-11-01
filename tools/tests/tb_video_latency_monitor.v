`timescale 1ns/1ps
// Independent event-time/slot reference. No DUT internal state is referenced.
// Acceleration affects only the tick divider: one displayed 0.1ms unit is
// represented by 13 DDR clocks so timeout/boundary cases finish quickly.
module tb_video_latency_monitor;
    localparam integer TICK_CYCLES = 13;
    reg ddr_clk=0, pixel_clk=0, camera_clk=0;
    always #5 ddr_clk=~ddr_clk;
    initial begin #3; forever #7 pixel_clk=~pixel_clk; end
    initial begin #0.25; forever #5.5 camera_clk=~camera_clk; end

    reg rst_n=0, camera_toggle=0, write_start=0, read_start=0;
    reg [1:0] write_slot=0, read_slot=0;
    reg output_vs=0, output_de=0;
    wire [15:0] bcd;
    wire valid;
    video_latency_monitor #(.TICK_CYCLES(TICK_CYCLES)) dut (
        .I_rst_n(rst_n), .I_ddr_clk(ddr_clk), .I_camera_toggle(camera_toggle),
        .I_write_start(write_start), .I_write_slot(write_slot),
        .I_read_start(read_start), .I_read_slot(read_slot),
        .I_pixel_clk(pixel_clk), .I_output_vs(output_vs), .I_output_de(output_de),
        .O_bcd(bcd), .O_valid(valid)
    );

    integer ddr_cycles=0;
    real first_ddr_pos;
    always @(posedge ddr_clk or negedge rst_n)
        if (!rst_n) ddr_cycles=0;
        else ddr_cycles=ddr_cycles+1;

    // Frame metadata reference: source-event tick indices never increment.
    // Ages are computed only when an external output first-pixel event occurs.
    integer source_tick=0, pending_frame_slot=0;
    integer frame_tick[0:3];
    reg [3:0] complete=0;
    reg source_fresh=0, pending_frame_valid=0;
    integer selected_frame_tick=0, selected_frame_slot=0;
    reg selected_frame_valid=0;
    integer checked=0, index, frame, want_tick, actual_age, expected_age;
    reg expected_valid;
    reg [15:0] held_bcd;

    function [15:0] packed_decimal;
        input integer number;
        begin
            packed_decimal[15:12]=(number/1000)%10;
            packed_decimal[11:8]=(number/100)%10;
            packed_decimal[7:4]=(number/10)%10;
            packed_decimal[3:0]=number%10;
        end
    endfunction

    task reset_all;
        begin
            @(negedge ddr_clk);
            rst_n=0; camera_toggle=0; write_start=0; read_start=0;
            output_vs=0; output_de=0; complete=0; source_fresh=0;
            pending_frame_valid=0; selected_frame_valid=0;
            source_tick=0; pending_frame_slot=0;
            selected_frame_tick=0; selected_frame_slot=0;
            for(index=0; index<4; index=index+1) frame_tick[index]=0;
            repeat(6) @(negedge ddr_clk);
            rst_n=1;
            first_ddr_pos=$realtime+5;
            repeat(12) @(negedge ddr_clk);
            #0.1;
            if(valid !== 0) $fatal(1,"Reset retained a valid measurement");
        end
    endtask

    task camera_frame;
        begin
            @(negedge camera_clk);
            camera_toggle=~camera_toggle;
            // The toggle reaches FF1 at the next DDR edge, FF2 one edge
            // later, and the consumer detects it on the following edge.
            source_tick=(ddr_cycles+3)/TICK_CYCLES;
            source_fresh=1;
            repeat(5) @(negedge ddr_clk);
        end
    endtask

    task write_frame;
        input integer slot;
        begin
            @(negedge ddr_clk);
            write_start=1; write_slot=slot;
            if(pending_frame_valid && pending_frame_slot != slot)
                complete[pending_frame_slot]=1;
            complete[slot]=0;
            frame_tick[slot]=source_tick;
            pending_frame_valid=source_fresh &&
                (((ddr_cycles+1)/TICK_CYCLES-source_tick) < 10000);
            pending_frame_slot=slot;
            source_fresh=0;
            if(selected_frame_slot==slot) selected_frame_valid=0;
            @(negedge ddr_clk);write_start=0;
        end
    endtask

    task same_edge_camera_and_write;
        input integer slot;
        reg aligned;
        begin
            // Arrange that the consumer sees raw-frame arrival, ISP write
            // selection and the global tick boundary on exactly the same edge.
            aligned=0;
            while(!aligned) begin
                @(negedge camera_clk);
                aligned=((ddr_cycles+3)%TICK_CYCLES)==0;
            end
            camera_toggle=~camera_toggle;
            source_tick=(ddr_cycles+3)/TICK_CYCLES;
            repeat(2) @(posedge ddr_clk);
            @(negedge ddr_clk);
            write_start=1;write_slot=slot;
            if(pending_frame_valid && pending_frame_slot != slot)
                complete[pending_frame_slot]=1;
            complete[slot]=0;
            frame_tick[slot]=source_tick;
            pending_frame_valid=1;pending_frame_slot=slot;source_fresh=0;
            if(selected_frame_slot==slot) selected_frame_valid=0;
            @(negedge ddr_clk);write_start=0;
        end
    endtask

    task read_frame;
        input integer slot;
        begin
            @(negedge ddr_clk);
            read_start=1;read_slot=slot;
            selected_frame_slot=slot;
            selected_frame_tick=frame_tick[slot];
            selected_frame_valid=complete[slot];
            @(negedge ddr_clk);read_start=0;
        end
    endtask

    task check_result;
        input reg must_be_valid;
        input integer age;
        input [8*100-1:0] label;
        begin
            repeat(60) @(negedge ddr_clk);
            #0.1;
            if(valid !== must_be_valid)
                $fatal(1,"%0s: valid=%b expected=%b bcd=%h age=%0d",label,valid,must_be_valid,bcd,age);
            if(must_be_valid && bcd !== packed_decimal(age))
                $fatal(1,"%0s: bcd=%h expected=%h age=%0d",label,bcd,packed_decimal(age),age);
            if(!must_be_valid && bcd !== 16'd0)
                $fatal(1,"%0s: invalid result retained stale digits %h",label,bcd);
            checked=checked+1;
            $display("SAMPLE_PASS %0s valid=%0d age=%0d bcd=%h",label,must_be_valid,age,bcd);
        end
    endtask

    // target_age=-1 starts immediately; otherwise schedule the external pixel
    // event so its DDR observation lands at the requested exact tick age.
    task output_frame;
        input integer target_age;
        input [8*100-1:0] label;
        integer predicted_cycle, predicted_tick;
        reg ready;
        begin
            @(negedge pixel_clk);output_de=0;output_vs=1;
            repeat(3) @(negedge pixel_clk);
            output_vs=0;
            repeat(2) @(negedge pixel_clk);
            ready=0;
            while(!ready) begin
                // The next pixel positive edge is seven ns after this edge.
                predicted_cycle=$rtoi((($realtime+7)-first_ddr_pos)/10.0)+1;
                predicted_tick=(predicted_cycle+3)/TICK_CYCLES;
                if(target_age < 0 || predicted_tick == selected_frame_tick+target_age)
                    ready=1;
                else if(predicted_tick > selected_frame_tick+target_age)
                    $fatal(1,"%0s: exact target age already passed",label);
                else @(negedge pixel_clk);
            end
            output_de=1;
            @(posedge pixel_clk);#0.1;
            actual_age=(ddr_cycles+3)/TICK_CYCLES-selected_frame_tick;
            if(target_age>=0 && actual_age != target_age)
                $fatal(1,"Endpoint scheduler mismatch target=%0d actual=%0d",target_age,actual_age);
            expected_age=actual_age;
            expected_valid=selected_frame_valid && actual_age<10000;
            repeat(5) @(negedge pixel_clk);
            output_de=0;
            check_result(expected_valid,expected_age,label);
        end
    endtask

    initial begin
        reset_all;
        read_frame(0);
        output_frame(-1,"startup uninitialized slot");

        camera_frame;write_frame(0);read_frame(0);
        output_frame(-1,"partially written first frame");
        repeat(23) @(negedge ddr_clk);
        camera_frame;write_frame(1);read_frame(0);
        output_frame(-1,"first complete source frame");

        // A later output of the same frame must age; it is not measured from
        // the latest camera event or from the latest read-selection event.
        repeat(40) @(negedge ddr_clk);
        camera_frame;
        read_frame(0);
        @(negedge ddr_clk);read_slot=3;
        output_frame(-1,"repeated frame and unlatched RP changes");

        write_frame(2);
        write_frame(3); // No fresh camera event for this write.
        camera_frame;write_frame(0);
        read_frame(3);
        output_frame(-1,"missing source event cannot complete a frame");

        // Two raw frames before a write use the latest source frame identity.
        camera_frame;
        repeat(41) @(negedge ddr_clk);
        camera_frame;write_frame(1);
        repeat(31) @(negedge ddr_clk);
        camera_frame;write_frame(2);
        read_frame(1);
        output_frame(-1,"dropped camera frame uses newest timestamp");

        for(frame=0;frame<24;frame=frame+1) begin
            repeat((frame*19)%47+1) @(negedge ddr_clk);
            camera_frame;write_frame(frame%4);
            read_frame((frame+2)%4);
            @(negedge ddr_clk);read_slot=(frame+1)%4;
            output_frame(-1,"four-slot rotation with changing clock phases");
        end

        // Write/read selection on the same edge must not select a completed
        // old frame from a slot that is simultaneously being overwritten.
        camera_frame;
        @(negedge ddr_clk);write_start=1;write_slot=2;read_start=1;read_slot=2;
        selected_frame_slot=2;selected_frame_tick=source_tick;selected_frame_valid=0;
        @(negedge ddr_clk);write_start=0;read_start=0;
        output_frame(-1,"same-edge read/write slot conflict");

        reset_all;
        camera_frame;write_frame(0);
        camera_frame;write_frame(1);read_frame(0);
        camera_frame;write_frame(0);
        output_frame(-1,"selected frame overwritten before first output pixel");

        camera_frame;write_frame(0);read_frame(0);
        output_frame(-1,"same-slot replacement remains incomplete");

        reset_all;
        same_edge_camera_and_write(0);
        camera_frame;write_frame(1);read_frame(0);
        output_frame(-1,"raw event write selection and tick on the same edge");

        reset_all;
        camera_frame;write_frame(0);
        camera_frame;write_frame(1);read_frame(0);
        output_frame(9999,"maximum representable 999.9ms");
        output_frame(-1,"1000ms expiry replaces formerly valid result");
        repeat(20000*TICK_CYCLES) @(negedge ddr_clk);
        read_frame(0);
        output_frame(-1,"stopped camera cannot wrap into a fresh result");

        // A raw event that was never paired to ISP output also expires.
        camera_frame;
        repeat(10003*TICK_CYCLES) @(negedge ddr_clk);
        write_frame(2);
        camera_frame;write_frame(3);read_frame(2);
        output_frame(-1,"expired raw event cannot validate a late write");

        reset_all;
        camera_frame;write_frame(0);
        camera_frame;write_frame(1);read_frame(0);
        output_frame(-1,"reset recovery");
        held_bcd=bcd;
        // Active line pulses without a new VS must not trigger extra samples.
        repeat(2) begin
            @(negedge pixel_clk);output_de=1;
            repeat(5) @(negedge pixel_clk);
            output_de=0;
            repeat(80) @(negedge ddr_clk);
        end
        if(valid !== 1 || bcd !== held_bcd)
            $fatal(1,"Additional active lines produced a second frame measurement");
        checked=checked+1;

        // Independent decimal oracle checks carry boundaries and every digit,
        // including values well above the usual two/three-frame video age.
        for(frame=0;frame<10;frame=frame+1) begin
            case(frame)
                0:want_tick=9;
                1:want_tick=10;
                2:want_tick=99;
                3:want_tick=100;
                4:want_tick=999;
                5:want_tick=1000;
                6:want_tick=1234;
                7:want_tick=5678;
                8:want_tick=9998;
                9:want_tick=9999;
            endcase
            reset_all;
            camera_frame;write_frame(0);
            camera_frame;write_frame(1);read_frame(0);
            output_frame(want_tick,"decimal boundary and digit coverage");
        end
        $display("VIDEO_LATENCY_MONITOR_PASS samples=%0d",checked);
        $finish;
    end

    initial begin
        #20000000;
        $fatal(1,"Simulation watchdog expired");
    end
endmodule
