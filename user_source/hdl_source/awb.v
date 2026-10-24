/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
WebSite:https://www.milianke.com
TechWeb:https://www.uisrc.com
tmall-shop:https://milianke.tmall.com
jd-shop:https://milianke.jd.com
taobao-shop: https://milianke.taobao.com
Description: 
The reference demo provided by Milianke is only used for learning. 
We cannot ensure that the demo itself is free of bugs, so users 
should be responsible for the technical problems and consequences
caused by the use of their own products.
@Author      :   XiaoQingquan 
@Time        :   2024/10 
version:     :   
@Description :   在原基础上删去了一些赘余的代码，并且优化了时序，加入BRAM IP核，
                 让从除法器出来的每一个数据都可以对上相应的像素数据进行增益，使
                 得它的适用行更加广泛了。
*****************************************************************/
//=====================================================================
//  RAW_PASS 诊断模式（2026-10-24）
//  打开 = AWB 增益固定 1.0x（信号延迟链仍保留 50 拍，不会错位），
//         配合 isp_top.v 里同名的 RAW_PASS（Gamma 直通），
//         即可把 demosaic 之后、未做白平衡/未做 Gamma 的原始 RGB 送到 HDMI。
//  注意：**必须和 isp_top.v 里的 RAW_PASS 保持一致**（一起开/一起关）。
//  交付版本必须注释掉。
//=====================================================================
`ifndef RAW_PASS      // 自保护：若 isp_top.v 已定义则跳过
//`define RAW_PASS   // 交付版本关闭：恢复 AWB 增益和 Gamma
`endif

module awb  #(   
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920
) 
(
    input                   I_clk  ,
    input                   I_rst_n,


    input                   I_tlast  ,
    input                   I_tuser  ,
    input [95:0]            I_tdata  ,
    input                   I_tvalid , 
    output                  I_tready ,

    output                  O_tlast  ,
    output                  O_tuser  ,
    output [95:0]           O_tdata  ,
    output                  O_tvalid ,
    input                   O_tready
);

/*****************************************************************
                          RGB565תRGB888                                        
*****************************************************************/

    // //RGB565??????888
    // wire [4:0]  rgb565_r   = I_st_data[11+:5];
    // wire [5:0]  rgb565_g   = I_st_data[5+:6];
    // wire [4:0]  rgb565_b   = I_st_data[0+:5];
    
    // wire [23:0] rgb888     = {{rgb565_r[4:0],rgb565_r[2:0]},{rgb565_g[5:0],rgb565_g[1:0]},{rgb565_b[4:0],rgb565_b[2:0]}};
    
    // wire [7:0]  rgb888_r   = rgb888[16+:8];
    // wire [7:0]  rgb888_g   = rgb888[8+:8] ;
    // wire [7:0]  rgb888_b   = rgb888[0+:8] ;
    
  /*****************************************************************
                          中间信号                                        
*****************************************************************/


  reg         I_tvalid_r0,I_tvalid_r1;
  reg  [95:0] I_tdata_d0,I_tdata_d1;


  //累加RGB通道的�??
  reg  [31:0]         sum_r[0:3];
  reg  [31:0]         sum_g[0:3];
  reg  [31:0]         sum_b[0:3];

  // 统计有效样本数。当前每个96位包取1个像素，720p一帧最多约230400个样本。
  // 没有样本数保护时，过曝/肤色筛选可能让累加器只剩初始值1，进而算出异常大增益。
  reg  [19:0]         sample_count;
  localparam integer  AWB_MIN_SAMPLES = 4096;

  
  wire  [95:0]        data_d0 ;
  wire                valid_d0;
  wire                I_tuser_r0;    

  reg                 I_tuser_r1;

  reg   [95:0]        data_d1 ;
  reg                 valid_d1;
  reg   [9:0]         rgb_sum[0:3];//每个像素点RGB的和
  /*****************************************************************
                            平均值计�??                                      
*****************************************************************/

// 对输入数据和有效信号进行寄存，形成流水线
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        I_tdata_d0  <= 0;
        I_tdata_d1  <= 0;
        {I_tvalid_r0,I_tvalid_r1} <= 0;
    end else begin
        I_tdata_d0  <= I_tdata   ;
        I_tdata_d1  <= I_tdata_d0;
        I_tvalid_r0 <= I_tvalid;
        I_tvalid_r1 <= I_tvalid_r0;
    end
end

// 将输入数据拆分为4个像素的RGB分量
wire [7:0] rgb888_r_d[0:3];
wire [7:0] rgb888_g_d[0:3];
wire [7:0] rgb888_b_d[0:3];

assign  rgb888_r_d[0] = I_tdata[16+:8];
assign  rgb888_g_d[0] = I_tdata[8+:8];
assign  rgb888_b_d[0] = I_tdata[0+:8];


// 将输入数据拆分为4个像素的RGB分量
wire [7:0] rgb888_r_d0[0:3];
wire [7:0] rgb888_g_d0[0:3];
wire [7:0] rgb888_b_d0[0:3];

assign  rgb888_r_d0[0] = I_tdata_d0[16+:8];
assign  rgb888_g_d0[0] = I_tdata_d0[8+:8];
assign  rgb888_b_d0[0] = I_tdata_d0[0+:8];


        ///削弱白色
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                rgb_sum[0] <= 0;
            end
            else if(I_tvalid)begin
                // 显式扩展到10位，避免三路8位相加时发生位宽截断。
                rgb_sum[0] <= {2'b0, rgb888_r_d[0]} +
                              {2'b0, rgb888_g_d[0]} +
                              {2'b0, rgb888_b_d[0]};
            end
        end

        //------------------------------------------------------------------
        // ★ 亮度加权统计（2026-10-24，替代原来的全帧等权求和）
        //
        //   原：sum += R/G/B               （Gray World：假设整帧平均是灰）
        //   新：sum += R/G/B × lgray       （偏向亮部 ≈ White Patch）
        //
        //   lgray = (R + 2G + B) >> 4，取值 0..63
        //
        //   ★ 为什么 >>4 而不是 >>2：位宽！
        //     单个采样 R×lgray 最大 255×63 = 16065，
        //     整帧 1280*720/4=230400 次累加 -> 最大 3.7e9 < 2^32=4.29e9，32 位刚好装下。
        //     若用 >>2（lgray 0..255），累加会到 1.5e10，需要 34 位，除法器也得跟着加宽。
        //
        //   ★ 为什么加权（视频/图像通用性）
        //     Gray World 在「画面有大量偏色内容」时会被带偏（人像场景里皮肤偏红 ->
        //     整帧均值偏红 -> AWB 压 R -> 白墙变绿）。亮度加权天然偏向亮部（白墙/天花
        //     板这类中性面），实测四场景中性面色偏极差合计 17.3，优于 6x4 分块 White
        //     Patch 的 22.3，而且只是流式累加（不需要记住 24 个块），适合视频实时处理。
        //------------------------------------------------------------------
        wire [9:0] S_luma3_d0 = { 2'd0, rgb888_r_d0[0] }
                              + { 1'd0, rgb888_g_d0[0], 1'b0 }     // 2G
                              + { 2'd0, rgb888_b_d0[0] };          // 0..1020
        wire [5:0] S_lgray_d0 = S_luma3_d0[9:4];                   // >>4 -> 0..63
        wire [13:0] S_rl_d0 = rgb888_r_d0[0] * S_lgray_d0;         // 8x6 = 14 位
        wire [13:0] S_gl_d0 = rgb888_g_d0[0] * S_lgray_d0;
        wire [13:0] S_bl_d0 = rgb888_b_d0[0] * S_lgray_d0;

        //------------------------------------------------------------------
        //  ★ 排除肤色像素（2026-10-24）
        //    实测：画面里有人时白墙偏绿（对着人时绿），因为皮肤偏红把
        //    「整帧加权平均」拉红 -> AWB 压 R -> 白墙被压绿。九宫格实测
        //    中央 1.12~1.14（偏绿），而 CSC 已经把空间校平，说明锅在 AWB。
        //    判据：R 明显高于 G（+15）且饱和度高（>0.18*255≈46）-> 视为肤色，不参与统计。
        //    注意：真正偏红的光源会让「白墙」也满足这个判据 -> 若排除太多，
        //    样本会不足，所以同时统计「参与样本数」，太少时退回全帧统计。
        //------------------------------------------------------------------
        wire [7:0] S_mx_d0 = (rgb888_r_d0[0] > rgb888_g_d0[0])
                           ? ((rgb888_r_d0[0] > rgb888_b_d0[0]) ? rgb888_r_d0[0] : rgb888_b_d0[0])
                           : ((rgb888_g_d0[0] > rgb888_b_d0[0]) ? rgb888_g_d0[0] : rgb888_b_d0[0]);
        wire [7:0] S_mn_d0 = (rgb888_r_d0[0] < rgb888_g_d0[0])
                           ? ((rgb888_r_d0[0] < rgb888_b_d0[0]) ? rgb888_r_d0[0] : rgb888_b_d0[0])
                           : ((rgb888_g_d0[0] < rgb888_b_d0[0]) ? rgb888_g_d0[0] : rgb888_b_d0[0]);
        wire [7:0] S_sat_d0 = S_mx_d0 - S_mn_d0;
        // 用 9 位比较避免 R+15 溢出（R 最大 255）
        wire       S_skin_d0 = ({1'b0, rgb888_r_d0[0]} > ({1'b0, rgb888_g_d0[0]} + 9'd15)) && (S_sat_d0 > 8'd46);

        // 对每个通道的值进行累加（亮度加权），用于计算加权平均
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n || I_tuser) begin
                // 复位或帧首信号有效时，清零累加器
                sum_r[0] <= 1;
                sum_g[0] <= 1;
                sum_b[0] <= 1;
                sample_count <= 0;
            end else if (I_tvalid_r0 && (rgb_sum[0] < 720) && !S_skin_d0) begin
                // 过曝像素不参与统计（rgb_sum>=720 说明 R+G+B 接近饱和，颜色不可信）
                // 肤色像素也不参与（否则皮肤偏红会把整帧平均拉红，AWB 压 R 导致白墙发绿）
                sum_r[0] <= sum_r[0] + S_rl_d0;
                sum_g[0] <= sum_g[0] + S_gl_d0;
                sum_b[0] <= sum_b[0] + S_bl_d0;
                sample_count <= sample_count + 1'b1;
            end
        end

  /*****************************************************************
        串行除法器（2026-10-24 替换原 2 个 50 级流式除法器）
  *****************************************************************/
  // 改造说明
  //   原设计：2 个 divider IP（PIPLE=50），start=I_tvalid_r1 每拍启动，
  //           配合 96bit x 50 拍的 signal_delay 做逐像素对齐。
  //           实测这两个除法器占 u_awb 的 90%：
  //             div_gen_G_R_r1  845 lut / 1,084 ripple / 2,803 seq
  //             divide_G_B_r1   785 lut / 1,084 ripple / 2,710 seq
  //           合计约 4,700 slice。
  //   新设计：帧首锁存上一帧累加和，串行算 R、B 两个增益（各 48 拍），
  //           整帧使用同一增益。行消隐有 370 拍，96 拍足够算完；
  //           signal_delay延迟到100拍，覆盖完整计算窗口。
  //
  //   !! 商必须用移位累积（{quo[46:0], bit}），不能用 quo[cnt]<=bit 这种
  //      变量索引赋值 —— 实测综合结果不对（详见 docs/worklog.md 2026-10-24）。
  //   !! 用 S_dquo_f 组合出最后一位，因为 cnt==0 那一拍的试减结果还没进寄存器。

  reg [19:0] in_r_r1;
  reg [19:0] in_b_r1;
`ifdef RAW_PASS
  // 诊断模式：增益固定 1.0x（乘法会被综合器优化成直连，但 R_new_r1 寄存器仍在，流水拍数不变）
  wire [19:0] S_gain_r_mux = 20'h10000;
  wire [19:0] S_gain_b_mux = 20'h10000;
