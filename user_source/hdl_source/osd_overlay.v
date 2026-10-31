// Production OSD: actual algorithm name and original Anlogic Logo.
// Experimental labels removed; pixel overlay remains combinational.
module osd_overlay #(
    parameter integer OSD_EN      = 1,      // 0 = 完全旁路（不消耗 BRAM）
    parameter integer LOGO_EN     = 1,      // 0 = 只保留算法文字，释放Logo ROM资源

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
                                            I_data;
        end
        else begin : g_osd_off
            assign O_data = I_data;
        end
    endgenerate

endmodule
