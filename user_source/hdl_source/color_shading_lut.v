//=====================================================================
//  color_shading_lut.v —— 颜色阴影校正增益表（1D水平表）
//
//  当前先采用历史stage9-shading-1d表。它只沿水平方向平滑插值，不在
//  y=360处做上下两段硬切换，从而避免明显的水平色带。
//  格式：Q8定点，256=1.0；只调R/B，G直通。
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
            4'd3: begin O_gain_r = 9'd278; O_gain_b = 9'd275; end
            4'd4: begin O_gain_r = 9'd291; O_gain_b = 9'd284; end
            4'd5: begin O_gain_r = 9'd295; O_gain_b = 9'd285; end
            4'd6: begin O_gain_r = 9'd287; O_gain_b = 9'd279; end
            4'd7: begin O_gain_r = 9'd274; O_gain_b = 9'd269; end
            4'd8: begin O_gain_r = 9'd260; O_gain_b = 9'd259; end
            4'd9: begin O_gain_r = 9'd249; O_gain_b = 9'd250; end
            default: begin O_gain_r = 9'd256; O_gain_b = 9'd256; end
        endcase
    end
endmodule
