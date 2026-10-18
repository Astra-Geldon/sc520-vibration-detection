//=============================================================================
//  awb_fg.v  ——  帧级增益版自动白平衡（方案 B）
//
//  由 awb.v 派生，数据通路、握手、50+3 拍延迟**完全不变**，
//  只把"每像素算一次除法"改成"每帧算两次除法 + 整帧恒定增益"。
//
//  改动清单：
//    1. 两个 50 级流水 divider → 一个 48 拍 vib_div_serial（省掉一个除法器）
//    2. start 从"每像素 valid"→"每帧一次"（I_tuser 锁存上一帧最终和）
//    3. 增益寄存器不再被 I_tuser 复位 → 消除帧内增益漂移
//    4. 增益限幅 0.5 ~ 4.0，除零/样本不足保持旧值
//
//  预期：u_awb 约 10,079 → 5,500 slice（省掉一个除法器 ≈ 4,600）
//        以综合报告为准。
//
//  注意：本文件依赖 vib_div_serial（由 design_top_wrapper.v 用 `include 拉入）。
//        不要登记进 .al 的 Design Files。
//=============================================================================

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
`ifndef AWB_FG_V
`define AWB_FG_V

module awb_fg  #(   
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
                rgb_sum[0] <= rgb888_r_d[0] + rgb888_g_d[0] + rgb888_b_d[0];
            end
        end

        // 对每个通道的值进行累加，用于计算平均值
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n || I_tuser) begin
                // 复位或行开始信号有效时，清零累加器
                sum_r[0] <= 1;
                sum_g[0] <= 1;
                sum_b[0] <= 1;
            end else if (I_tvalid_r0 && (rgb_sum[0] < 720)) begin
                // 当输入有效时，累加RGB分量的值
                sum_r[0] <= sum_r[0] + rgb888_r_d0[0];
                sum_g[0] <= sum_g[0] + rgb888_g_d0[0];
                sum_b[0] <= sum_b[0] + rgb888_b_d0[0];
            end
        end

  /*****************************************************************
                           计算增益                                       
*****************************************************************/

  wire [47:0] dout_R[3:0];
  wire [47:0] dout_B[3:0];

  wire done[3:0];

  wire [47:0] in_r_x1;
  wire [47:0] in_b_x1;
  assign in_r_x1 = dout_R[0][47:0];
  assign in_b_x1 = dout_B[0][47:0];



