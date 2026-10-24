//=====================================================================
//  color_shading_lut.v  ——  颜色阴影校正增益表（自动生成，勿手改）
//
//  生成工具: 0 Project/tools/gen_shading_lut.py
//  源图:     docs/captures/awb_v2serial/*.png
//  网格:     10 列 x 6 行 = 60 块（每块 128 x 120 像素）
//  块索引:   blk = blk_y * 10 + blk_x,  blk_x = x[10:7], blk_y = y[9:7]
//  格式:     Q8 定点，256 = 1.0x；只调 R/B，G 直通（保持亮度）
//
//  标定原理: 每块增益 = 块内 G 均值 / 块内 R(或B) 均值，
//            使块内三通道相等，从而消除镜头/传感器的 color shading。
//  OSD 区域的块已排除统计（Logo 右上、文字标签左上）。
//=====================================================================
module color_shading_lut (
    input  wire [5:0] I_blk,
    output reg  [8:0] O_gain_r,
    output reg  [8:0] O_gain_b
);
    always @(*) begin
        case (I_blk)
            6'd0 : begin O_gain_r = 9'd245; O_gain_b = 9'd251; end  // y0 x0
            6'd1 : begin O_gain_r = 9'd252; O_gain_b = 9'd262; end  // y0 x1
            6'd2 : begin O_gain_r = 9'd262; O_gain_b = 9'd270; end  // y0 x2
            6'd3 : begin O_gain_r = 9'd275; O_gain_b = 9'd276; end  // y0 x3
            6'd4 : begin O_gain_r = 9'd282; O_gain_b = 9'd278; end  // y0 x4
            6'd5 : begin O_gain_r = 9'd287; O_gain_b = 9'd277; end  // y0 x5
            6'd6 : begin O_gain_r = 9'd283; O_gain_b = 9'd272; end  // y0 x6
            6'd7 : begin O_gain_r = 9'd275; O_gain_b = 9'd267; end  // y0 x7
            6'd8 : begin O_gain_r = 9'd266; O_gain_b = 9'd261; end  // y0 x8
            6'd9 : begin O_gain_r = 9'd258; O_gain_b = 9'd248; end  // y0 x9
            6'd10: begin O_gain_r = 9'd237; O_gain_b = 9'd248; end  // y1 x0
            6'd11: begin O_gain_r = 9'd246; O_gain_b = 9'd251; end  // y1 x1
            6'd12: begin O_gain_r = 9'd260; O_gain_b = 9'd265; end  // y1 x2
            6'd13: begin O_gain_r = 9'd280; O_gain_b = 9'd281; end  // y1 x3
            6'd14: begin O_gain_r = 9'd293; O_gain_b = 9'd288; end  // y1 x4
            6'd15: begin O_gain_r = 9'd298; O_gain_b = 9'd287; end  // y1 x5
            6'd16: begin O_gain_r = 9'd291; O_gain_b = 9'd280; end  // y1 x6
            6'd17: begin O_gain_r = 9'd278; O_gain_b = 9'd271; end  // y1 x7
            6'd18: begin O_gain_r = 9'd263; O_gain_b = 9'd260; end  // y1 x8
            6'd19: begin O_gain_r = 9'd252; O_gain_b = 9'd254; end  // y1 x9
            6'd20: begin O_gain_r = 9'd235; O_gain_b = 9'd250; end  // y2 x0
            6'd21: begin O_gain_r = 9'd246; O_gain_b = 9'd259; end  // y2 x1
            6'd22: begin O_gain_r = 9'd258; O_gain_b = 9'd262; end  // y2 x2
            6'd23: begin O_gain_r = 9'd283; O_gain_b = 9'd280; end  // y2 x3
            6'd24: begin O_gain_r = 9'd301; O_gain_b = 9'd293; end  // y2 x4
            6'd25: begin O_gain_r = 9'd307; O_gain_b = 9'd295; end  // y2 x5
            6'd26: begin O_gain_r = 9'd297; O_gain_b = 9'd287; end  // y2 x6
            6'd27: begin O_gain_r = 9'd280; O_gain_b = 9'd273; end  // y2 x7
            6'd28: begin O_gain_r = 9'd262; O_gain_b = 9'd260; end  // y2 x8
            6'd29: begin O_gain_r = 9'd249; O_gain_b = 9'd250; end  // y2 x9
            6'd30: begin O_gain_r = 9'd231; O_gain_b = 9'd247; end  // y3 x0
            6'd31: begin O_gain_r = 9'd245; O_gain_b = 9'd259; end  // y3 x1
            6'd32: begin O_gain_r = 9'd260; O_gain_b = 9'd272; end  // y3 x2
            6'd33: begin O_gain_r = 9'd286; O_gain_b = 9'd284; end  // y3 x3
            6'd34: begin O_gain_r = 9'd301; O_gain_b = 9'd292; end  // y3 x4
            6'd35: begin O_gain_r = 9'd305; O_gain_b = 9'd294; end  // y3 x5
            6'd36: begin O_gain_r = 9'd293; O_gain_b = 9'd284; end  // y3 x6
            6'd37: begin O_gain_r = 9'd278; O_gain_b = 9'd273; end  // y3 x7
            6'd38: begin O_gain_r = 9'd260; O_gain_b = 9'd260; end  // y3 x8
            6'd39: begin O_gain_r = 9'd246; O_gain_b = 9'd249; end  // y3 x9
            6'd40: begin O_gain_r = 9'd231; O_gain_b = 9'd246; end  // y4 x0
            6'd41: begin O_gain_r = 9'd244; O_gain_b = 9'd251; end  // y4 x1
            6'd42: begin O_gain_r = 9'd258; O_gain_b = 9'd261; end  // y4 x2
            6'd43: begin O_gain_r = 9'd276; O_gain_b = 9'd272; end  // y4 x3
            6'd44: begin O_gain_r = 9'd290; O_gain_b = 9'd281; end  // y4 x4
            6'd45: begin O_gain_r = 9'd293; O_gain_b = 9'd284; end  // y4 x5
            6'd46: begin O_gain_r = 9'd284; O_gain_b = 9'd277; end  // y4 x6
            6'd47: begin O_gain_r = 9'd270; O_gain_b = 9'd267; end  // y4 x7
            6'd48: begin O_gain_r = 9'd255; O_gain_b = 9'd258; end  // y4 x8
            6'd49: begin O_gain_r = 9'd244; O_gain_b = 9'd248; end  // y4 x9
            6'd50: begin O_gain_r = 9'd231; O_gain_b = 9'd246; end  // y5 x0
            6'd51: begin O_gain_r = 9'd244; O_gain_b = 9'd247; end  // y5 x1
            6'd52: begin O_gain_r = 9'd257; O_gain_b = 9'd253; end  // y5 x2
            6'd53: begin O_gain_r = 9'd266; O_gain_b = 9'd260; end  // y5 x3
            6'd54: begin O_gain_r = 9'd275; O_gain_b = 9'd269; end  // y5 x4
            6'd55: begin O_gain_r = 9'd278; O_gain_b = 9'd272; end  // y5 x5
            6'd56: begin O_gain_r = 9'd273; O_gain_b = 9'd271; end  // y5 x6
            6'd57: begin O_gain_r = 9'd263; O_gain_b = 9'd263; end  // y5 x7
            6'd58: begin O_gain_r = 9'd253; O_gain_b = 9'd256; end  // y5 x8
            6'd59: begin O_gain_r = 9'd244; O_gain_b = 9'd248; end  // y5 x9
            default: begin O_gain_r = 9'd256; O_gain_b = 9'd256; end
        endcase
    end
endmodule
