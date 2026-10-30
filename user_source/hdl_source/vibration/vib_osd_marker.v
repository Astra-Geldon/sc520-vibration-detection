//=============================================================================
//  vib_osd_marker.v  ——  在 HDMI 画面上叠加调试标记
//
//  目的：上板时肉眼对齐"手机方块"和"固定纹理块"的实时位置。
//        之前靠猜坐标，结果固定块在右下角、方块在左上角，白测了一轮。
//
//  画两个东西：
//    1) 左上角一个**不对称的 L 形参考标记**（绿色）
//         一个 32x32 实心方块 + 一条向右伸到 x=160 的横条
//         用来判断画面有没有被镜像/翻转：
//           正常 → 长臂指向右边
//           镜像 → 长臂跑到左边
//    2) 固定纹理块的**外框**（品红，2 像素粗）
//         坐标来自 st_fx_pos = {29'd0, valid, row[2:0], col[2:0]}
//         块大小：显示 1280x720 / 网格 8x6 → 每块 160x120 像素
//
//  ★ 这个模块插在 hdmi_mixer → hdmi_tx 之间，**在算法取数之后**，
//    所以画的标记完全不影响振动算法（算法从 ISP 输出取数）。
//
//  行/帧同步不依赖 vs 极性：x 在 de 上升沿清 0（每行），
//  y 在每个 de 上升沿 +1、到 720 回绕（每帧正好 720 行有效）。
//=============================================================================
`ifndef VIB_OSD_MARKER_V
`define VIB_OSD_MARKER_V

module vib_osd_marker (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        I_vs,
    input  wire        I_de,
    input  wire [23:0] I_data,
    input  wire [31:0] I_pos,       // {29'd0, valid, row[2:0], col[2:0]}
    output reg         O_vs,
    output reg         O_de,
    output reg  [23:0] O_data
);

    localparam [10:0] W = 11'd1280;
    localparam [9:0]  H = 10'd720;

    reg [10:0] x;          // 行内像素
    reg [9:0]  y;          // 有效行
    reg        de_d;

    wire        de_rise = I_de & ~de_d;
    wire [2:0]  col     = I_pos[2:0];
    wire [2:0]  row     = I_pos[5:3];
    wire        fxv     = I_pos[6];

    // 固定块的外框（显示像素坐标）
    // 块大小：显示 1280x720 / 网格 8x6 → 每块 160x120 显示像素
    //   用常数乘法，TD 会自动展开成移位加法（比手写拼接不容易错）
    wire [10:0] bx0 = col * 11'd160;
    wire [10:0] bx1 = bx0 + 11'd159;
    wire [9:0]  by0 = row * 10'd120;
    wire [9:0]  by1 = by0 + 10'd119;

    // ---- 参考标记：左上角 L 形 ----
    wire ref_sq = (x >= 11'd8  && x <= 11'd39) && (y >= 10'd8 && y <= 10'd39);
    wire ref_bar = (x >= 11'd8 && x <= 11'd159) && (y >= 10'd8 && y <= 10'd15);

    // ---- 固定块外框：2 像素粗 ----
    wire in_x = (x >= bx0 && x <= bx1);
    wire in_y = (y >= by0 && y <= by1);
    wire on_edge = (x >= bx0 && x <= bx0 + 11'd1) || (x >= bx1 - 11'd1 && x <= bx1) ||
                (y >= by0 && y <= by0 + 10'd1) || (y >= by1 - 10'd1 && y <= by1);
    wire frm = fxv && in_x && in_y && on_edge;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 11'd0;
            y <= 10'd0;
            de_d <= 1'b0;
            O_vs <= 1'b0;
            O_de <= 1'b0;
            O_data <= 24'd0;
        end
        else begin
            de_d <= I_de;
            O_vs <= I_vs;
            O_de <= I_de;
            O_data <= I_data;

            if (I_de) begin
                if (de_rise) begin
                    x <= 11'd0;
                    y <= (y == H - 10'd1) ? 10'd0 : (y + 10'd1);
                end
                else begin
                    x <= (x == W - 11'd1) ? 11'd0 : (x + 11'd1);
                end

                // 叠加（后写覆盖）
                if (ref_sq || ref_bar)
                    O_data <= 24'h00FF00;      // 绿
                else if (frm)
                    O_data <= 24'hFF00FF;      // 品红
            end
            else begin
                x <= 11'd0;
            end
        end
    end

endmodule

`endif