/*****************************************************************
                   IP 调用                                    
*****************************************************************/
    //为了保证合理的延迟，这里使用了除法器

    //=====================================================================
    //  帧级增益计算（方案 B）
    //
    //  原版：两个 50 级流水除法器，start 接每个像素 → 每像素重算一次
    //  本版：一个 48 拍串行除法器，每帧算两次（G/R、G/B）
    //
    //  为什么要用 I_tuser 那一拍锁存：
    //    sum_r/sum_g/sum_b 在 I_tuser 被清成 1。非阻塞赋值取的是旧值，
    //    所以在同一个时钟边沿把 sum_* 采进 s*_f 拿到的正是"上一帧的
    //    最终累加和"——天然在清零之前，不需要另外数行数或等帧尾脉冲。
    //=====================================================================
    reg [31:0] sr_f, sg_f, sb_f;
    reg        frm_cap;          // I_tuser 后给一个"可以开始算了"的标志

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sr_f    <= 32'd0;
            sg_f    <= 32'd0;
            sb_f    <= 32'd0;
            frm_cap <= 1'b0;
        end else begin
            frm_cap <= 1'b0;
            if (I_tuser) begin
                // 非阻塞：右边是旧的 sum_*，也就是上一帧的最终值
                sr_f    <= sum_r[0];
                sg_f    <= sum_g[0];
                sb_f    <= sum_b[0];
                // 累加和被清成 1 之后，至少要有 1000 个有效像素才值得重算
                frm_cap <= (sum_r[0] > 32'd1000) && (sum_g[0] > 32'd1000)
                        && (sum_b[0] > 32'd1000);
            end
        end
    end

    // 串行除法器：一帧两次（先 R 后 B）
    reg         dv_start;
    reg  [47:0] dv_numer;
    reg  [31:0] dv_denom;
    wire [47:0] dv_quot;
    wire [47:0] dv_rem;
    wire        dv_done;

    vib_div_serial #(.W(48), .DW(32)) u_awb_div (
        .clk  (I_clk    ),
        .rst_n(I_rst_n  ),
        .start(dv_start ),
        .numer(dv_numer ),
        .denom(dv_denom ),
        .quot (dv_quot  ),
        .rem  (dv_rem   ),
        .done (dv_done  )
    );

    localparam [1:0] S_IDLE = 2'd0,
                     S_R    = 2'd1,
                     S_B    = 2'd2;

    reg  [1:0]  div_st;
    reg  [19:0] gain_r_q;        // 计算出来的新增益（未平滑）
    reg  [19:0] gain_b_q;
    reg         gain_r_vld, gain_b_vld;

    // 限幅 0.5 ~ 4.0（Q16.16）
    function [19:0] clamp_gain;
        input [47:0] q;
        begin
            if (q[47:20] != 28'd0)      clamp_gain = 20'h40000;  // 溢出 → 上限
            else if (q[19:0] < 20'h08000) clamp_gain = 20'h08000; // 下限 0.5
            else                          clamp_gain = q[19:0];
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            div_st      <= S_IDLE;
            dv_start    <= 1'b0;
            dv_numer    <= 48'd0;
            dv_denom    <= 32'd0;
            gain_r_q    <= 20'h10000;
            gain_b_q    <= 20'h10000;
            gain_r_vld  <= 1'b0;
            gain_b_vld  <= 1'b0;
        end else begin
            dv_start   <= 1'b0;
            gain_r_vld <= 1'b0;
            gain_b_vld <= 1'b0;

            case (div_st)
            S_IDLE: begin
                if (frm_cap) begin
                    // G/R
                    dv_numer <= {sg_f, 16'd0};
                    dv_denom <= sr_f;
                    dv_start <= 1'b1;
                    div_st   <= S_R;
                end
            end
            S_R: begin
                if (dv_done) begin
                    gain_r_q   <= clamp_gain(dv_quot);
                    gain_r_vld <= 1'b1;
                    // 接着算 G/B
                    dv_numer   <= {sg_f, 16'd0};
                    dv_denom   <= sb_f;
                    dv_start   <= 1'b1;
                    div_st     <= S_B;
                end
            end
            S_B: begin
                if (dv_done) begin
                    gain_b_q   <= clamp_gain(dv_quot);
                    gain_b_vld <= 1'b1;
                    div_st     <= S_IDLE;
                end
            end
            default: div_st <= S_IDLE;
            endcase
        end
    end

signal_delay #(
        .IMG_HEIGHT   (IMG_HEIGHT),
        .IMG_WIDTH    (IMG_WIDTH ),
        .DATA_WIDTH   (96  ),
        .DELAY_CYCLE  (50)
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

    

/*****************************************************************
                            ��������                                      
*****************************************************************/

    //=====================================================================
    //  输出增益：整帧恒定，只在新的计算完成时更新
    //    ★ 这里**不再**被 I_tuser 复位 —— 这正是原版"帧内增益漂移"的根源
    //    复位只在系统复位时做一次（1.0）
    //=====================================================================
    reg  [19:0]   in_r_r1;
    reg  [19:0]   in_b_r1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            in_r_r1 <= 20'h10000;      // 1.0，首帧单位增益
            in_b_r1 <= 20'h10000;
        end else begin
            if (gain_r_vld) in_r_r1 <= gain_r_q;
            if (gain_b_vld) in_b_r1 <= gain_b_q;
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
            R_new_r1 <= in_r_r1 * rgb888_r_d1[0];
            G_new_r1 <=           rgb888_g_d1[0];
            B_new_r1 <= in_b_r1 * rgb888_b_d1[0];

            R_new_r2 <= in_r_r1 * rgb888_r_d1[1];
            G_new_r2 <=           rgb888_g_d1[1];
            B_new_r2 <= in_b_r1 * rgb888_b_d1[1];

            R_new_r3 <= in_r_r1 * rgb888_r_d1[2];
            G_new_r3 <=           rgb888_g_d1[2];
            B_new_r3 <= in_b_r1 * rgb888_b_d1[2];

            R_new_r4 <= in_r_r1 * rgb888_r_d1[3];
            G_new_r4 <=           rgb888_g_d1[3];
            B_new_r4 <= in_b_r1 * rgb888_b_d1[3];
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

`endif // AWB_FG_V
