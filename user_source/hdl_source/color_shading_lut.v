//=====================================================================
//  color_shading_lut.v  ——  颜色阴影增益表（2 段垂直 x 10 列，自动生成）
//
//  标定源图：docs/captures/raw_pass/grab_190905_01.png（RAW_PASS 抓的均匀天花板）
//  格式    ：Q8 定点，256=1.0；只调 R/B，G 直通
//  索引    ：{I_vsel, I_blk}  I_vsel=0 上段(y<360) 1 下段；I_blk=列 0..9
//
//  ★ 表值 = 原始 G/R（完全校正），不做归一化
//    之前试过归一化到平均 1.0（只校形状、整体交给 AWB），实测更糟：
//    九宫格 G/R 中央 1.11（偏绿）/ 左侧 0.70（偏红），极差 0.44。
//    原因：归一化只把空间差异压平 42%，剩下 58% 靠 AWB —— 但 AWB 是
//    全局单增益，根本无法处理空间差异，于是中央绿、两侧红。
//    正确做法：CSC 必须把空间完全校平（gain=原始 G/R），之后 AWB 只需
//    1.0 附近的增益就能收敛，两者正交、不打架。
//=====================================================================
module color_shading_lut (
    input  wire [3:0] I_blk,
    input  wire       I_vsel,
    output reg  [8:0] O_gain_r,
    output reg  [8:0] O_gain_b
);
    always @(*) begin
        case ({I_vsel, I_blk})
            5'd0: begin O_gain_r = 9'd290; O_gain_b = 9'd354; end   // 上段 列0
            5'd1: begin O_gain_r = 9'd309; O_gain_b = 9'd373; end   // 上段 列1
            5'd2: begin O_gain_r = 9'd337; O_gain_b = 9'd392; end   // 上段 列2
            5'd3: begin O_gain_r = 9'd370; O_gain_b = 9'd411; end   // 上段 列3
            5'd4: begin O_gain_r = 9'd395; O_gain_b = 9'd419; end   // 上段 列4
            5'd5: begin O_gain_r = 9'd405; O_gain_b = 9'd421; end   // 上段 列5
            5'd6: begin O_gain_r = 9'd393; O_gain_b = 9'd410; end   // 上段 列6
            5'd7: begin O_gain_r = 9'd370; O_gain_b = 9'd395; end   // 上段 列7
            5'd8: begin O_gain_r = 9'd343; O_gain_b = 9'd377; end   // 上段 列8
            5'd9: begin O_gain_r = 9'd322; O_gain_b = 9'd363; end   // 上段 列9
            5'd10: begin O_gain_r = 9'd292; O_gain_b = 9'd362; end   // 下段 列0
            5'd11: begin O_gain_r = 9'd312; O_gain_b = 9'd381; end   // 下段 列1
            5'd12: begin O_gain_r = 9'd346; O_gain_b = 9'd393; end   // 下段 列2
            5'd13: begin O_gain_r = 9'd391; O_gain_b = 9'd399; end   // 下段 列3
            5'd14: begin O_gain_r = 9'd433; O_gain_b = 9'd411; end   // 下段 列4
            5'd15: begin O_gain_r = 9'd448; O_gain_b = 9'd416; end   // 下段 列5
            5'd16: begin O_gain_r = 9'd436; O_gain_b = 9'd401; end   // 下段 列6
            5'd17: begin O_gain_r = 9'd402; O_gain_b = 9'd380; end   // 下段 列7
            5'd18: begin O_gain_r = 9'd361; O_gain_b = 9'd364; end   // 下段 列8
            5'd19: begin O_gain_r = 9'd329; O_gain_b = 9'd353; end   // 下段 列9
            default: begin O_gain_r = 9'd256; O_gain_b = 9'd256; end
        endcase
    end
endmodule
