// Production OSD: actual mode, original Anlogic Logo, and applied enhancement
// states. Compact panels use native 5x7 glyphs with an 8-pixel character pitch.
// Character/row lookahead prepares text before its first pixel; video remains
// combinational, with no added pixel delay or change to name/Logo priority.
module osd_overlay #(
    parameter integer OSD_EN      = 1,      // 0 = 完全旁路（不消耗 BRAM）
    parameter integer LOGO_EN     = 1,      // 0 = 只保留算法文字，释放Logo ROM资源
    parameter integer STATUS_EN   = 1,
    parameter integer LATENCY_EN  = 1,

    // ---- 画面尺寸（与 VTC 一致）----
    parameter integer H_ACTIVE    = 1280,
    parameter integer V_ACTIVE    = 720,

    // ---- Logo 窗口（右上角）----
    parameter integer LOGO_W      = 128,
    parameter integer LOGO_H      = 80,
    parameter integer LOGO_X      = 1136,   // 1280-128-16
    parameter integer LOGO_Y      = 16,

    // ---- 文字窗口 1（左上角）：算法名 ----
    parameter integer TEXT_X      = 24,     // 第一个字的左上角
    parameter integer TEXT_Y      = 24,
    parameter integer BOX_PAD     = 8       // 黑底外扩
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_de,        // 像素有效
    input  wire        I_vs,        // 场同步（用来清行计数）
    input  wire [ 2:0] I_mode,      // 当前算法（来自 img_mode_sel，3 bit）
    // 生效状态，bit0..5依次为AWB、Gamma、CSC、SW5补亮允许、AE和去马赛克。
    // SW2只控制Gamma，SW5允许但尚未实际补亮时显示ARM。
    input  wire [ 5:0] I_alg_state,
    input  wire [ 5:0] I_alg_pending,
    input  wire        I_n1_active,
    input  wire        I_latency_valid,
    input  wire [15:0] I_latency_bcd, // Four BCD digits, xxx.x milliseconds.
    input  wire [23:0] I_data,      // 来自 img_proc
    output wire [23:0] O_data       // 送 hdmi_mixer
);

    //------------------------------------------------------------------
    //  配色
    //------------------------------------------------------------------
    localparam [23:0] C_NAVY  = 24'h1B3A66;     // 安路深蓝
    localparam [23:0] C_RED   = 24'hE8382F;     // 安路红
    localparam [23:0] C_BLACK = 24'h00_00_00;   // 文字底色
    localparam [23:0] C_WHITE = 24'hFF_FF_FF;   // 文字

    //------------------------------------------------------------------
    //  像素坐标计数：x 在 de 期间累加，y 在 de 下降沿（行尾）累加
    //------------------------------------------------------------------
    reg [10:0] S_x;
    reg [ 9:0] S_y;
    reg        S_de_d;

    wire S_line_end = S_de_d & ~I_de;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_x    <= 11'd0;
            S_y    <= 10'd0;
            S_de_d <= 1'b0;
        end
        else begin
            S_de_d <= I_de;

            if (I_de)              S_x <= S_x + 1'b1;
            else                   S_x <= 11'd0;

            if (I_vs)              S_y <= 10'd0;
            else if (S_line_end)   S_y <= S_y + 1'b1;
        end
    end

    // The timing result arrives independently of the raster.  Show one stable
    // snapshot for the whole frame, even if the next result arrives mid-frame.
    reg S_vs_d;
    reg S_latency_valid;
    reg [15:0] S_latency_bcd;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_vs_d <= 1'b0;
            S_latency_valid <= 1'b0;
            S_latency_bcd <= 16'd0;
        end else begin
            S_vs_d <= I_vs;
            if (I_vs && !S_vs_d) begin
                S_latency_valid <= I_latency_valid;
                S_latency_bcd <= I_latency_bcd;
            end
        end
    end

    //------------------------------------------------------------------
    //  算法 -> 字模表（★ 新增算法在这里加一行）
    //------------------------------------------------------------------
    // 窗口1（左上）：算法名，跟随 KEY1/KEY2 的 I_mode
    reg [3:0] S_base1;
    reg [2:0] S_nchars1;
    always @(*) begin
        case (I_mode)
            3'd0:    begin S_base1 = 4'd0; S_nchars1 = 3'd2; end   // 原图（增强彩色）
            3'd1:    begin S_base1 = 4'd2; S_nchars1 = 3'd2; end   // 灰度
            3'd2:    begin S_base1 = 4'd4; S_nchars1 = 3'd3; end   // 二值化
            3'd3:    begin S_base1 = 4'd7; S_nchars1 = 3'd2; end   // 边缘
            default: begin S_base1 = 4'd0; S_nchars1 = 3'd2; end
        endcase
    end

    //------------------------------------------------------------------
    //  Logo 窗口：组合ROM使用当前像素坐标
    //------------------------------------------------------------------

    wire [9:0]  S_lx = S_x[9:0] - LOGO_X[9:0];
    wire [9:0]  S_ly = S_y      - LOGO_Y[9:0];

    // 当前坐标窗口判定；Logo ROM为组合输出，不新增像素延迟。
    wire S_in_logo = (S_x >= LOGO_X) && (S_x < LOGO_X + LOGO_W) &&
                     (S_y >= LOGO_Y) && (S_y < LOGO_Y + LOGO_H);


    // Logo 点阵 ROM：LUT 实现（640 条 case），无厂商原语依赖
    wire [1:0] S_logo_q;
    generate
        if (LOGO_EN != 0) begin : g_logo_on
            wire [31:0] S_logo_word;
            osd_logo_rom u_logo_rom (
                .I_addr ( {S_ly[6:0], S_lx[6:4]} ),
                .O_word ( S_logo_word )
            );
            // 32 bit word里装16个像素，取当前x对应像素。
            wire [4:0] S_px_shift = 5'd30 - {S_lx[3:0], 1'b0};
            assign S_logo_q = (S_logo_word >> S_px_shift) & 2'b11;
        end
        else begin : g_logo_off
            assign S_logo_q = 2'd0;
        end
    endgenerate

    //------------------------------------------------------------------
    //  文字窗口（左上角黑底 + 白字）
    //------------------------------------------------------------------
    //---------------- 窗口1（左上）----------------
    wire [6:0] S_text_px1 = {S_nchars1, 4'h0};

    wire S_in_box1  = (S_x >= TEXT_X - BOX_PAD) &&
                      (S_x <  TEXT_X + S_text_px1 + BOX_PAD) &&
                      (S_y >= TEXT_Y - BOX_PAD) &&
                      (S_y <  TEXT_Y + 16 + BOX_PAD);

    wire S_in_text1 = (S_x >= TEXT_X) && (S_x < TEXT_X + S_text_px1) &&
                      (S_y >= TEXT_Y) && (S_y < TEXT_Y + 16);

    wire [3:0] S_char_i1 = (S_x - TEXT_X) >> 4;
    wire [3:0] S_col1    = (S_x - TEXT_X) & 4'hF;
    wire [3:0] S_row1    = (S_y - TEXT_Y);
    // Only the name glyphs, with no exposure/candidate-number suffix.
    wire [3:0] S_glyph1 = S_base1 + S_char_i1;

    wire [15:0] S_font_row1;
    osd_font_rom u_font1 (
        .I_addr ( {S_glyph1, S_row1} ),
        .O_row  ( S_font_row1        )
    );

    wire [3:0] S_bit_idx1  = 4'd15 - S_col1;
    wire       S_text_bit1 = S_font_row1[S_bit_idx1];

    //------------------------------------------------------------------
    // Lower-left applied-state panel. 3 columns x 2 rows, 96x16 per item.
    // 标签对应实体键，例如S2 GAM、S5 N1及K4 AE。
    // WAIT优先，其后补亮项区分允许待命ARM和实际补亮ON。
    // Coordinates and font selection are shared across all six entries.
    //------------------------------------------------------------------
    localparam integer STATUS_X = 24;
    localparam integer STATUS_Y = V_ACTIVE - 32;
    localparam [23:0] C_ON   = 24'h50_FF_80;
    localparam [23:0] C_OFF  = 24'hA0_A0_A0;
    localparam [23:0] C_WAIT = 24'hFF_D0_40;

    // Both compact panels start on an 8-pixel boundary. Decode a character
    // two pixels early, then register its five-bit row one pixel early.
    wire [10:0] S_small_fetch_x = S_x + 11'd2;
    wire [10:0] S_status_dx = S_small_fetch_x - STATUS_X;
    wire [ 9:0] S_status_dy = S_y - STATUS_Y;
    wire S_in_status_box = (S_x >= STATUS_X - 4) && (S_x < STATUS_X + 292) &&
                           (S_y >= STATUS_Y - 4) && (S_y < STATUS_Y + 28);
    wire S_status_text_line = (S_y >= STATUS_Y) && (S_y < STATUS_Y + 24) &&
                              !S_status_dy[3];
    wire S_in_status_text = (S_x >= STATUS_X) && (S_x < STATUS_X + 288) &&
                            S_status_text_line;
    wire S_fetch_status = (STATUS_EN != 0) &&
                          (S_small_fetch_x >= STATUS_X) &&
                          (S_small_fetch_x < STATUS_X + 288) && S_status_text_line;
    reg [1:0] S_status_column;
    reg [6:0] S_status_item_x;
    always @(*) begin
        if (S_status_dx < 11'd96) begin
            S_status_column = 2'd0;
            S_status_item_x = S_status_dx[6:0];
        end else if (S_status_dx < 11'd192) begin
            S_status_column = 2'd1;
            S_status_item_x = S_status_dx - 11'd96;
        end else begin
            S_status_column = 2'd2;
            S_status_item_x = S_status_dx - 11'd192;
        end
    end
    wire [2:0] S_status_item = S_status_dy[4] ?
                               (3'd3 + {1'b0, S_status_column}) :
                               {1'b0, S_status_column};
    wire [3:0] S_status_char = S_status_item_x[6:3];
    wire [2:0] S_status_row = S_status_dy[2:0];
    wire S_status_pending = I_alg_pending[S_status_item];
    wire S_status_enabled = I_alg_state[S_status_item];
    wire S_status_armed = (S_status_item == 3'd3) && S_status_enabled && !I_n1_active;

    function [7:0] status_label;
        input [2:0] item;
        input [1:0] letter;
        begin
            status_label = " ";
            case (item)
                3'd0: case (letter) 0:status_label="A";1:status_label="W";2:status_label="B";endcase
                3'd1: case (letter) 0:status_label="G";1:status_label="A";2:status_label="M";endcase
                3'd2: case (letter) 0:status_label="C";1:status_label="S";2:status_label="C";endcase
                3'd3: case (letter) 0:status_label="N";1:status_label="1";endcase
                3'd4: case (letter) 0:status_label="A";1:status_label="E";endcase
                3'd5: case (letter) 0:status_label="D";1:status_label="E";2:status_label="M";endcase
                default: status_label=" ";
            endcase
        end
    endfunction

    reg [7:0] S_status_ascii;
    always @(*) begin
        S_status_ascii = " ";
        case (S_status_char)
            4'd0: S_status_ascii = (S_status_item == 3'd4) ? "K" : "S";
            4'd1: case (S_status_item)
                3'd0:S_status_ascii="1";
                3'd1:S_status_ascii="2";
                3'd3:S_status_ascii="5";
                3'd2:S_status_ascii="3";
                3'd4:S_status_ascii="4";
                3'd5:S_status_ascii="4";
                default:S_status_ascii=" ";
            endcase
            4'd3:S_status_ascii=status_label(S_status_item,2'd0);
            4'd4:S_status_ascii=status_label(S_status_item,2'd1);
            4'd5:S_status_ascii=status_label(S_status_item,2'd2);
            4'd7:S_status_ascii=S_status_pending ? "W" : (S_status_armed ? "A" : "O");
            4'd8:S_status_ascii=S_status_pending ? "A" : (S_status_armed ? "R" : (S_status_enabled ? "N" : "F"));
            4'd9:S_status_ascii=S_status_pending ? "I" : (S_status_armed ? "M" : (S_status_enabled ? " " : "F"));
            4'd10:S_status_ascii=S_status_pending ? "T" : " ";
            default:S_status_ascii=" ";
        endcase
    end

    // Upper-left timing panel, beside every mode name, vertically centered
    // against the original 16-pixel mode label. The compact box is 104x16.
    localparam integer LATENCY_X = 96;
    localparam integer LATENCY_Y = TEXT_Y + 4;
    localparam integer LATENCY_CHARS = 12; // "LAT 033.2 MS", or "LAT ---.- MS".
    wire [10:0] S_latency_dx = S_small_fetch_x - LATENCY_X;
    wire [9:0] S_latency_dy = S_y - LATENCY_Y;
    wire S_in_latency_box = (LATENCY_EN != 0) &&
                           (S_x >= LATENCY_X - 4) &&
                           (S_x < LATENCY_X + LATENCY_CHARS * 8 + 4) &&
                           (S_y >= LATENCY_Y - 4) &&
                           (S_y < LATENCY_Y + 8 + 4);
    wire S_in_latency_text = (LATENCY_EN != 0) &&
                            (S_x >= LATENCY_X) &&
                            (S_x < LATENCY_X + LATENCY_CHARS * 8) &&
                            (S_y >= LATENCY_Y) && (S_y < LATENCY_Y + 8);
    wire S_fetch_latency = (LATENCY_EN != 0) &&
                           (S_small_fetch_x >= LATENCY_X) &&
                           (S_small_fetch_x < LATENCY_X + LATENCY_CHARS * 8) &&
                           (S_y >= LATENCY_Y) && (S_y < LATENCY_Y + 8);
    wire [3:0] S_latency_char = S_latency_dx[6:3];
    reg [7:0] S_latency_ascii;
    always @(*) begin
        S_latency_ascii = " ";
        case (S_latency_char)
            4'd0: S_latency_ascii = "L";
            4'd1: S_latency_ascii = "A";
            4'd2: S_latency_ascii = "T";
            4'd4: S_latency_ascii = S_latency_valid ?
                                   (8'h30 + {4'd0,S_latency_bcd[15:12]}) : "-";
            4'd5: S_latency_ascii = S_latency_valid ?
                                   (8'h30 + {4'd0,S_latency_bcd[11:8]}) : "-";
            4'd6: S_latency_ascii = S_latency_valid ?
                                   (8'h30 + {4'd0,S_latency_bcd[7:4]}) : "-";
            4'd7: S_latency_ascii = ".";
            4'd8: S_latency_ascii = S_latency_valid ?
                                   (8'h30 + {4'd0,S_latency_bcd[3:0]}) : "-";
            4'd10: S_latency_ascii = "M";
            4'd11: S_latency_ascii = "S";
            default: S_latency_ascii = " ";
        endcase
    end

    function [34:0] status_glyph;
        input [7:0] ascii;
        begin
            case (ascii)
                "K":status_glyph=35'b10001_10010_10100_11000_10100_10010_10001;
                "A":status_glyph=35'b01110_10001_10001_11111_10001_10001_10001;
                "B":status_glyph=35'b11110_10001_10001_11110_10001_10001_11110;
                "C":status_glyph=35'b01111_10000_10000_10000_10000_10000_01111;
                "D":status_glyph=35'b11110_10001_10001_10001_10001_10001_11110;
                "E":status_glyph=35'b11111_10000_10000_11110_10000_10000_11111;
                "F":status_glyph=35'b11111_10000_10000_11110_10000_10000_10000;
                "G":status_glyph=35'b01111_10000_10000_10111_10001_10001_01111;
                "I":status_glyph=35'b11111_00100_00100_00100_00100_00100_11111;
                "L":status_glyph=35'b10000_10000_10000_10000_10000_10000_11111;
                "M":status_glyph=35'b10001_11011_10101_10101_10001_10001_10001;
                "N":status_glyph=35'b10001_11001_10101_10011_10001_10001_10001;
                "O":status_glyph=35'b01110_10001_10001_10001_10001_10001_01110;
                "P":status_glyph=35'b11110_10001_10001_11110_10000_10000_10000;
                "R":status_glyph=35'b11110_10001_10001_11110_10100_10010_10001;
                "S":status_glyph=35'b01111_10000_10000_01110_00001_00001_11110;
                "T":status_glyph=35'b11111_00100_00100_00100_00100_00100_00100;
                "W":status_glyph=35'b10001_10001_10001_10101_10101_11011_10001;
                "X":status_glyph=35'b10001_10001_01010_00100_01010_10001_10001;
                "0":status_glyph=35'b01110_10001_10011_10101_11001_10001_01110;
                "1":status_glyph=35'b00100_01100_00100_00100_00100_00100_01110;
                "2":status_glyph=35'b01110_10001_00001_00010_00100_01000_11111;
                "3":status_glyph=35'b11110_00001_00001_01110_00001_00001_11110;
                "4":status_glyph=35'b00010_00110_01010_10010_11111_00010_00010;
                "5":status_glyph=35'b11111_10000_10000_11110_00001_00001_11110;
                "6":status_glyph=35'b01110_10000_10000_11110_10001_10001_01110;
                "7":status_glyph=35'b11111_00001_00010_00100_01000_01000_01000;
                "8":status_glyph=35'b01110_10001_10001_01110_10001_10001_01110;
                "9":status_glyph=35'b01110_10001_10001_01111_00001_00001_01110;
                ".":status_glyph=35'b00000_00000_00000_00000_00000_00110_00110;
                "-":status_glyph=35'b00000_00000_00000_11111_00000_00000_00000;
                default:status_glyph=35'd0;
            endcase
        end
    endfunction
    // Split character decoding, glyph-row lookup and pixel selection. Only
    // text metadata is registered; the input video never passes these FFs.
    reg [7:0] S_small_ascii;
    reg [2:0] S_small_row;
    reg [1:0] S_small_style;
    wire [34:0] S_small_glyph = status_glyph(S_small_ascii);
    reg [4:0] S_small_row_bits;
    always @(*) begin
        case (S_small_row)
            3'd0: S_small_row_bits = S_small_glyph[34:30];
            3'd1: S_small_row_bits = S_small_glyph[29:25];
            3'd2: S_small_row_bits = S_small_glyph[24:20];
            3'd3: S_small_row_bits = S_small_glyph[19:15];
            3'd4: S_small_row_bits = S_small_glyph[14:10];
            3'd5: S_small_row_bits = S_small_glyph[9:5];
            3'd6: S_small_row_bits = S_small_glyph[4:0];
            default: S_small_row_bits = 5'd0;
        endcase
    end
    reg [4:0] S_small_bits;
    reg [1:0] S_small_color;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_small_ascii <= " ";
            S_small_row <= 0;
            S_small_style <= 0;
            S_small_bits <= 0;
            S_small_color <= 0;
        end else if (I_de) begin
            if ((S_x[2:0] == 3'd6) && (S_fetch_latency || S_fetch_status)) begin
                S_small_ascii <= S_fetch_latency ? S_latency_ascii : S_status_ascii;
                S_small_row <= S_fetch_latency ? S_latency_dy[2:0] : S_status_row;
                S_small_style <= S_fetch_latency ? 2'd0 :
                                 (S_status_pending ? 2'd3 :
                                  (S_status_enabled ? 2'd1 : 2'd2));
            end
            if (S_x[2:0] == 3'd7) begin
                S_small_bits <= S_small_row_bits;
                S_small_color <= S_small_style;
            end
        end
    end
    reg S_small_ink;
    always @(*) begin
        case (S_x[2:0])
            3'd0: S_small_ink = S_small_bits[4];
            3'd1: S_small_ink = S_small_bits[3];
            3'd2: S_small_ink = S_small_bits[2];
            3'd3: S_small_ink = S_small_bits[1];
            3'd4: S_small_ink = S_small_bits[0];
            default: S_small_ink = 1'b0;
        endcase
    end
    wire [23:0] S_status_rgb = (S_small_color == 2'd3) ? C_WAIT :
                               ((S_small_color == 2'd1) ? C_ON : C_OFF);

    //------------------------------------------------------------------
    //  叠加（纯组合 3 选 1）
    //     Logo 不透明像素 > 文字框（黑底/白字） > 原视频
    //------------------------------------------------------------------
    wire [23:0] S_logo_rgb = (S_logo_q == 2'd1) ? C_NAVY :
                             (S_logo_q == 2'd2) ? C_RED  : 24'h00_00_00;

    wire S_logo_opaque = (LOGO_EN != 0) && S_in_logo && (S_logo_q != 2'd0);

    generate
        if (OSD_EN != 0) begin : g_osd_on
            assign O_data = S_logo_opaque ? S_logo_rgb  :
                            S_in_text1    ? (S_text_bit1 ? C_WHITE : C_BLACK) :
                            S_in_box1     ? C_BLACK :
                            S_in_latency_text ? (S_small_ink ? C_WHITE : C_BLACK) :
                            S_in_latency_box ? C_BLACK :
                            ((STATUS_EN != 0) && S_in_status_text) ?
                                (S_small_ink ? S_status_rgb : C_BLACK) :
                            ((STATUS_EN != 0) && S_in_status_box) ? C_BLACK :
                                            I_data;
        end
        else begin : g_osd_off
            assign O_data = I_data;
        end
    endgenerate

endmodule
