// ★★ 去掉下面这行的注释即可旁路 AWB（做颜色对比实验）★★
// 2026-10-24：旁路实验**失败**，已恢复。
//   实测证据：AWB 开（osd_mode0/pll75）行末列均值差 = 1.1（正常）；
//             AWB 旁路（awb_off）行末差 = 27.9，画面右侧出现 58 像素宽的错位竖带。
//   原因：awb 模块内部有 10 块 ERAM 做延迟缓冲，旁路后这段缓冲消失，
//         上下游吞吐率不匹配 -> DDR 写入丢像素 -> 行末错位。
//         原注释"AXI-Stream 不依赖固定延迟"的假设是错的。
//   所以：这条旁路省 5,438 slice，但代价是画面错位，不可接受。
//`define AWB_BYPASS

module isp_top (
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,
    input 			O_tready		,
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready
);
 
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 


  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  wire [ 95:0] awb_O_tdata;  //synthesis keep 
  wire         awb_O_tvalid;  //synthesis keep 
  wire         awb_O_tready;  //synthesis keep 

  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
  wire [127:0] awb_O_tdata_128;  //synthesis keep 

  assign awb_O_tready = O_tready;
  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = awb_O_tlast    ;
  assign O_tuser  = awb_O_tuser_128    ;
  assign O_tvalid = awb_O_tvalid_128   ;
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
demosaic #(
    .IMG_HEIGHT          (720 ),  // 图像高度
    .IMG_WIDTH           (1280),  // 图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(I_tdata)	,  // AXI4-Stream视频数据
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(I_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(I_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(I_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

`ifdef AWB_BYPASS
//=============================================================================
//  AWB 旁路实验（2026-10-18）
//
//  目的：判断 SC520 传感器内部是否已经做了 AWB。
//        如果传感器自带 AWB，FPGA 再算一次就是**双重校正**，
//        两个自适应环互相追打，会形成低频猎振 → 污染振动频率检测。
//
//  用法：把**文件第 2 行**的 define AWB_BYPASS 注释去掉再编译，对比 HDMI 画面颜色。
//        颜色正常  → 传感器自带 AWB → FPGA 这套可以永久删掉（省 9,926）
//        发绿/发紫  → 传感器没做   → FPGA 的 AWB 必需，改平滑帧级
//
//  注意：旁路后 AWB 的延迟消失，但 AXI-Stream 不依赖固定延迟，
//        下游的 96→128 转换和时间戳都不受影响。
//=============================================================================
    assign m_aixs_tready = O_tready;
    assign awb_O_tdata   = m_aixs_tdata_96;
    assign awb_O_tlast   = m_aixs_tlast;
    assign awb_O_tuser   = m_aixs_tuser;
    assign awb_O_tvalid  = m_aixs_tvalid;
`else
awb #(
    .IMG_HEIGHT(720 ),
    .IMG_WIDTH (1280)
) u_awb (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),
    .I_tvalid(m_aixs_tvalid),
    .I_tready(m_aixs_tready),
    .O_tlast (awb_O_tlast ),
    .O_tuser (awb_O_tuser ),
    .O_tdata (awb_O_tdata ),
    .O_tvalid(awb_O_tvalid),
    .O_tready(awb_O_tready)
);
`endif

    //------------------------------------------------------------------
    //  伽马校正（2026-10-18 补入）
    //
    //  为什么必须加：模块 axis_gamma_rgb96 一直定义在本文件末尾，
    //  但从来没有被例化过 —— 所以 10 位传感器到 8 位显示是**线性映射**，
    //  中灰被严重压暗（实测平均灰度 24~48，而传感器还有余量）。
    //  这条曲线 y = 255*(x/255)^0.7 把暗部和中调抬高 30~60%，
    //  亮部基本不变，正好补上"暗淡"的问题。
    //
    //  位置：AWB 之后、96→128 转换之前。
    //  代价：多 1 拍流水 = 画面右移 4 个像素（96 位总线 = 4 像素）
    //        这个偏移对显示无影响，但记在这里以备后查。
    //------------------------------------------------------------------
    wire        gam_O_tlast, gam_O_tuser, gam_O_tvalid;
    wire [95:0] gam_O_tdata;

    axis_gamma_rgb96 u_gamma (
        .I_clk   ( axi4s_video_aclk ),
        .I_rst_n ( I_rst_n           ),
        .I_tlast ( awb_O_tlast       ),
        .I_tuser ( awb_O_tuser       ),
        .I_tdata ( awb_O_tdata       ),
        .I_tvalid( awb_O_tvalid      ),
        .O_tlast ( gam_O_tlast       ),
        .O_tuser ( gam_O_tuser       ),
        .O_tdata ( gam_O_tdata       ),
        .O_tvalid( gam_O_tvalid      )
    );

    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( gam_O_tuser       ),
        .I_96b_valid        ( gam_O_tvalid      ),
        .I_96b_data         ( gam_O_tdata       ),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
        .O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule


// Four-pixel RGB888 gamma stage.  The 16-segment curve approximates
// y = 255 * (x / 255)^0.7.  Mid-tone lift WITHOUT the heavy shadow lift,
// so the sensor black-level noise is NOT amplified (no grey veil).
// Adds one registered pipeline cycle.
module axis_gamma_rgb96 (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    output reg         O_tlast,
    output reg         O_tuser,
    output reg  [95:0] O_tdata,
    output reg         O_tvalid
);

    function [7:0] gamma07;
        input [7:0] value;
        reg [7:0] base;
        reg [7:0] delta;
        reg [11:0] interpolation;
        begin
            // 2026-10-24 重设计：原曲线中间段 delta=14，斜率 14/16 = 0.875 < 1，
            // 对「有效动态范围只有 78 级」的画面是**反向压缩**对比度。
            // 新曲线：暗部基本保留（delta 13~22，输入 47 -> 输出 45 几乎不变），
            // 高光压缩（delta 6~1）避免过曝。
            // 预期：输入 62~140（78 级）-> 输出约 56~181（125 级，x1.6）。
            // 自检：base 累加应 0→13→28→46→68→94→120→146→172→198→222→239→247→251→253→254→255
            case (value[7:4])
                4'h0: begin base = 8'd0;   delta = 8'd13; end
                4'h1: begin base = 8'd13;  delta = 8'd15; end
                4'h2: begin base = 8'd28;  delta = 8'd18; end
                4'h3: begin base = 8'd46;  delta = 8'd22; end
                4'h4: begin base = 8'd68;  delta = 8'd26; end
                4'h5: begin base = 8'd94;  delta = 8'd26; end
                4'h6: begin base = 8'd120; delta = 8'd26; end
                4'h7: begin base = 8'd146; delta = 8'd26; end
                4'h8: begin base = 8'd172; delta = 8'd26; end
                4'h9: begin base = 8'd198; delta = 8'd24; end
                4'ha: begin base = 8'd222; delta = 8'd17; end
                4'hb: begin base = 8'd239; delta = 8'd8; end
                4'hc: begin base = 8'd247; delta = 8'd4; end
                4'hd: begin base = 8'd251; delta = 8'd2; end
                4'he: begin base = 8'd253; delta = 8'd1; end
                default: begin base = 8'd254; delta = 8'd1; end
            endcase

            interpolation = delta * value[3:0] + 8;
            if (value == 8'hff)
                gamma07 = 8'hff;
            else
                gamma07 = base + (interpolation >> 4);
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            O_tdata  <= 96'd0;
            O_tvalid <= 1'b0;
        end else begin
            O_tlast  <= I_tlast;
            O_tuser  <= I_tuser;
            O_tvalid <= I_tvalid;
            if (I_tvalid) begin
                O_tdata <= {
                    gamma07(I_tdata[95:88]), gamma07(I_tdata[87:80]), gamma07(I_tdata[79:72]),
                    gamma07(I_tdata[71:64]), gamma07(I_tdata[63:56]), gamma07(I_tdata[55:48]),
                    gamma07(I_tdata[47:40]), gamma07(I_tdata[39:32]), gamma07(I_tdata[31:24]),
                    gamma07(I_tdata[23:16]), gamma07(I_tdata[15:8]),  gamma07(I_tdata[7:0])
                };
            end else begin
                O_tdata <= 96'd0;
            end
        end
    end

endmodule


// Centre crop for the ISP's four-pixel-wide RGB888 stream.  Frame start is
// intentionally forwarded at the original frame boundary so video_in can
// reset its asynchronous FIFO before the first selected row arrives.
module axis_crop_rgb96 #(
    parameter integer IN_WIDTH   = 1792,
    parameter integer IN_HEIGHT  = 1080,
    parameter integer OUT_WIDTH  = 1600,
    parameter integer OUT_HEIGHT = 900,
    parameter integer X_START    = 96,
    parameter integer Y_START    = 90
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    output wire        O_tlast,
    output wire        O_tuser,
    output wire [95:0] O_tdata,
    output wire        O_tvalid
);

    localparam integer X_START_BEAT = X_START / 4;
    localparam integer OUT_BEATS    = OUT_WIDTH / 4;
    localparam integer X_END_BEAT   = X_START_BEAT + OUT_BEATS;

    reg [9:0]  S_hcnt;
    reg [10:0] S_vcnt;

    wire [9:0]  S_current_h = I_tuser ? 10'd0 : S_hcnt;
    wire [10:0] S_current_v = I_tuser ? 11'd0 : S_vcnt;
    wire S_inside = (S_current_h >= X_START_BEAT) &&
                    (S_current_h < X_END_BEAT) &&
                    (S_current_v >= Y_START) &&
                    (S_current_v < (Y_START + OUT_HEIGHT));

    assign O_tdata  = I_tdata;
    assign O_tvalid = I_tvalid && S_inside;
    assign O_tlast  = O_tvalid && (S_current_h == (X_END_BEAT - 1));
    assign O_tuser  = I_tuser;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_hcnt <= 10'd0;
            S_vcnt <= 11'd0;
        end
        else if(I_tuser) begin
            S_hcnt <= (I_tvalid && !I_tlast) ? 10'd1 : 10'd0;
            S_vcnt <= (I_tvalid && I_tlast) ? 11'd1 : 11'd0;
        end
        else if(I_tvalid) begin
            if(I_tlast) begin
                S_hcnt <= 10'd0;
                S_vcnt <= (S_vcnt == IN_HEIGHT - 1) ? 11'd0 : S_vcnt + 1'b1;
            end
            else begin
                S_hcnt <= S_hcnt + 1'b1;
            end
        end
    end

endmodule
