// Confirmed 8-column x 6-row targets, drawn after the algorithm video tap.
// Slot 1..4 is printed INSIDE the upper left; decimal frequency INSIDE the
// upper right. Native 5x7 glyphs use 6x8 cells, with a narrow black pad.
// White top/left grid ticks are retained. The green reference L is removed.
// A shared renderer handles the current cell; no DSP, divider or block RAM.
// Three pixel registers delay DATA/DE/VS together. No feedback to detection.
`ifndef VIB_OSD_MARKER_V
`define VIB_OSD_MARKER_V
module vib_osd_marker (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_data,
    input  wire [31:0] I_obj_pos,   // slot n: byte {0,valid,row[2:0],col[2:0]}
    input  wire [31:0] I_obj_hz10,  // same slot order, frequency * 10
    output reg         O_vs,
    output reg         O_de,
    output reg  [23:0] O_data
);
    reg [10:0] x;
    reg [9:0] y;
    reg de_d, vs_d;
    reg [31:0] frame_pos, frame_hz;
    wire line_end = de_d && !I_de;
    // Both VS edges are in blanking, so this works with either VS polarity.
    wire frame_sync = (I_vs != vs_d) && !I_de;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 0; y <= 0; de_d <= 0; vs_d <= 0;
            frame_pos <= 0; frame_hz <= 0;
        end else begin
            de_d <= I_de; vs_d <= I_vs;
            if (I_de) x <= (x == 11'd1279) ? 11'd0 : x + 11'd1;
            else x <= 0;
            if (line_end) y <= (y == 10'd719) ? 10'd0 : y + 10'd1;
            // Snapshot all positions and frequencies in blanking, never
            // part-way through an active frame. Wrap is a fallback if VS
            // is absent in a simulation / diagnostic source.
            if (frame_sync || (line_end && y == 10'd719)) begin
                x <= 0; y <= 0;
                frame_pos <= I_obj_pos; frame_hz <= I_obj_hz10;
            end
        end
    end

    // Current cell, using compare/subtract rather than variable division.
    reg [2:0] col, row;
    reg [10:0] x0;
    reg [9:0] y0;
    always @(*) begin
        if      (x < 11'd160)  begin col=0; x0=0;    end
        else if (x < 11'd320)  begin col=1; x0=160;  end
        else if (x < 11'd480)  begin col=2; x0=320;  end
        else if (x < 11'd640)  begin col=3; x0=480;  end
        else if (x < 11'd800)  begin col=4; x0=640;  end
        else if (x < 11'd960)  begin col=5; x0=800;  end
        else if (x < 11'd1120) begin col=6; x0=960;  end
        else                  begin col=7; x0=1120; end
        if      (y < 10'd120) begin row=0; y0=0;   end
        else if (y < 10'd240) begin row=1; y0=120; end
        else if (y < 10'd360) begin row=2; y0=240; end
        else if (y < 10'd480) begin row=3; y0=360; end
        else if (y < 10'd600) begin row=4; y0=480; end
        else                 begin row=5; y0=600; end
    end
    wire [10:0] dx = x-x0;
    wire [9:0] dy = y-y0;
    wire [5:0] cell_id = {row,col};
    wire hit0 = frame_pos[6]  && frame_pos[5:0]   == cell_id;
    wire hit1 = frame_pos[14] && frame_pos[13:8]  == cell_id;
    wire hit2 = frame_pos[22] && frame_pos[21:16] == cell_id;
    wire hit3 = frame_pos[30] && frame_pos[29:24] == cell_id;
    reg [2:0] slot;
    reg [7:0] hz;
    reg [23:0] color;
    always @(*) begin
        slot=0; hz=0; color=0;
        if      (hit0) begin slot=1; hz=frame_hz[7:0];   color=24'hFF00FF; end
        else if (hit1) begin slot=2; hz=frame_hz[15:8];  color=24'h00FFFF; end
        else if (hit2) begin slot=3; hz=frame_hz[23:16]; color=24'hFFFF00; end
        else if (hit3) begin slot=4; hz=frame_hz[31:24]; color=24'hFF8000; end
    end
    wire tick_top = y < 10'd32 && col != 0 && dx < 11'd2;
    wire tick_left = x < 11'd32 && row != 0 && dy < 10'd2;

    // Stage A: cell/slot selection. Every image pixel has identical latency.
    reg a_vs, a_de, a_tick;
    reg [23:0] a_data, a_color;
    reg [7:0] a_x, a_hz;
    reg [6:0] a_y;
    reg [2:0] a_slot;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_vs<=0; a_de<=0; a_tick<=0; a_data<=0; a_color<=0;
            a_x<=0; a_y<=0; a_slot<=0; a_hz<=0;
        end else begin
            a_vs<=I_vs; a_de<=I_de; a_data<=I_data;
            a_tick<=tick_top || tick_left; a_color<=color;
            a_x<=dx[7:0]; a_y<=dy[6:0]; a_slot<=slot; a_hz<=hz;
        end
    end

    // BCD glyph codes: 0..9 digits, 10 '.', 11 H, 12 z, 15 space.
    // Explicit 17-point mapping avoids /10, %10 and extra DSPs.
    function [11:0] hz_digits;
        input [7:0] value;
        begin
            case (value)
            20:hz_digits=12'hF20; 25:hz_digits=12'hF25;
            30:hz_digits=12'hF30; 35:hz_digits=12'hF35;
            40:hz_digits=12'hF40; 45:hz_digits=12'hF45;
            50:hz_digits=12'hF50; 55:hz_digits=12'hF55;
            60:hz_digits=12'hF60; 65:hz_digits=12'hF65;
            70:hz_digits=12'hF70; 75:hz_digits=12'hF75;
            80:hz_digits=12'hF80; 85:hz_digits=12'hF85;
            90:hz_digits=12'hF90; 95:hz_digits=12'hF95;
            100:hz_digits=12'h100;
            default:hz_digits=12'hFFF;
            endcase
        end
    endfunction
    wire [11:0] digits = hz_digits(a_hz);
    wire freq_valid = digits != 12'hFFF;
    wire id_panel = a_slot != 0 && a_x >= 8'd6 && a_x < 8'd15 &&
                    a_y >= 7'd6 && a_y < 7'd17;
    wire hz_panel = a_slot != 0 && freq_valid &&
                    a_x >= 8'd114 && a_x < 8'd154 &&
                    a_y >= 7'd6 && a_y < 7'd17;
    // Text at cell x=8 (ID) or x=116 (6 cells * 6 pixels for frequency),
    // cell y=8. Rightmost text ends at x=150; black pad ends at x=153.
    reg [7:0] gx;
    reg [3:0] code;
    always @(*) begin
        gx=0; code=15;
        if (id_panel) begin
            gx=a_x-8'd8; code={1'b0,a_slot};
        end else if (hz_panel) begin
            if      (a_x < 8'd122) begin gx=a_x-8'd116; code=digits[11:8]; end
            else if (a_x < 8'd128) begin gx=a_x-8'd122; code=digits[7:4];  end
            else if (a_x < 8'd134) begin gx=a_x-8'd128; code=10;           end
            else if (a_x < 8'd140) begin gx=a_x-8'd134; code=digits[3:0];  end
            else if (a_x < 8'd146) begin gx=a_x-8'd140; code=11;           end
            else                  begin gx=a_x-8'd146; code=12;           end
        end
    end
    wire [6:0] gy = a_y-7'd8;

    // Stage B: short geometry and glyph address calculation.
    reg b_vs, b_de, b_tick, b_border, b_panel, b_ink_area;
    reg [23:0] b_data, b_color;
    reg [3:0] b_code;
    reg [2:0] b_gx, b_gy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_vs<=0; b_de<=0; b_tick<=0; b_border<=0; b_panel<=0;
            b_ink_area<=0; b_data<=0; b_color<=0;
            b_code<=15; b_gx<=0; b_gy<=0;
        end else begin
            b_vs<=a_vs; b_de<=a_de; b_data<=a_data;
            b_tick<=a_tick; b_color<=a_color;
            b_border<=a_slot != 0 &&
                (a_x < 8'd2 || a_x >= 8'd158 || a_y < 7'd2 || a_y >= 7'd118);
            b_panel<=id_panel || hz_panel;
            b_ink_area<=(id_panel || hz_panel) && gx < 8'd5 && gy < 7'd7;
            b_code<=code; b_gx<=gx[2:0]; b_gy<=gy[2:0];
        end
    end

    function [4:0] glyph_row;
        input [3:0] ch;
        input [2:0] ry;
        reg [34:0] bits;
        begin
            case (ch)
            0: bits={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
            1: bits={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
            2: bits={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
            3: bits={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
            4: bits={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
            5: bits={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
            6: bits={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
            7: bits={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
            8: bits={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
            9: bits={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
            10:bits={5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b00110,5'b00110};
            11:bits={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
            12:bits={5'b00000,5'b00000,5'b11111,5'b00010,5'b00100,5'b01000,5'b11111};
            default:bits=35'd0;
            endcase
            case (ry)
            0:glyph_row=bits[34:30]; 1:glyph_row=bits[29:25];
            2:glyph_row=bits[24:20]; 3:glyph_row=bits[19:15];
            4:glyph_row=bits[14:10]; 5:glyph_row=bits[9:5];
            6:glyph_row=bits[4:0]; default:glyph_row=0;
            endcase
        end
    endfunction
    wire [4:0] glyph = glyph_row(b_code,b_gy);
    wire ink = b_ink_area && glyph[3'd4-b_gx];
    // Stage C: video and all control signals leave in the same register.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin O_vs<=0; O_de<=0; O_data<=0; end
        else begin
            O_vs<=b_vs; O_de<=b_de; O_data<=b_data;
            if (b_de) begin
                if (b_border || ink) O_data<=b_color;
                else if (b_panel) O_data<=24'h000000;
                else if (b_tick) O_data<=24'hFFFFFF;
            end
        end
    end
endmodule
`endif
