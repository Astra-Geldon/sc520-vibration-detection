// Four tracked vibration envelopes, drawn after the algorithm video tap.
// Each envelope uses its slot colour and contains its own 5x7 ID/frequency.
// Fixed 6x8 target outlines are retained behind a disabled compile parameter;
// white top/left grid ticks remain visible. No feedback to detection.
// Three pixel registers delay DATA/DE/VS together, including all labels.
`ifndef VIB_OSD_MARKER_V
`define VIB_OSD_MARKER_V
module vib_osd_marker #(
    parameter integer DRAW_GRID_TARGET_BOXES = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_data,
    input  wire [31:0] I_obj_pos,   // optional old grid outlines, slot1 low
    input  wire [31:0] I_obj_hz10,  // envelope frequencies, slot1 low
    input  wire [43:0] I_bbox_x0,   // four 11-bit coordinates, slot1 low
    input  wire [39:0] I_bbox_y0,   // four 10-bit coordinates, slot1 low
    input  wire [43:0] I_bbox_x1,
    input  wire [39:0] I_bbox_y1,
    input  wire [3:0]  I_bbox_vld,
    output reg         O_vs,
    output reg         O_de,
    output reg  [23:0] O_data
);
    reg [10:0] x;
    reg [9:0] y;
    reg de_d, vs_d;
    reg [31:0] frame_pos, frame_hz;
    reg [43:0] frame_bbox_x0, frame_bbox_x1;
    reg [39:0] frame_bbox_y0, frame_bbox_y1;
    reg [3:0] frame_bbox_vld;
    wire line_end = de_d && !I_de;
    wire frame_sync = (I_vs != vs_d) && !I_de;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x<=0; y<=0; de_d<=0; vs_d<=0;
            frame_pos<=0; frame_hz<=0;
            frame_bbox_x0<=0; frame_bbox_x1<=0;
            frame_bbox_y0<=0; frame_bbox_y1<=0; frame_bbox_vld<=0;
        end else begin
            de_d<=I_de; vs_d<=I_vs;
            if (I_de) x <= (x==11'd1279) ? 11'd0 : x+11'd1;
            else x<=0;
            if (line_end) y <= (y==10'd719) ? 10'd0 : y+10'd1;
            // Atomic blanking snapshot: geometry, frequency and validity
            // must not change part-way through an active video frame.
            if (frame_sync || (line_end && y==10'd719)) begin
                x<=0; y<=0; frame_pos<=I_obj_pos; frame_hz<=I_obj_hz10;
                frame_bbox_x0<=I_bbox_x0; frame_bbox_x1<=I_bbox_x1;
                frame_bbox_y0<=I_bbox_y0; frame_bbox_y1<=I_bbox_y1;
                frame_bbox_vld<=I_bbox_vld;
            end
        end
    end

    function [23:0] slot_colour;
        input [1:0] s;
        begin
            case (s)
            0:slot_colour=24'hFF00FF;
            1:slot_colour=24'h00FFFF;
            2:slot_colour=24'hFFFF00;
            default:slot_colour=24'hFF8000;
            endcase
        end
    endfunction

    // Grid coordinates serve the retained white ticks and optional old
    // outlines only. Envelope text uses its own variable-size coordinates.
    reg [2:0] col,row;
    reg [10:0] x0;
    reg [9:0] y0;
    always @(*) begin
        if      (x<11'd160)  begin col=0; x0=0;    end
        else if (x<11'd320)  begin col=1; x0=160;  end
        else if (x<11'd480)  begin col=2; x0=320;  end
        else if (x<11'd640)  begin col=3; x0=480;  end
        else if (x<11'd800)  begin col=4; x0=640;  end
        else if (x<11'd960)  begin col=5; x0=800;  end
        else if (x<11'd1120) begin col=6; x0=960;  end
        else                begin col=7; x0=1120; end
        if      (y<10'd120) begin row=0; y0=0;   end
        else if (y<10'd240) begin row=1; y0=120; end
        else if (y<10'd360) begin row=2; y0=240; end
        else if (y<10'd480) begin row=3; y0=360; end
        else if (y<10'd600) begin row=4; y0=480; end
        else               begin row=5; y0=600; end
    end
    wire [10:0] dx=x-x0;
    wire [9:0] dy=y-y0;
    wire [5:0] cell_id={row,col};
    wire tick_top=(y<10'd32) && (col!=0) && (dx<11'd2);
    wire tick_left=(x<11'd32) && (row!=0) && (dy<10'd2);
    wire grid_edge=(dx<11'd2)||(dx>=11'd158)||(dy<10'd2)||(dy>=10'd118);
    wire [3:0] grid_hit={
        frame_pos[30]&&(frame_pos[29:24]==cell_id),
        frame_pos[22]&&(frame_pos[21:16]==cell_id),
        frame_pos[14]&&(frame_pos[13:8]==cell_id),
        frame_pos[6]&&(frame_pos[5:0]==cell_id)};
    wire grid_border=(DRAW_GRID_TARGET_BOXES!=0) && (|grid_hit) && grid_edge;
    reg [1:0] grid_slot;
    always @(*) begin
        if      (grid_hit[0]) grid_slot=0;
        else if (grid_hit[1]) grid_slot=1;
        else if (grid_hit[2]) grid_slot=2;
        else                 grid_slot=3;
    end

    wire [3:0] box_border, id_panel, hz_panel;
    wire [23:0] label_x;
    wire [15:0] label_y;
    genvar s;
    generate for (s=0;s<4;s=s+1) begin:g_envelope
        wire [10:0] bx0=frame_bbox_x0[s*11+:11];
        wire [10:0] bx1=frame_bbox_x1[s*11+:11];
        wire [9:0] by0=frame_bbox_y0[s*10+:10];
        wire [9:0] by1=frame_bbox_y1[s*10+:10];
        wire [7:0] hz=frame_hz[s*8+:8];
        wire [10:0] left=x-bx0, right=bx1-x, width=bx1-bx0;
        wire [9:0] top=y-by0, bottom=by1-y, height=by1-by0;
        wire box_inside=frame_bbox_vld[s] && (x>=bx0)&&(x<=bx1)&&(y>=by0)&&(y<=by1);
        wire two_digits=(hz>=8'd100);
        wire hz_valid=(hz>=8'd20)&&(hz<=8'd150);
        // Label pads are one pixel around the native glyphs, three pixels
        // inside the outline. Hide text that cannot fit; never grow a box.
        wire id_fits=(width>=11'd12)&&(height>=10'd14);
        wire hz_fits=(width>=(two_digits?11'd51:11'd45))&&(height>=10'd14);
        assign box_border[s]=box_inside &&
            ((left<11'd2)||(right<11'd2)||(top<10'd2)||(bottom<10'd2));
        assign id_panel[s]=box_inside && id_fits &&
            (left>=11'd3)&&(left<=11'd9)&&(top>=10'd3)&&(top<=10'd11);
        // The right edge is anchored to bx1. Minimum width leaves at least
        // two untouched pixels between the ID and frequency panels.
        assign hz_panel[s]=box_inside && hz_fits && hz_valid &&
            (right>=11'd3)&&(right<=(two_digits?11'd39:11'd33)) &&
            (top>=10'd3)&&(top<=10'd11);
        wire [10:0] gx=id_panel[s] ? left-11'd4 :
            (two_digits?11'd38:11'd32)-right;
        wire [9:0] gy=top-10'd4;
        assign label_x[s*6+:6]=gx[5:0];
        assign label_y[s*4+:4]=gy[3:0];
    end endgenerate

    // A single owner supplies BOTH label and colour at every covered pixel.
    // Overlap priority is slot1, then slot2, slot3, slot4; a high-priority
    // interior without ink/pad does not hide a lower-priority outline.
    wire [3:0] overlay_hit=box_border|id_panel|hz_panel;
    reg [1:0] overlay_slot;
    always @(*) begin
        if      (overlay_hit[0]) overlay_slot=0;
        else if (overlay_hit[1]) overlay_slot=1;
        else if (overlay_hit[2]) overlay_slot=2;
        else                     overlay_slot=3;
    end
    wire overlay_present=|overlay_hit;

    // Stage A: snapshot the selected overlay owner and local glyph position.
    reg a_vs,a_de,a_tick,a_border,a_panel,a_id;
    reg [23:0] a_data,a_colour;
    reg [7:0] a_hz;
    reg [2:0] a_slot;
    reg [5:0] a_x;
    reg [3:0] a_y;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_vs<=0; a_de<=0; a_tick<=0; a_border<=0; a_panel<=0; a_id<=0;
            a_data<=0; a_colour<=0; a_hz<=0; a_slot<=0; a_x<=0; a_y<=0;
        end else begin
            a_vs<=I_vs; a_de<=I_de; a_data<=I_data; a_tick<=tick_top||tick_left;
            a_border<=overlay_present?box_border[overlay_slot]:grid_border;
            a_panel<=overlay_present&&(id_panel[overlay_slot]||hz_panel[overlay_slot]);
            a_id<=id_panel[overlay_slot];
            a_colour<=slot_colour(overlay_present?overlay_slot:grid_slot);
            a_hz<=frame_hz[overlay_slot*8+:8];
            a_slot<={1'b0,overlay_slot}+3'd1;
            a_x<=label_x[overlay_slot*6+:6];
            a_y<=label_y[overlay_slot*4+:4];
        end
    end

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
            100:hz_digits=12'h100; 105:hz_digits=12'h105;
            110:hz_digits=12'h110; 115:hz_digits=12'h115;
            120:hz_digits=12'h120;
            125:hz_digits=12'h125; 130:hz_digits=12'h130;
            135:hz_digits=12'h135; 140:hz_digits=12'h140;
            145:hz_digits=12'h145; 150:hz_digits=12'h150;
            default:hz_digits=12'hFFF;
            endcase
        end
    endfunction
    wire [11:0] digits=hz_digits(a_hz);
    reg [5:0] gx;
    reg [3:0] code;
    always @(*) begin
        gx=a_x; code=15;
        if (a_id) code={1'b0,a_slot};
        else if (digits[11:8]!=4'hF) begin
            if      (a_x<6'd6)  begin gx=a_x;       code=digits[11:8]; end
            else if (a_x<6'd12) begin gx=a_x-6'd6;  code=digits[7:4];  end
            else if (a_x<6'd18) begin gx=a_x-6'd12; code=10;           end
            else if (a_x<6'd24) begin gx=a_x-6'd18; code=digits[3:0];  end
            else if (a_x<6'd30) begin gx=a_x-6'd24; code=11;           end
            else               begin gx=a_x-6'd30; code=12;           end
        end else begin
            if      (a_x<6'd6)  begin gx=a_x;       code=digits[7:4]; end
            else if (a_x<6'd12) begin gx=a_x-6'd6;  code=10;          end
            else if (a_x<6'd18) begin gx=a_x-6'd12; code=digits[3:0]; end
            else if (a_x<6'd24) begin gx=a_x-6'd18; code=11;          end
            else               begin gx=a_x-6'd24; code=12;          end
        end
    end

    // Stage B: glyph decoding shares one renderer across all four slots.
    reg b_vs,b_de,b_tick,b_border,b_panel,b_ink_area;
    reg [23:0] b_data,b_colour;
    reg [3:0] b_code;
    reg [2:0] b_gx,b_gy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_vs<=0; b_de<=0; b_tick<=0; b_border<=0; b_panel<=0; b_ink_area<=0;
            b_data<=0; b_colour<=0; b_code<=15; b_gx<=0; b_gy<=0;
        end else begin
            b_vs<=a_vs; b_de<=a_de; b_data<=a_data; b_tick<=a_tick;
            b_border<=a_border; b_panel<=a_panel; b_colour<=a_colour;
            b_ink_area<=a_panel&&(gx<6'd5)&&(a_y<4'd7);
            b_code<=code; b_gx<=gx[2:0]; b_gy<=a_y[2:0];
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
    wire [4:0] glyph=glyph_row(b_code,b_gy);
    wire ink=b_ink_area && glyph[3'd4-b_gx];
    // Stage C: all video/control signals retain the original three registers.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin O_vs<=0; O_de<=0; O_data<=0; end
        else begin
            O_vs<=b_vs; O_de<=b_de; O_data<=b_data;
            if (b_de) begin
                if (b_border||ink) O_data<=b_colour;
                else if (b_panel) O_data<=24'h000000;
                else if (b_tick) O_data<=24'hFFFFFF;
            end
        end
    end
endmodule
`endif
