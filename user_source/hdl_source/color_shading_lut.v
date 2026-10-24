//=====================================================================
//  color_shading_lut.v  ——  颜色阴影校正增益表（1D 水平表，自动生成）
//
//  生成工具: 0 Project/tools/gen_shading_lut.py
//  网格:     10 列 x 1 行（把原来的 6 行按列垂直平均）
//  索引:     blk_x = x[10:7] (0..9)
//  格式:     Q8 定点，256 = 1.0x；只调 R/B，G 直通（保持亮度）
//
//  ★ 为什么从 10x6 改成 10x1
//    10x6 的分块增益是硬跳变的，块边界（每 128 像素 / 128 行）会形成
//    可见的竖条和横条。实测（摄像头画面注入连续 shading）：
//      10x6 硬跳变      -> 竖边界 G-R 跳变 14.11、横 10.69
//      10x6 双线性插值  -> 竖 0.48、横 0.48、残差 0.08（但 11 个乘法串行，
//                          实测 SWNS -10.9ns，75 MHz 跑不动）
//      10x1 + 水平插值  -> 竖 0.48、横 0.44、残差 1.87（只要 2 个乘法）
//    垂直方向改成不分块后，横条自然消失；残差 1.87 是缓慢渐变，肉眼不可见。
//=====================================================================
module color_shading_lut (
    input  wire [3:0] I_blk,
    output reg  [8:0] O_gain_r,
    output reg  [8:0] O_gain_b
);
    always @(*) begin
        case (I_blk)
            4'd0: begin O_gain_r = 9'd235; O_gain_b = 9'd248; end
            4'd1: begin O_gain_r = 9'd246; O_gain_b = 9'd255; end
            4'd2: begin O_gain_r = 9'd259; O_gain_b = 9'd264; end
            4'd3: begin O_gain_r = 9'd278; O_gain_b = 9'd276; end
            4'd4: begin O_gain_r = 9'd290; O_gain_b = 9'd284; end
            4'd5: begin O_gain_r = 9'd295; O_gain_b = 9'd285; end
            4'd6: begin O_gain_r = 9'd287; O_gain_b = 9'd278; end
            4'd7: begin O_gain_r = 9'd274; O_gain_b = 9'd269; end
            4'd8: begin O_gain_r = 9'd260; O_gain_b = 9'd259; end
            4'd9: begin O_gain_r = 9'd249; O_gain_b = 9'd250; end
            default: begin O_gain_r = 9'd256; O_gain_b = 9'd256; end
        endcase
    end
endmodule
