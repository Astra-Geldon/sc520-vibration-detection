//=====================================================================
//  osd_overlay.v  ——  视频 OSD 叠加（基础要求 2.3(4)）
//
//  插入位置
//      img_proc ──► [osd_overlay] ──► hdmi_mixer
//      时钟域 S_hdmi_pixel_clk（74.25 MHz），与 VTC / mixer 同域。
//
//  显示内容
//      右上角：ANLOGIC 安路 Logo   128×80，双色（深蓝 A + 红色条纹），白底透明
//      左上角：当前算法名称        16×16 汉字点阵，黑底白字
//                 只显示算法名，不显示原图/增强图标记
//      二值化诊断（TH_DEBUG_EN=1）：算法名下一行 T=128 A/L，A=自适应，L=已锁定
//
//  ★ 关键：仍然保持"数据零延迟"
//      O_data 相对 I_data 是**纯组合**的（一个 3 选 1 mux），
//      因为坐标计数器只用来算出"该不该覆盖"，不参与数据通路。
//      这样 hdmi_mixer 的 2 级数据/DE 对齐照旧成立，de 不用跟着延拍。
//      实现：Logo 用 LUT ROM（640 条 case 的 32 bit 字 + 变量移位取像素），
//      字模用 case ROM，两者都是**组合输出**，因此叠加位置与像素坐标严格对齐。
//
//  ★ 新增算法的接口（详见 docs/算法添加方法.md）
//      1) 在 img_proc.v 里加一个 I_mode 编码分支；
//      2) 在下面 S_base / S_nchars 的 case 里加一行（字形序号 → 起始字模）；
//      3) 在 tools/gen_osd_assets.py 的 CHARS 里按顺序补上汉字，重新生成字模；
//      4) 新增键位见 img_mode_sel.v。
//      字形表是"顺序编号"的，加字只需追加，不会影响已有编码。
//=====================================================================
module osd_overlay #(
    parameter integer OSD_EN      = 1,      // 0 = 完全旁路（不消耗 BRAM）
    parameter integer TH_DEBUG_EN = 0,      // 二值化实际阈值/锁定状态诊断
    parameter integer REGION_DEBUG_EN = 0,  // 彩色画面固定H1及补偿档 H=1 C=0/1/2/3/M
    parameter integer SHOULDER_DEBUG_EN = 0,// C/P/W: eight references + white protection
    parameter integer GAIN_DEBUG_EN = 0,    // isolated exposure900/gain comparison
    parameter integer LIFT_DEBUG_EN = 0,    // append L0..L3 RGB8 lift profile
    parameter integer GAIN12_EN = 0,        // gain index1 label12 instead of16
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
    // ---- 文字窗口 2（左下角）：CSC 强度档 k ----
    parameter integer TEXT2_X     = 24,
    parameter integer TEXT2_Y     = 670,
    parameter integer BOX_PAD     = 8       // 黑底外扩
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_de,        // 像素有效
    input  wire        I_vs,        // 场同步（用来清行计数）
    input  wire [ 2:0] I_mode,      // 当前算法（来自 img_mode_sel，3 bit）
    input  wire        I_src_raw,   // 二值化来源：1=原图，0=视觉增强输入
    input  wire [ 1:0] I_k_sel,     // 兼容保留，KEY4 已释放
    input  wire [ 1:0] I_exp_sel,   // 曝光候选编号：0=1991,1=1600,2=1200,3=900
    input  wire [ 3:0] I_region_sel,// 0..7=C/P references, 8..10=C3/P3/W1..3
    input  wire [ 1:0] I_gain_sel,  // sensor gain request index: 24/16/8/4x
    input  wire        I_gain_verified, // six exposure/gain readbacks matched
    input  wire [ 1:0] I_lift_sel,
    input  wire [ 7:0] I_threshold, // 二值比较器实际使用的阈值
    input  wire        I_th_locked, // 实际已提交的锁定状态
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
    reg [10:0] S_x_d;        // 延迟 1 拍：与 Logo BRAM 的输出对齐
    reg [ 9:0] S_y_d;

    wire S_line_end = S_de_d & ~I_de;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_x    <= 11'd0;
            S_y    <= 10'd0;
            S_de_d <= 1'b0;
            S_x_d  <= 11'd0;
            S_y_d  <= 10'd0;
        end
        else begin
            S_de_d <= I_de;
            S_x_d  <= S_x;
            S_y_d  <= S_y;

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
    reg [2:0] S_name_len1;
    // 窗口2（左下）：CSC 强度档 k 的数字 0~3
    reg [3:0] S_base2;
    reg [1:0] S_nchars2;

    always @(*) begin
        case (I_mode)
            3'd0:    begin S_base1 = 4'd0; S_name_len1 = 3'd2; end   // 原图（增强彩色）
            3'd1:    begin S_base1 = 4'd2; S_name_len1 = 3'd2; end   // 灰度
            3'd2:    begin S_base1 = 4'd4; S_name_len1 = 3'd3; end   // 二值化
            3'd3:    begin S_base1 = 4'd7; S_name_len1 = 3'd2; end   // 边缘
            default: begin S_base1 = 4'd0; S_name_len1 = 3'd2; end
        endcase
        S_nchars1 = S_name_len1 + 3'd1;
        // 字形表 CHARS = "原图灰度二值化边缘0123"，数字 0~3 序号 9~12
        S_base2   = 4'd9 + {2'b0, I_k_sel};
        S_nchars2 = 2'd0;
    end

    //------------------------------------------------------------------
    //  Logo 窗口：地址用**当前**坐标算（BRAM 输出晚 1 拍）
    //------------------------------------------------------------------

    wire [9:0]  S_lx = S_x[9:0] - LOGO_X[9:0];
    wire [9:0]  S_ly = S_y      - LOGO_Y[9:0];
    wire [13:0] S_logo_addr = (S_ly * LOGO_W) + S_lx;   // LOGO_W 是 2 的幂 -> 移位

    // 延迟 1 拍后的窗口判定（与上面算出的地址对应的像素）
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

    // This line uses the sensor request index and its readback status, not
    // another local key counter. It remains combinational like the old OSD.
    wire S_gain_box, S_gain_white;
    generate
        if (GAIN_DEBUG_EN != 0) begin : g_gain_text
            osd_gain_line #(.TEXT_X(TEXT_X), .TEXT_Y(TEXT_Y + 32), .LIFT_DEBUG_EN(LIFT_DEBUG_EN), .GAIN12_EN(GAIN12_EN)) u_line (
                .I_x(S_x), .I_y(S_y), .I_enable(I_de),
                .I_sel(I_gain_sel), .I_verified(I_gain_verified),
                .I_lift_sel(I_lift_sel),
                .O_box(S_gain_box), .O_white(S_gain_white)
            );
        end else begin : g_no_gain_text
            assign S_gain_box = 1'b0;
            assign S_gain_white = 1'b0;
        end
    endgenerate

    // 固定H1及补偿档只覆盖彩色视频；关闭参数后整段裁剪，不改变像素拍数。
    // H=1 C=0/1/2/3/M 与上方真实曝光编号分行显示；M表示查看品红H1掩码。
    wire S_region_box, S_region_white;
    generate
        if (REGION_DEBUG_EN != 0) begin : g_region_text
            osd_region_line #(.TEXT_X(TEXT_X), .TEXT_Y(TEXT_Y + 32),
                              .SHOULDER_MODE(SHOULDER_DEBUG_EN)) u_line (
                .I_x       ( S_x            ),
                .I_y       ( S_y            ),
                .I_enable  ( I_de && (I_mode == 3'd0) ),
                .I_sel     ( I_region_sel   ),
                .O_box     ( S_region_box   ),
                .O_white   ( S_region_white )
            );
        end
        else begin : g_no_region_text
            assign S_region_box = 1'b0;
            assign S_region_white = 1'b0;
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
    // 算法名只显示实际算法，不再追加 0/1 后缀。
    wire [3:0] S_glyph1  = (S_char_i1 < S_name_len1) ?
                            (S_base1 + S_char_i1) :
                            (4'd9 + {2'b0, I_exp_sel});

    wire [15:0] S_font_row1;
    osd_font_rom u_font1 (
        .I_addr ( {S_glyph1, S_row1} ),
        .O_row  ( S_font_row1        )
    );

    wire [3:0] S_bit_idx1  = 4'd15 - S_col1;
    wire       S_text_bit1 = S_font_row1[S_bit_idx1];

    //---------------- 窗口2（左下，CSC 强度档）----------------
    wire [6:0] S_text_px2 = {S_nchars2, 4'h0};

    wire S_in_box2  = 1'b0;
    wire S_in_text2 = 1'b0;

    wire [3:0] S_char_i2 = (S_x - TEXT2_X) >> 4;
    wire [3:0] S_col2    = (S_x - TEXT2_X) & 4'hF;
    wire [3:0] S_row2    = (S_y - TEXT2_Y);
    wire [3:0] S_glyph2  = S_base2 + S_char_i2;

    wire [15:0] S_font_row2;
    osd_font_rom u_font2 (
        .I_addr ( {S_glyph2, S_row2} ),
        .O_row  ( S_font_row2        )
    );

    wire [3:0] S_bit_idx2  = 4'd15 - S_col2;
    wire       S_text_bit2 = S_font_row2[S_bit_idx2];

    // 诊断文字复用当前像素坐标，仍为纯组合叠加；关闭参数后整段裁剪。
    wire S_threshold_box, S_threshold_white;
    generate
        if (TH_DEBUG_EN != 0) begin : g_threshold_text
            osd_threshold_line #(.TEXT_X(TEXT_X), .TEXT_Y(TEXT_Y + 32)) u_line (
                .I_x         ( S_x            ),
                .I_y         ( S_y            ),
                .I_enable    ( I_de && (I_mode == 3'd2) ),
                .I_threshold ( I_threshold    ),
                .I_locked    ( I_th_locked    ),
                .O_box       ( S_threshold_box ),
                .O_white     ( S_threshold_white )
            );
        end
        else begin : g_no_threshold_text
            assign S_threshold_box = 1'b0;
            assign S_threshold_white = 1'b0;
        end
    endgenerate

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
                            S_region_box  ? (S_region_white ? C_WHITE : C_BLACK) :
                            S_gain_box    ? (S_gain_white ? C_WHITE : C_BLACK) :
                            S_threshold_box ? (S_threshold_white ? C_WHITE : C_BLACK) :
                            S_in_text2    ? (S_text_bit2 ? C_WHITE : C_BLACK) :
                            S_in_box2     ? C_BLACK :
                                            I_data;
        end
        else begin : g_osd_off
            assign O_data = I_data;
        end
    endgenerate

endmodule

// Fourteen 6x8 cells at2x scale: "E=900 G=24 V=1". Single-digit gains
// are right aligned. V=1 means exposure/gain readback matched; V=0 is pending
// or error. This fixed-size label needs no framebuffer, DSP or decimal divider.
module osd_gain_line #(
    parameter integer TEXT_X = 24,
    parameter integer TEXT_Y = 56,
    parameter integer LIFT_DEBUG_EN = 0,
    parameter integer GAIN12_EN = 0
)(
    input wire [10:0] I_x,
    input wire [9:0] I_y,
    input wire I_enable,
    input wire [1:0] I_sel,
    input wire I_verified,
    input wire [1:0] I_lift_sel,
    output wire O_box,
    output wire O_white
);
    function [34:0] f_glyph;
        input [3:0] glyph;
        begin
            case (glyph)
                4'd0: f_glyph = {5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                4'd1: f_glyph = {5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                4'd2: f_glyph = {5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                4'd3: f_glyph = {5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                4'd4: f_glyph = {5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                4'd6: f_glyph = {5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                4'd8: f_glyph = {5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                4'd9: f_glyph = {5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                4'd10: f_glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111}; // E
                4'd11: f_glyph = {5'b01110,5'b10001,5'b10000,5'b10111,5'b10001,5'b10001,5'b01110}; // G
                4'd12: f_glyph = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100}; // V
                4'd13: f_glyph = {5'b00000,5'b11111,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000}; // =
                4'd14: f_glyph = {5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111}; // L
                default: f_glyph = 35'd0;
            endcase
        end
    endfunction
    reg [3:0] S_tens, S_ones;
    always @(*) begin
        case (I_sel)
            2'd0: begin S_tens=4'd2; S_ones=4'd4; end
            2'd1: begin S_tens=4'd1; S_ones=(GAIN12_EN != 0) ? 4'd2 : 4'd6; end
            2'd2: begin S_tens=4'd15; S_ones=4'd8; end
            default: begin S_tens=4'd15; S_ones=4'd4; end
        endcase
    end
    wire [10:0] S_local_x = I_x - TEXT_X;
    wire [9:0] S_local_y = I_y - TEXT_Y;
    reg [3:0] S_glyph_id, S_cell_x;
    always @(*) begin
        if      (S_local_x < 11'd12) begin S_glyph_id=4'd10; S_cell_x=S_local_x; end
        else if (S_local_x < 11'd24) begin S_glyph_id=4'd13; S_cell_x=S_local_x-11'd12; end
        else if (S_local_x < 11'd36) begin S_glyph_id=4'd9; S_cell_x=S_local_x-11'd24; end
        else if (S_local_x < 11'd48) begin S_glyph_id=4'd0; S_cell_x=S_local_x-11'd36; end
        else if (S_local_x < 11'd60) begin S_glyph_id=4'd0; S_cell_x=S_local_x-11'd48; end
        else if (S_local_x < 11'd72) begin S_glyph_id=4'd15; S_cell_x=S_local_x-11'd60; end
        else if (S_local_x < 11'd84) begin S_glyph_id=4'd11; S_cell_x=S_local_x-11'd72; end
        else if (S_local_x < 11'd96) begin S_glyph_id=4'd13; S_cell_x=S_local_x-11'd84; end
        else if (S_local_x < 11'd108) begin S_glyph_id=S_tens; S_cell_x=S_local_x-11'd96; end
        else if (S_local_x < 11'd120) begin S_glyph_id=S_ones; S_cell_x=S_local_x-11'd108; end
        else if (S_local_x < 11'd132) begin S_glyph_id=4'd15; S_cell_x=S_local_x-11'd120; end
        else if (S_local_x < 11'd144) begin S_glyph_id=4'd12; S_cell_x=S_local_x-11'd132; end
        else if (S_local_x < 11'd156) begin S_glyph_id=4'd13; S_cell_x=S_local_x-11'd144; end
        else if (S_local_x < 11'd168) begin S_glyph_id=I_verified ? 4'd1 : 4'd0; S_cell_x=S_local_x-11'd156; end
        else if (S_local_x < 11'd180) begin S_glyph_id=4'd15; S_cell_x=S_local_x-11'd168; end
        else if (S_local_x < 11'd192) begin S_glyph_id=4'd14; S_cell_x=S_local_x-11'd180; end
        else if (S_local_x < 11'd204) begin S_glyph_id=4'd13; S_cell_x=S_local_x-11'd192; end
        else begin S_glyph_id={2'd0,I_lift_sel}; S_cell_x=S_local_x-11'd204; end
    end
    wire [2:0] S_col = S_cell_x[3:1];
    wire [2:0] S_row = S_local_y[3:1];
    wire [34:0] S_bitmap = f_glyph(S_glyph_id);
    wire [5:0] S_row_offset = {1'b0,S_row,2'b00} + {3'b000,S_row};
    wire [5:0] S_bit_index = 6'd34 - S_row_offset - {3'd0,S_col};
    localparam integer TEXT_WIDTH = (LIFT_DEBUG_EN != 0) ? 216 : 168;
    wire S_in_text = (I_x >= TEXT_X) && (I_x < TEXT_X+TEXT_WIDTH) &&
                     (I_y >= TEXT_Y) && (I_y < TEXT_Y+14);
    assign O_box = I_enable && (I_x >= TEXT_X-4) && (I_x < TEXT_X+TEXT_WIDTH+4) &&
                   (I_y >= TEXT_Y-4) && (I_y < TEXT_Y+18);
    assign O_white = I_enable && S_in_text && (S_col < 3'd5) && S_bitmap[S_bit_index];
endmodule

// Seven cells in legacy mode: "H=1 C=0" .. "H=1 C=3", "H=1 C=M".
// Eleven cells in shoulder mode: "C=3 P=3 W=0"; indices8..10 select W1..3.
// Constant glyphs, shifts and additions only; no pixel register or ROM file.
module osd_region_line #(
    parameter integer TEXT_X = 24,
    parameter integer TEXT_Y = 56,
    parameter integer SHOULDER_MODE = 0
)(
    input wire [10:0] I_x,
    input wire [9:0] I_y,
    input wire I_enable,
    input wire [3:0] I_sel,
    output wire O_box,
    output wire O_white
);
    function [34:0] f_glyph;
        input [3:0] glyph;
        begin
            case (glyph)
                4'd0: f_glyph = {5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                4'd1: f_glyph = {5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                4'd2: f_glyph = {5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                4'd3: f_glyph = {5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                4'd4: f_glyph = {5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001}; // H
                4'd5: f_glyph = {5'b00000,5'b11111,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000}; // =
                4'd6: f_glyph = {5'b01110,5'b10001,5'b10000,5'b10000,5'b10000,5'b10001,5'b01110}; // C
                4'd7: f_glyph = {5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001}; // M
                4'd8: f_glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000}; // P
                4'd9: f_glyph = {5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010}; // W
                default: f_glyph = 35'd0;
            endcase
        end
    endfunction

    wire [10:0] S_local_x = I_x - TEXT_X;
    wire [9:0] S_local_y = I_y - TEXT_Y;
    wire S_white_candidate = (I_sel >= 4'd8) && (I_sel <= 4'd10);
    wire S_c3 = S_white_candidate || I_sel[2];
    wire [1:0] S_p = S_white_candidate ? 2'd3 : I_sel[1:0];
    wire [1:0] S_w = S_white_candidate ? (I_sel[1:0] + 2'd1) : 2'd0;
    localparam integer TEXT_WIDTH = (SHOULDER_MODE != 0) ? 132 : 84;
    reg [3:0] S_glyph_id;
    reg [3:0] S_cell_x;
    always @(*) begin
        if (S_local_x < 11'd12) begin
            S_glyph_id = (SHOULDER_MODE != 0) ? 4'd6 : 4'd4;
            S_cell_x = S_local_x[3:0];
        end
        else if (S_local_x < 11'd24) begin
            S_glyph_id = 4'd5;
            S_cell_x = S_local_x - 11'd12;
        end
        else if (S_local_x < 11'd36) begin
            S_glyph_id = (SHOULDER_MODE != 0) ? (S_c3 ? 4'd3 : 4'd0) : 4'd1;
            S_cell_x = S_local_x - 11'd24;
        end
        else if (S_local_x < 11'd48) begin
            S_glyph_id = 4'd15; // space
            S_cell_x = S_local_x - 11'd36;
        end
        else if (S_local_x < 11'd60) begin
            S_glyph_id = (SHOULDER_MODE != 0) ? 4'd8 : 4'd6;
            S_cell_x = S_local_x - 11'd48;
        end
        else if (S_local_x < 11'd72) begin
            S_glyph_id = 4'd5;
            S_cell_x = S_local_x - 11'd60;
        end
        else if (S_local_x < 11'd84) begin
            S_glyph_id = (SHOULDER_MODE != 0) ? {2'b0, S_p} :
                         (I_sel < 4'd4) ? I_sel :
                         (I_sel == 4'd4) ? 4'd7 : 4'd15;
            S_cell_x = S_local_x - 11'd72;
        end
        else if (S_local_x < 11'd96) begin
            S_glyph_id = 4'd15; // space
            S_cell_x = S_local_x - 11'd84;
        end
        else if (S_local_x < 11'd108) begin
            S_glyph_id = 4'd9; // W
            S_cell_x = S_local_x - 11'd96;
        end
        else if (S_local_x < 11'd120) begin
            S_glyph_id = 4'd5;
            S_cell_x = S_local_x - 11'd108;
        end
        else begin
            S_glyph_id = {2'b0, S_w};
            S_cell_x = S_local_x - 11'd120;
        end
    end
    wire [2:0] S_col = S_cell_x[3:1];
    wire [2:0] S_row = S_local_y[3:1];
    wire [34:0] S_bitmap = f_glyph(S_glyph_id);
    wire [5:0] S_row_offset = {1'b0, S_row, 2'b00} + {3'b000, S_row};
    wire [5:0] S_bit_index = 6'd34 - S_row_offset - {3'd0, S_col};
    wire S_in_text = (I_x >= TEXT_X) && (I_x < TEXT_X + TEXT_WIDTH) &&
                     (I_y >= TEXT_Y) && (I_y < TEXT_Y + 14);
    assign O_box = I_enable && (I_x >= TEXT_X - 4) && (I_x < TEXT_X + TEXT_WIDTH + 4) &&
                   (I_y >= TEXT_Y - 4) && (I_y < TEXT_Y + 18);
    assign O_white = I_enable && S_in_text && (S_col < 3'd5) && S_bitmap[S_bit_index];
endmodule

// Seven 6x8 character cells, 2x scale: "T=128 A" / "T=128 L".
// Each glyph is 5x7 pixels plus spacing; no ROM latency or vendor primitive.
module osd_threshold_line #(
    parameter integer TEXT_X = 24,
    parameter integer TEXT_Y = 56
)(
    input wire [10:0] I_x,
    input wire [9:0] I_y,
    input wire I_enable,
    input wire [7:0] I_threshold,
    input wire I_locked,
    output wire O_box,
    output wire O_white
);
    function [11:0] f_decimal;
        input [7:0] value;
        reg [11:0] digits;
        integer i;
        begin
            digits = 12'd0;
            for (i = 7; i >= 0; i = i - 1) begin
                if (digits[3:0] >= 4'd5) digits[3:0] = digits[3:0] + 4'd3;
                if (digits[7:4] >= 4'd5) digits[7:4] = digits[7:4] + 4'd3;
                if (digits[11:8] >= 4'd5) digits[11:8] = digits[11:8] + 4'd3;
                digits = {digits[10:0], value[i]};
            end
            f_decimal = digits;
        end
    endfunction

    // Rows packed top-to-bottom, bit4 at the left of each five-bit row.
    function [34:0] f_glyph;
        input [3:0] glyph;
        begin
            case (glyph)
                4'd0: f_glyph = {5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                4'd1: f_glyph = {5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                4'd2: f_glyph = {5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                4'd3: f_glyph = {5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                4'd4: f_glyph = {5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                4'd5: f_glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
                4'd6: f_glyph = {5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                4'd7: f_glyph = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
                4'd8: f_glyph = {5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                4'd9: f_glyph = {5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                4'd10: f_glyph = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100}; // T
                4'd11: f_glyph = {5'b00000,5'b11111,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000}; // =
                4'd12: f_glyph = {5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001}; // A
                4'd13: f_glyph = {5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111}; // L
                default: f_glyph = 35'd0; // blank
            endcase
        end
    endfunction

    wire [11:0] S_decimal = f_decimal(I_threshold);
    wire [10:0] S_local_x = I_x - TEXT_X;
    wire [9:0] S_local_y = I_y - TEXT_Y;
    reg [3:0] S_glyph_id;
    reg [3:0] S_cell_x;
    always @(*) begin
        if      (S_local_x < 11'd12) begin S_glyph_id = 4'd10; S_cell_x = S_local_x; end
        else if (S_local_x < 11'd24) begin S_glyph_id = 4'd11; S_cell_x = S_local_x - 11'd12; end
        else if (S_local_x < 11'd36) begin S_glyph_id = S_decimal[11:8]; S_cell_x = S_local_x - 11'd24; end
        else if (S_local_x < 11'd48) begin S_glyph_id = S_decimal[7:4]; S_cell_x = S_local_x - 11'd36; end
        else if (S_local_x < 11'd60) begin S_glyph_id = S_decimal[3:0]; S_cell_x = S_local_x - 11'd48; end
        else if (S_local_x < 11'd72) begin S_glyph_id = 4'd14; S_cell_x = S_local_x - 11'd60; end
        else                        begin S_glyph_id = I_locked ? 4'd13 : 4'd12; S_cell_x = S_local_x - 11'd72; end
    end
    wire [2:0] S_col = S_cell_x[3:1];
    wire [2:0] S_row = S_local_y[3:1];
    wire [34:0] S_bitmap = f_glyph(S_glyph_id);
    wire [5:0] S_bit_index = 6'd34 - ({3'd0, S_row} * 6'd5) - {3'd0, S_col};
    wire S_in_text = (I_x >= TEXT_X) && (I_x < TEXT_X + 84) &&
                     (I_y >= TEXT_Y) && (I_y < TEXT_Y + 14);
    assign O_box = I_enable && (I_x >= TEXT_X - 4) && (I_x < TEXT_X + 84 + 4) &&
                   (I_y >= TEXT_Y - 4) && (I_y < TEXT_Y + 14 + 4);
    assign O_white = I_enable && S_in_text && (S_col < 3'd5) && S_bitmap[S_bit_index];
endmodule
