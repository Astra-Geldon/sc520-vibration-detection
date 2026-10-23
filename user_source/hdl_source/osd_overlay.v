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
//                 mode 0 -> 原图     mode 1 -> 灰度     mode 2 -> 二值化
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

    // ---- 画面尺寸（与 VTC 一致）----
    parameter integer H_ACTIVE    = 1280,
    parameter integer V_ACTIVE    = 720,

    // ---- Logo 窗口（右上角）----
    parameter integer LOGO_W      = 128,
    parameter integer LOGO_H      = 80,
    parameter integer LOGO_X      = 1136,   // 1280-128-16
    parameter integer LOGO_Y      = 16,

    // ---- 文字窗口（左上角）----
    parameter integer TEXT_X      = 24,     // 第一个字的左上角
    parameter integer TEXT_Y      = 24,
    parameter integer BOX_PAD     = 8       // 黑底外扩
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_de,        // 像素有效
    input  wire        I_vs,        // 场同步（用来清行计数）
    input  wire [ 1:0] I_mode,      // 当前算法（来自 img_mode_sel）
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
    reg [2:0] S_base;       // 起始字形序号
    reg [1:0] S_nchars;     // 本标签的字数

    always @(*) begin
        case (I_mode)
            2'd0:    begin S_base = 3'd0; S_nchars = 2'd2; end   // 原图
            2'd1:    begin S_base = 3'd2; S_nchars = 2'd2; end   // 灰度
            2'd2:    begin S_base = 3'd4; S_nchars = 2'd3; end   // 二值化
            default: begin S_base = 3'd0; S_nchars = 2'd2; end   // 未定义 -> 原图
        endcase
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
    wire [31:0] S_logo_word;
    osd_logo_rom u_logo_rom (
        .I_addr ( {S_ly[6:0], S_lx[6:4]} ),
        .O_word ( S_logo_word             )
    );

    // 32 bit word 里装 16 个像素（2 bit/像素），取 S_lx[3:0] 对应的那一个
    wire [4:0]  S_px_shift = 5'd30 - {S_lx[3:0], 1'b0};        // 2*(15-lx)
    wire [1:0]  S_logo_q   = (S_logo_word >> S_px_shift) & 2'b11;

    //------------------------------------------------------------------
    //  文字窗口（左上角黑底 + 白字）
    //------------------------------------------------------------------
    wire [6:0] S_text_px = {S_nchars, 4'h0};                 // 16 * nchars

    wire S_in_box  = (S_x >= TEXT_X - BOX_PAD) &&
                     (S_x <  TEXT_X + S_text_px + BOX_PAD) &&
                     (S_y >= TEXT_Y - BOX_PAD) &&
                     (S_y <  TEXT_Y + 16 + BOX_PAD);

    wire S_in_text = (S_x >= TEXT_X) && (S_x < TEXT_X + S_text_px) &&
                     (S_y >= TEXT_Y) && (S_y < TEXT_Y + 16);

    wire [3:0] S_char_i = (S_x - TEXT_X) >> 4;             // 第几个字
    wire [3:0] S_col    = (S_x - TEXT_X) & 4'hF;           // 字内列
    wire [3:0] S_row    = (S_y - TEXT_Y);                  // 字内行

    wire [2:0] S_glyph  = S_base + S_char_i[2:0];

    wire [15:0] S_font_row;

    osd_font_rom u_font (
        .I_addr ( {S_glyph, S_row} ),
        .O_row  ( S_font_row       )
    );

    // 16 位行位图，bit15 = 最左；用变量下标取当前列（可综合）
    wire [3:0] S_bit_idx  = 4'd15 - S_col;
    wire       S_text_bit = S_font_row[S_bit_idx];

    //------------------------------------------------------------------
    //  叠加（纯组合 3 选 1）
    //     Logo 不透明像素 > 文字框（黑底/白字） > 原视频
    //------------------------------------------------------------------
    wire [23:0] S_logo_rgb = (S_logo_q == 2'd1) ? C_NAVY :
                             (S_logo_q == 2'd2) ? C_RED  : 24'h00_00_00;

    wire S_logo_opaque = S_in_logo && (S_logo_q != 2'd0);

    generate
        if (OSD_EN != 0) begin : g_osd_on
            assign O_data = S_logo_opaque ? S_logo_rgb  :
                            S_in_text     ? (S_text_bit ? C_WHITE : C_BLACK) :
                            S_in_box      ? C_BLACK :
                                            I_data;
        end
        else begin : g_osd_off
            assign O_data = I_data;
        end
    endgenerate

endmodule