`else
  wire [19:0] S_gain_r_mux = in_r_r1;
  wire [19:0] S_gain_b_mux = in_b_r1;
`endif

  localparam [1:0] DIV_IDLE = 2'd0,
                   DIV_R    = 2'd1,
                   DIV_B    = 2'd2;

  reg [1:0]  S_dst;
  reg [5:0]  S_dcnt;
  reg [47:0] S_ddvd;
  reg [31:0] S_ddvs;
  reg [48:0] S_drem;
  reg [47:0] S_dquo;
  reg [31:0] S_sum_g_h;
  reg [31:0] S_sum_b_h;   // 2026-10-24: B 通道也要锁存，原来只锁了 G
  reg        S_frame_ok;
  reg [19:0] S_gain_r_hold;

  wire [48:0] S_drem_nx = {S_drem[47:0], S_ddvd[S_dcnt]};
  wire        S_dsub    = (S_drem_nx >= {17'd0, S_ddvs});
  wire [47:0] S_dquo_f  = {S_dquo[46:0], S_dsub};

  //------------------------------------------------------------------
  //  帧间平滑相关（2026-10-24，视频专用）
  //    S_gain_calc : 本轮除法结果（钳位后，再乘 R_TRIM 微调）
  //    S_smooth_*  : (3*old + new)，即 alpha=1/4 的分子部分，取 [21:2] 得到 /4
  //    S_awb_first : 冷启动标志，第一帧跳过平滑（否则上电后有 0.2s 颜色渐变）
  //
  //  ★ R_TRIM = 15/16（gain_r 再压 6.25%），2026-10-24 实测加
  //    AWB 按「整帧平均」算 gain_r，但白墙只是局部，所以压不干净：
  //      天花板场景：白墙 RAW G/R=0.845（需要 gain_r=0.845），AWB 只给 0.944
  //      人像场景：  白墙 G/R=0.934（video 实测，偏红 6.6%），同样欠压
  //    两个场景都还需要再压 6~10%，取 15/16 折中（纯移位减法，无乘法器）。
  //    若之后发现偏绿，把 R_TRIM 改回 16/16（即去掉这一行）即可。
  //------------------------------------------------------------------
  // 2026-10-24：取消 R 增益整体衰减（trim）。
  //   原因：color_shading 表已归一化（只校空间形状，平均=1.0），
  //   整体色偏完全交给 AWB，再加 trim 等于人为压低校正量，会让白墙回绿。
  //   原来挂在 KEY4 上的 trim 档位改用去控制 color_shading 的强度 k。
  // 增益限制在0.5x~2.0x。异常统计只能影响这一帧的校正量，不能把通道推到16x。
  localparam [19:0] AWB_GAIN_MIN = 20'h08000;
  localparam [19:0] AWB_GAIN_MAX = 20'h20000;
  wire [19:0] S_gain_div = (|S_dquo_f[47:20]) ? AWB_GAIN_MAX : S_dquo_f[19:0];
  wire [19:0] S_gain_calc = (S_gain_div < AWB_GAIN_MIN) ? AWB_GAIN_MIN :
                             (S_gain_div > AWB_GAIN_MAX) ? AWB_GAIN_MAX : S_gain_div;
  wire [21:0] S_smooth_r_hold = ({2'b0, in_r_r1} << 1) +
                                 {2'b0, in_r_r1} + {2'b0, S_gain_r_hold};
  wire [21:0] S_smooth_b_calc = ({2'b0, in_b_r1} << 1) +
                                {2'b0, in_b_r1} + {2'b0, S_gain_calc};
  reg         S_awb_first;

  always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          S_dst     <= DIV_IDLE;
          S_dcnt    <= 6'd47;
          S_ddvd    <= 48'd0;
          S_ddvs    <= 32'd1;
          S_drem    <= 49'd0;
          S_dquo    <= 48'd0;
          S_sum_g_h <= 32'd1;
          S_sum_b_h <= 32'd1;
          S_frame_ok <= 1'b0;
          S_gain_r_hold <= 20'h10000;
          in_r_r1   <= 20'h10000;
          in_b_r1   <= 20'h10000;
          S_awb_first <= 1'b1;
      end
      else begin
          case (S_dst)
              DIV_IDLE: begin
                  //------------------------------------------------------------------
                  // 2026-10-24 修正：触发点从「行末 I_tlast」改成「帧首 I_tuser」
                  //
                  // sum_r/g/b 是「整帧累加、帧首清零」（见上方 always 块）。
                  //   x 行末触发：用的是「到这一行为止」的部分统计 -> 帧内增益一路漂移
                  //     实测垂直方向白墙 G/R 从 1.082（顶部）漂到 1.017（底部），
                  //     表现为「上绿下中性」，也就是用户反馈的「背景变绿」。
                  //   v 帧首触发：读到的是上一帧的完整统计（非阻塞赋值，清零同拍不生效）
                  //     -> 整帧使用同一组增益，帧内均匀。
                  //
                  // 代价：增益比画面晚一帧（16.7ms），肉眼不可见。
                  //------------------------------------------------------------------
                  if (I_tuser) begin
                      S_sum_g_h <= sum_g[0];
                      S_sum_b_h <= sum_b[0];
                      S_frame_ok <= (sample_count >= AWB_MIN_SAMPLES);
                      S_ddvd    <= {sum_g[0], 16'd0};
                      S_ddvs    <= sum_r[0];
                      S_drem    <= 49'd0;
                      S_dquo    <= 48'd0;
                      S_dcnt    <= 6'd47;
                      S_dst     <= DIV_R;
                  end
              end

              DIV_R: begin
                  if (S_dsub) begin
                      S_drem <= S_drem_nx - {17'd0, S_ddvs};
                      S_dquo <= {S_dquo[46:0], 1'b1};
                  end
                  else begin
                      S_drem <= S_drem_nx;
                      S_dquo <= {S_dquo[46:0], 1'b0};
                  end

                  if (S_dcnt == 6'd0) begin
                      // 先保存R结果，等B完成后再和B一起提交，避免两路增益在一帧内混用。
                      S_gain_r_hold <= S_gain_calc;
                      S_ddvd  <= {S_sum_g_h, 16'd0};
                      S_ddvs  <= S_sum_b_h;
                      S_drem  <= 49'd0;
                      S_dquo  <= 48'd0;
                      S_dcnt  <= 6'd47;
                      S_dst   <= DIV_B;
                  end
                  else begin
                      S_dcnt <= S_dcnt - 1'b1;
                  end
              end

              DIV_B: begin
                  if (S_dsub) begin
                      S_drem <= S_drem_nx - {17'd0, S_ddvs};
                      S_dquo <= {S_dquo[46:0], 1'b1};
                  end
                  else begin
                      S_drem <= S_drem_nx;
                      S_dquo <= {S_dquo[46:0], 1'b0};
                  end

                  if (S_dcnt == 6'd0) begin
                      // 样本不足时保持上一组增益；有效帧才更新并结束冷启动状态。
                      if (S_frame_ok) begin
                          in_r_r1 <= S_awb_first ? S_gain_r_hold : S_smooth_r_hold[21:2];
                          in_b_r1 <= S_awb_first ? S_gain_calc   : S_smooth_b_calc[21:2];
                          S_awb_first <= 1'b0;
                      end
                      S_dst   <= DIV_IDLE;
                  end
                  else begin
                      S_dcnt <= S_dcnt - 1'b1;
                  end
              end

              default: S_dst <= DIV_IDLE;
          endcase
      end
  end


     
    signal_delay #(
        .IMG_HEIGHT   (IMG_HEIGHT),
        .IMG_WIDTH    (IMG_WIDTH ),
        .DATA_WIDTH   (96  ),
        // 串行除法需要约96拍；延迟覆盖完整计算窗口后，当前帧首像素不会使用旧增益。
        .DELAY_CYCLE  (100)
    )signal_delay_d (
        /*input                       */ .I_clk  (I_clk  ),
        /*input                       */ .I_rst_n(I_rst_n),
        /*input                       */ .I_tuser(I_tuser),  //synthesis keep 
        /*input  wire                 */ .I_valid(I_tvalid_r1),  //synthesis keep 
        /*input  wire [DATA_WIDTH-1:0]*/ .I_data (I_tdata_d1 ),   //synthesis keep 
        /*output wire                 */ .O_valid(valid_d0   ),  //synthesis keep 
        /*output wire [DATA_WIDTH-1:0]*/ .O_data (data_d0    ),   //synthesis keep 
        /*output wire                 */ .O_tuser(I_tuser_r0 )
    );


    ////信号同步
    always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          valid_d1 <= 0;
          data_d1  <= 0;
          I_tuser_r1 <= 0;
      end else begin
          valid_d1 <= valid_d0;
          data_d1  <= data_d0 ;
          I_tuser_r1 <= I_tuser_r0;
      end
    end
/*****************************************************************
                           ��������                                       
*****************************************************************/

    reg [27:0] R_new_r1;
    reg [27:0] G_new_r1;
    reg [27:0] B_new_r1;

    reg [27:0] R_new_r2;
    reg [27:0] G_new_r2;
    reg [27:0] B_new_r2;

    reg [27:0] R_new_r3;
    reg [27:0] G_new_r3;
    reg [27:0] B_new_r3;

    reg [27:0] R_new_r4;
    reg [27:0] G_new_r4;
    reg [27:0] B_new_r4;


    wire   [7:0] rgb888_r_d1[0:3];
    wire   [7:0] rgb888_g_d1[0:3];
    wire   [7:0] rgb888_b_d1[0:3];

    assign  rgb888_r_d1[0] = data_d1[16+:8];
    assign  rgb888_g_d1[0] = data_d1[8+:8];
    assign  rgb888_b_d1[0] = data_d1[0+:8];

    assign  rgb888_r_d1[1] = data_d1[40+:8];
    assign  rgb888_g_d1[1] = data_d1[32+:8];
    assign  rgb888_b_d1[1] = data_d1[24+:8];

    assign  rgb888_r_d1[2] = data_d1[64+:8];
    assign  rgb888_g_d1[2] = data_d1[56+:8];
    assign  rgb888_b_d1[2] = data_d1[48+:8];

    assign  rgb888_r_d1[3] = data_d1[88+:8];
    assign  rgb888_g_d1[3] = data_d1[80+:8];
    assign  rgb888_b_d1[3] = data_d1[72+:8];
    always @(posedge I_clk or negedge I_rst_n)begin 
        if(!I_rst_n)begin
            R_new_r1 <= 0;
            G_new_r1 <= 0;
            B_new_r1 <= 0;

            R_new_r2 <= 0;
            G_new_r2 <= 0;
            B_new_r2 <= 0;

            R_new_r3 <= 0;
            G_new_r3 <= 0;
            B_new_r3 <= 0;

            R_new_r4 <= 0;
            G_new_r4 <= 0;
            B_new_r4 <= 0;
        end
        else if(valid_d1) begin
            R_new_r1 <= S_gain_r_mux * rgb888_r_d1[0];
            G_new_r1 <=           rgb888_g_d1[0];
            B_new_r1 <= S_gain_b_mux * rgb888_b_d1[0];

            R_new_r2 <= S_gain_r_mux * rgb888_r_d1[1];
            G_new_r2 <=           rgb888_g_d1[1];
            B_new_r2 <= S_gain_b_mux * rgb888_b_d1[1];

            R_new_r3 <= S_gain_r_mux * rgb888_r_d1[2];
            G_new_r3 <=           rgb888_g_d1[2];
            B_new_r3 <= S_gain_b_mux * rgb888_b_d1[2];

            R_new_r4 <= S_gain_r_mux * rgb888_r_d1[3];
            G_new_r4 <=           rgb888_g_d1[3];
            B_new_r4 <= S_gain_b_mux * rgb888_b_d1[3];
        end
    end

/*****************************************************************
                            �������???                                      
*****************************************************************/

    wire [7:0] R_new_x1;
    wire [7:0] G_new_x1;
    wire [7:0] B_new_x1;

    wire [7:0] R_new_x2;
    wire [7:0] G_new_x2;
    wire [7:0] B_new_x2;

    wire [7:0] R_new_x3;
    wire [7:0] G_new_x3;
    wire [7:0] B_new_x3;

    wire [7:0] R_new_x4;
    wire [7:0] G_new_x4;
    wire [7:0] B_new_x4;

    assign R_new_x1 = (R_new_r1[27:24])?255:R_new_r1[23:16];
    assign G_new_x1 =  G_new_r1;
    assign B_new_x1 = (B_new_r1[27:24])?255:B_new_r1[23:16];

    assign R_new_x2 = (R_new_r2[27:24])?255:R_new_r2[23:16];
    assign G_new_x2 =  G_new_r2;
    assign B_new_x2 = (B_new_r2[27:24])?255:B_new_r2[23:16];

    assign R_new_x3 = (R_new_r3[27:24])?255:R_new_r3[23:16];
    assign G_new_x3 =  G_new_r3;
    assign B_new_x3 = (B_new_r3[27:24])?255:B_new_r3[23:16];

    assign R_new_x4 = (R_new_r4[27:24])?255:R_new_r4[23:16];
    assign G_new_x4 =  G_new_r4;
    assign B_new_x4 = (B_new_r4[27:24])?255:B_new_r4[23:16];
/*****************************************************************
                           ͬ���ź�                                       
*****************************************************************/

    reg valid_d2,I_tuser_r2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin
            valid_d2 <= 0;
            I_tuser_r2 <= 0;
        end
        else begin
            valid_d2 <= valid_d1;
            I_tuser_r2 <= I_tuser_r1;
        end
    end


    assign  O_tlast  = (valid_d1 == 0) && (valid_d2 == 1);   
    // video_in uses frame_start to reset its asynchronous input FIFO.
    // Keep this pulse ahead of the delayed AWB pixels so the reset has
    // completed before the first output data reaches the FIFO.
    assign  O_tuser  = I_tuser;   
    assign  O_tvalid = valid_d2;

    assign  O_tdata = O_tvalid?{R_new_x4,G_new_x4,B_new_x4,
                       R_new_x3,G_new_x3,B_new_x3,
                       R_new_x2,G_new_x2,B_new_x2,
                       R_new_x1,G_new_x1,B_new_x1}:0;
    // assign O_t_data = {R_new[7-:5],G_new[7-:6],B_new[7-:5]};
    assign  I_tready = O_tready;
 
endmodule


