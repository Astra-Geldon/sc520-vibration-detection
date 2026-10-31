// Fixed E900/G12/N1 release. KEY1/KEY2 retain colour/gray/binary/Sobel.
// Camera power-up, ISP, DDR and HDMI clocks/wiring preserve b8407f8.
// Candidate menus, diagnostic overlay, statistics tap and UART are removed.
`include "fixed_n1_lift.v"

module design_top_wrapper (
    input wire        I_sys_clk,
    input wire        I_rst_n,
      
    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
      
    inout wire [1:0]  I_button,

    // Active-low KEY1/KEY2 select image modes; KEY3/KEY4 are unused.
    input wire [3:0]  I_key,

    output wire       O_screen_pwm,
    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p,
    output wire       O_uart_tx,

    inout wire        IO_rx_clk_pad_n, 
    inout wire        IO_rx_clk_pad_p, 
    inout wire[3:0]   IO_rx_data_pad_n,
    inout wire[3:0]   IO_rx_data_pad_p,

    output wire[12:0] ddr_addr,
    output wire[ 1:0] ddr_ba,
    output wire[ 0:0] ddr_cke,
    output wire[ 0:0] ddr_odt,
    output wire[ 0:0] ddr_cs_n,
    output wire       ddr_ras_n,
    output wire       ddr_cas_n,
    output wire       ddr_we_n,
    output wire[ 0:0] ddr_ck_p,
    output wire[ 0:0] ddr_ck_n,
    inout wire[1:0]   ddr_dm,
    inout wire[15:0]  ddr_dq,
    inout wire[1:0]   ddr_dqs_p,
    inout wire[1:0]   ddr_dqs_n   
);


    wire        	S_100m_clk;
    wire        	S_24m_clk;
    wire        	S_aux_50m_clk;
	wire        	S_10m_clk;
		
	wire        	S_pll_lock;
    wire        	S_rst_n;
	reg  [17:0] 	S_cam_power_cnt;
	reg         	S_cam_pwdnb;
	reg         	S_cam_i2c_ready;
	wire [15:0] S_cam_sensor_id;
	wire        S_cam_sensor_id_ok;
	wire        S_cam_i2c_error;
	localparam integer CAM_PWDNB_LOW_CYCLES = 23810;  // >= 1 ms at 23.809524 MHz
	localparam integer CAM_I2C_START_CYCLES = 142857; // release + >= 5 ms
	
	wire [15:0] 	S_ae;
    wire [15:0] 	S_ag;
    wire 			S_cam_cfg_done;
    wire 			S_ae_cfg_done;
    wire 			S_ae_req; 

    // Strict-original baseline: retain the original FPGA sensor controller.
    // The MCU is present as a passive clock/reset-connected instance only;
    // it does not own the camera I2C pads in this baseline.
	
	wire        	S_csi_rx_clk;  
    wire        	S_hs_rx_valid;  
    wire[15:0]  	S_hs_rx_data;   
	wire[1:0]   	S_lane_error;
	
	wire        	S_csi_frame_start;       
	wire        	S_csi_frame_end;         
	wire        	S_csi_valid;             
	wire[31:0]  	S_csi_data;  
	wire [15:0] S_csi_data_length;

    // Carry frame events to the sensor-control domain without sampling a
    // narrow MIPI-domain pulse. Used only to schedule exposure/gain writes.
    reg S_cam_frame_toggle;
    reg [2:0] S_cam_frame_sync; // synthesis keep
    wire S_cam_frame_tick = S_cam_frame_sync[2] ^ S_cam_frame_sync[1];
    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_cam_frame_toggle <= 1'b0;
        else if (S_csi_frame_start) S_cam_frame_toggle <= ~S_cam_frame_toggle;
    end
    always @(posedge S_24m_clk or negedge S_cam_i2c_ready) begin
        if (!S_cam_i2c_ready) S_cam_frame_sync <= 3'b000;
        else S_cam_frame_sync <= {S_cam_frame_sync[1:0], S_cam_frame_toggle};
    end
		
	wire        	S_raw10_frame_start; 
	wire        	S_raw10_frame_end;   
	wire        	S_raw10_valid;       
	wire [39:0] 	S_raw10_data;

	wire 			S_axis_tlast;  
	wire 			S_axis_tuser;  
	wire [39:0]		S_axis_tdata;  
	wire 			S_axis_tvalid; 
	
	wire [39:0]		S_raw_tdata ;
	wire			S_raw_tlast ;
	wire 			S_raw_tvalid;
	wire 			S_raw_tuser ;
	
	wire			S_ISP_O_tready;
	wire [127:0]	S_ISP_O_tdata ;
	wire 			S_ISP_O_tlast ;
	wire 			S_ISP_O_tuser ;
	wire 			S_ISP_O_tvalid; 
	

    wire        S_ddr_clk;
    wire        S_hdmi_pixel_clk;
    wire        S_hdmi_serial_clk;
    wire        S_hdmi_rst_n;
    wire        S_video_out_rst_n;


    wire        S_vi_128b_frame_start;
    wire        S_vi_128b_valid;      
    wire[127:0] S_vi_128b_data;    
    
    wire        S_video_out_rd_busy;
    wire        S_video_in_wr_busy; 
    wire[1:0]   S_video_out_rp;     

    wire        S_ddr_user_wr_en;       
    wire        S_ddr_user_rd_en;       
    wire[24:0]  S_ddr_user_addr;        
    wire[127:0] S_ddr_user_wr_data;     
    wire        S_ddr_user_ready;       
    wire        S_ddr_user_rd_valid;    
    wire[127:0] S_ddr_user_rd_data;     

    wire        S_vi_ddr_wr_en;   
    wire[24:0]  S_vi_ddr_wr_addr; 
    wire[127:0] S_vi_ddr_wr_data;
    wire        S_vi_ddr_wr_ready;

    wire        S_vo_ddr_rd_en;   
    wire[24:0]  S_vo_ddr_rd_addr; 
    wire        S_vo_ddr_rd_ready;

    // Existing video DDR arbiter ports remain wired exactly as before.
    wire S_vo_ddr_rd_valid;
    wire [127:0] S_vo_ddr_rd_data;
    wire S_vib_ddr_wr_en, S_vib_ddr_rd_en, S_vib_ddr_want, S_vib_ddr_own;
    wire [24:0] S_vib_ddr_addr;
    wire [127:0] S_vib_ddr_wr_data;
    wire S_vib_ddr_ready, S_vib_ddr_rd_valid;
    wire [127:0] S_vib_ddr_rd_data;
    wire S_osd_vs, S_osd_de;
    wire [23:0] S_osd_data;

    wire        S_init_calib_complete; 
    wire[24:0]  S_mc_app_addr;          
    wire[2:0]   S_mc_app_cmd;           
    wire        S_mc_app_en;            
    wire[127:0] S_mc_app_wdf_data;      
    wire        S_mc_app_wdf_end;       
    wire[15:0]  S_mc_app_wdf_mask;      
    wire        S_mc_app_wdf_wren;      
    wire[127:0] S_mc_app_rd_data;       
    wire        S_mc_app_rd_data_end;   
    wire        S_mc_app_rd_data_valid; 
    wire        S_mc_app_rdy;           
    wire        S_mc_app_wdf_rdy;       

    wire        S_hdmi_vsync;
    wire        S_hdmi_hsync;
    wire        S_hdmi_de;
    wire        S_hdmi_user;
    wire        S_hdmi_last;
    wire        S_video_out_vsync;
    wire        S_hdmi_window_rd_en;
    wire        S_hdmi_out_vsync;
    wire        S_hdmi_out_hsync;
    wire        S_hdmi_out_de;
    wire[23:0]  S_hdmi_out_data;

    wire[23:0]  S_video_rd_data;

    // Original four image modes; fixed N1 is applied only to colour.
    localparam integer IMG_MODE = 0;
    wire [23:0] S_imgp_data, S_awb_data, S_csc_data, S_osd_mix;
    wire [2:0] S_img_mode;
    wire [23:0] S_lift_data, S_tone_stage_data;
    wire S_tone_stage_de, S_tone_stage_vs;
    wire [7:0] S_lift_rg_max = (S_imgp_data[23:16] > S_imgp_data[15:8]) ?
                               S_imgp_data[23:16] : S_imgp_data[15:8];
    wire [7:0] S_tone_input_peak = (S_lift_rg_max > S_imgp_data[7:0]) ?
                                  S_lift_rg_max : S_imgp_data[7:0];
    reg [7:0] S_tone_stage_peak;
    reg [2:0] S_tone_stage_mode;

    assign O_screen_pwm = 1'b1;
    assign S_video_out_vsync = ~S_hdmi_vsync;
	
	
    assign S_rst_n 		= S_pll_lock;
    // HDMI 域要等 74.25/371.25 的那颗 PLL 也锁定
    // 2026-10-24：HDMI 时钟已改由主 PLL 输出，没有第二个 PLL 了
    assign S_hdmi_rst_n = S_pll_lock;

	// J9 pin 37 is connected to the module's PWDNB/XSHUTDN input.
	// Hold the sensor in power-down after PLL lock, then allow its internal
	// power-up sequence to finish before the first I2C transaction.
	always @(posedge S_24m_clk or negedge S_pll_lock) begin
		if (!S_pll_lock) begin
			S_cam_power_cnt <= 18'd0;
			S_cam_pwdnb <= 1'b0;
			S_cam_i2c_ready <= 1'b0;
		end else begin
			if (S_cam_power_cnt < CAM_I2C_START_CYCLES)
				S_cam_power_cnt <= S_cam_power_cnt + 1'b1;
			if (S_cam_power_cnt >= CAM_PWDNB_LOW_CYCLES)
				S_cam_pwdnb <= 1'b1;
			if (S_cam_power_cnt >= CAM_I2C_START_CYCLES - 1)
				S_cam_i2c_ready <= 1'b1;
		end
	end

	assign O_cam_rst 	= S_cam_pwdnb;
    assign O_cam_24m 	= S_24m_clk;
	
	
	
	
    PLL u_PLL(
        .refclk      ( I_sys_clk         ),
        .reset    	 ( ~I_rst_n          ),
        
        .clk0_out    ( S_100m_clk        ),
        .clk1_out    ( S_24m_clk         ),

        // ★ 2026-10-24：实测 75 MHz 采集卡也能锁，于是改回「主 PLL 直接输出」
        //   75.000 / 375.000 MHz，整个 pll_hdmi_7425（两级 74.25/371.25）删除。
        //   收益：PLL 占用 5 → 3（省 2 个）。
        //   代价：刷新率 = 75M/(1650×750) = 60.606 Hz，属非标准 720p60（实测可用）。
        //   注：C1 输出是 23.809524 MHz（不是精确 24M），摄像头一直用的就是这个，
        //       偏差 -0.79%，在 SC500 的 MCLK 容差内。
        .clk4_out    ( S_hdmi_pixel_clk  ),   // 75.000 MHz 像素时钟
        .clk5_out    ( S_hdmi_serial_clk ),   // 375.000 MHz 串行时钟

        .lock        ( S_pll_lock        )

    );


	

  
  ae_set u_ae_set (
      .I_clk(S_24m_clk),
      .I_rst(~S_rst_n),
      .I_cam_cfg_done(S_cam_cfg_done),
      .I_ae_cfg_done(S_ae_cfg_done),
      .O_ae_req(S_ae_req),
      .O_ae(S_ae),
      .O_ag(S_ag)
  );
  
    uicfgcs520 #(
      .CLK_DIV(23809524 / 100000 - 1)
  ) u_uicfgcs520 (
      .I_clk(S_24m_clk),  //系统时钟输入
      .I_rst_n(S_cam_i2c_ready), // SC520CS power-up delay completed
      .I_frame_tick(S_cam_frame_tick),
      .I_ae_req(S_ae_req),
      .I_ae(S_ae),
      .I_ag(S_ag),
      .O_cam_scl(O_cam_scl),  //I2C总线，SCL时钟
      .IO_cam_sda(IO_cam_sda),  //I2C总线，SDA数据
      .O_cfg_done(S_cam_cfg_done),  //摄像头寄存器初始化完成
      .O_ae_cfg_done(S_ae_cfg_done),  //AE配置完成
      .O_sensor_id(S_cam_sensor_id),
      .O_sensor_id_ok(S_cam_sensor_id_ok),
      .O_iic_error(S_cam_i2c_error)
  );

    MCU u_mcu_passive (
        .jtag_tck(1'b0), .jtag_tms(1'b0), .jtag_tdi(1'b0), .jtag_tdo(),
        .gpio0_in(I_button[0]), .gpio0_out(), .gpio0_dir(),
        .gpio1_in(I_button[1]), .gpio1_out(), .gpio1_dir(),
        .gpio2_in(1'b0), .gpio2_out(), .gpio2_dir(),
        .gpio3_in(1'b0), .gpio3_out(), .gpio3_dir(),
        .gpio4_in(1'b0), .gpio4_out(), .gpio4_dir(),
        .gpio5_in(1'b0), .gpio5_out(), .gpio5_dir(),
        .gpio6_in(1'b0), .gpio6_out(), .gpio6_dir(),
        .gpio7_in(1'b0), .gpio7_out(), .gpio7_dir(),
        .uart0_tx(), .uart0_rx(1'b1), .uart1_tx(), .uart1_rx(1'b1),
        .i2c_sda_in(1'b1), .i2c_sda_out(), .i2c_sda_sel(),
        .i2c_scl_in(1'b1), .i2c_scl_out(), .i2c_scl_sel(),
        .qspi1_clk(), .qspi1_ss(),
        .qspi1_d0_in(1'b0), .qspi1_d1_in(1'b0), .qspi1_d2_in(1'b0), .qspi1_d3_in(1'b0),
        .qspi1_d0_out(), .qspi1_d1_out(), .qspi1_d2_out(), .qspi1_d3_out(), .qspi1_dir(),
        .ahb_clk(), .htrans(), .hwrite(), .haddr(), .hsize(), .hburst(), .hprot(), .hmastlock(),
        .hwdata(), .hrdata(32'd0), .hresp(2'b00), .hready(1'b1),
        .apb_clk(I_sys_clk), .apb_rst(~S_pll_lock), .paddr(), .psel(), .penable(), .pwrite(),
        .pwdata(), .pstrobe(), .pprot(), .prdata(32'd0), .pready(1'b1), .pslverr(1'b0),
        .core_clk(S_100m_clk), .timer_clk(S_100m_clk), .core_reset(~S_pll_lock),
        .por_reset(~S_pll_lock), .nmi(1'b0), .clic_irq(23'd0)
    );
	
    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),
        .HS_EQUALIZER          ( "3dB"   ),// 828 Mbps/Lane接收均衡
        .HS_VGA_GAIN           ( "8dB" ),//"-3dB","-1.5dB","0dB","1.5dB","3dB","4.5dB","6dB","7.5dB"
        .LANE_NUM              ( 2       ),
        .BYTE_NUM              ( 1       )
    )u_mipi_dphy_rx_ph1p_mipiio_wrapper(
        .I_lp_clk              ( S_100m_clk       ),
        .I_rst                 ( ~S_rst_n         ),

        .I_clk_lane_in_delay   ( 6'd0             ),
        .I_data_lane0_in_delay ( 6'd0             ),
        .I_data_lane1_in_delay ( 6'd0             ),
        .I_data_lane2_in_delay ( 6'd0             ),
        .I_data_lane3_in_delay ( 6'd0             ),

        .I_lane_invert         ( 4'b0000          ),
     
        .O_hs_rx_clk           ( S_csi_rx_clk     ),
        .O_hs_rx_valid         ( S_hs_rx_valid    ),
        .O_hs_rx_data          ( S_hs_rx_data     ),
      
        .O_lp_rx_lane0_p       (  ),
        .O_lp_rx_lane0_n       (  ),
      
        .I_lp_tx_en            ( 1'b0             ),
        .I_lp_tx_lane0_p       ( 1'b1             ),
        .I_lp_tx_lane0_n       ( 1'b1             ),
      
        .O_lane_match_error    (                  ),
        .O_lane_error          ( S_lane_error     ),
      
        .IO_rx_clk_pad_n       ( IO_rx_clk_pad_n  ),
        .IO_rx_clk_pad_p       ( IO_rx_clk_pad_p  ),
        .IO_rx_data_pad_n      ( IO_rx_data_pad_n ),
        .IO_rx_data_pad_p      ( IO_rx_data_pad_p )
    );
	
	
 //  cwc cwc_inst
 //(
 //    .probe0(S_hs_rx_valid),
 //    .probe1(S_hs_rx_data),
 //    .probe2(S_lane_error),
 //    .clk(S_csi_rx_clk)
 //);

 //csi 解码为RAW数据
csi_unpacket_2lane u_csi_unpacket(
.I_clk                 ( S_csi_rx_clk       ),
.I_rst_n               ( S_rst_n        	),
.I_hs_valid            ( S_hs_rx_valid     ),
.I_hs_data             ( S_hs_rx_data      ),

.O_csi_frame_start     ( S_csi_frame_start ),
.O_csi_frame_end       ( S_csi_frame_end   ),
.O_csi_valid           ( S_csi_valid       ),
.O_csi_data            ( S_csi_data        ),
.O_data_length         ( S_csi_data_length )
);


//解码为RAW8
raw10_unpacket_2lane u_raw10_unpacket (
.I_clk  (S_csi_rx_clk),
.I_rst_n(S_rst_n),

.I_csi_frame_start(S_csi_frame_start),
.I_csi_frame_end  (S_csi_frame_end),
.I_csi_valid      (S_csi_valid),
.I_csi_data       (S_csi_data),

.O_raw10_frame_start(S_raw10_frame_start),
.O_raw10_frame_end  (S_raw10_frame_end),
.O_raw10_valid      (S_raw10_valid),
.O_raw10_data       (S_raw10_data)
  );


//将数据转为stream流
uial2axis #(
.IMG_WIDTH(1280),
.IMG_HEIGHT(720),
.INPUT_DATA_WIDTH(40)
) 
u_uial2axis (
.I_native_clk(S_csi_rx_clk),
.I_rst_n     (S_rst_n),
.I_data      (S_raw10_data       ),
.I_data_valid(S_raw10_valid      ),
.I_data_start(S_raw10_frame_start),
.I_data_end  (S_raw10_frame_end  ),
.axis_tvalid (S_axis_tvalid),
.axis_tdata  (S_axis_tdata ),
.axis_tuser  (S_axis_tuser ),
.axis_tlast  (S_axis_tlast )
);
	

// SC520CS原厂HD模式已经直接输出1280x720 RAW10，无需FPGA窗口裁剪。
assign S_raw_tdata  = S_axis_tdata;
assign S_raw_tlast  = S_axis_tlast;
assign S_raw_tvalid = S_axis_tvalid;
assign S_raw_tuser  = S_axis_tuser;


//cwc1 cwc1_Inst
//  (
//      .probe0(S_axis_tuser),
//      .probe1(S_axis_tvalid),
//      .probe2(S_axis_tlast),
//      .probe3(S_axis_tdata),
//      .probe4(S_ISP_O_tuser),
//      .probe5(S_ISP_O_tvalid),
//      .probe6(S_ISP_O_tlast),
//      .probe7(S_ISP_O_tdata),
//      .probe8 (S_raw_tdata ),
//      .probe9 (S_raw_tlast ),
//      .probe10(S_raw_tvalid),
//      .probe11(S_raw_tuser ),
//      .clk(S_csi_rx_clk)
//  );


//ISP算法顶层模块
// Accepted shading strength remains k=0.75, unchanged from the comparison.
wire [1:0] S_k_sel = 2'd2;

isp_top u_isp_top (
.axi4s_video_aclk(S_csi_rx_clk),
.I_rst_n         (S_rst_n),
.I_tlast         (S_raw_tlast	),
.I_tuser         (S_raw_tuser	),
.I_tdata         (S_raw_tdata	),
.I_tvalid        (S_raw_tvalid	),
.I_tdest         (),
.O_tready        (S_ISP_O_tready),
.O_tdata         (S_ISP_O_tdata ),
.O_tlast         (S_ISP_O_tlast ),
.O_tuser         (S_ISP_O_tuser ),
.O_tvalid        (S_ISP_O_tvalid),
.I_tready        ()
  );


    video_in u_video_in(
        .I_rst_n              (  S_rst_n             ),

        .I_camera_clk         ( S_csi_rx_clk          ),
        .I_camera_frame_start ( S_ISP_O_tuser  ),
        .I_camera_valid       ( S_ISP_O_tvalid ),
        .I_camera_data        ( S_ISP_O_tdata  ),
        .I_mipi_rx_error      ( 1'b0			      ),

        .I_ddr_clk            ( S_ddr_clk             ),
		.I_display_pause      ( 1'b0                  ),
        .I_video_out_rd_busy  ( S_video_out_rd_busy   ),
        .O_video_in_wr_busy   ( S_video_in_wr_busy    ),
        .O_video_out_rp       ( S_video_out_rp        ),

        .O_ddr_user_wr_en     ( S_vi_ddr_wr_en        ),
        .O_ddr_user_addr      ( S_vi_ddr_wr_addr      ),
        .O_ddr_user_wr_data   ( S_vi_ddr_wr_data      ),
        .I_ddr_user_ready     ( S_vi_ddr_wr_ready     ),   // 改：接仲裁器门控后的 ready
        .I_vib_ddr_busy       ( S_vib_ddr_own         )    // 新增：算法正在占用 DDR
    );



    // =================================================================
    //  DDR 三路仲裁：video_in(只写) / video_out(只读) / 算法通路(读+写)
    //    原先这里只是两路简单 mux（S_ddr_user_* 由 vi/vo 直接驱动）。
    //    现在换成带"读回 tag 路由"的仲裁器 —— 因为 mc_to_user_interface 的
    //    读回数据没有标识，多一个读者就会分不清数据归谁。详见 vib_ddr_arb.v
    //    算法通路优先级最低，只在 vi/vo 都空闲时抢占，不打断它们的突发。
    // =================================================================
    vib_ddr_arb u_vib_ddr_arb (
        .clk             ( S_ddr_clk           ),
        .rst_n           ( S_rst_n             ),

        .O_ddr_wr_en     ( S_ddr_user_wr_en    ),
        .O_ddr_rd_en     ( S_ddr_user_rd_en    ),
        .O_ddr_addr      ( S_ddr_user_addr     ),
        .O_ddr_wr_data   ( S_ddr_user_wr_data  ),
        .I_ddr_ready     ( S_ddr_user_ready    ),
        .I_ddr_rd_valid  ( S_ddr_user_rd_valid ),
        .I_ddr_rd_data   ( S_ddr_user_rd_data  ),

        .I_vi_wr_en      ( S_vi_ddr_wr_en      ),
        .I_vi_addr       ( S_vi_ddr_wr_addr    ),
        .I_vi_wr_data    ( S_vi_ddr_wr_data    ),
        .O_vi_ready      ( S_vi_ddr_wr_ready   ),
        .I_vi_busy       ( S_video_in_wr_busy  ),

        .I_vo_rd_en      ( S_vo_ddr_rd_en      ),
        .I_vo_addr       ( S_vo_ddr_rd_addr    ),
        .O_vo_ready      ( S_vo_ddr_rd_ready   ),
        .I_vo_busy       ( S_video_out_rd_busy ),
        .O_vo_rd_valid   ( S_vo_ddr_rd_valid   ),
        .O_vo_rd_data    ( S_vo_ddr_rd_data    ),

        .I_vib_wr_en     ( S_vib_ddr_wr_en     ),
        .I_vib_rd_en     ( S_vib_ddr_rd_en     ),
        .I_vib_addr      ( S_vib_ddr_addr      ),
        .I_vib_wr_data   ( S_vib_ddr_wr_data   ),
        .O_vib_ready     ( S_vib_ddr_ready     ),
        .O_vib_rd_valid  ( S_vib_ddr_rd_valid  ),
        .O_vib_rd_data   ( S_vib_ddr_rd_data   ),
        .I_vib_want      ( S_vib_ddr_want      ),
        .O_vib_own       ( S_vib_ddr_own       )
    );


    assign S_video_out_rst_n = S_hdmi_rst_n;

    video_out u_video_out(
        .I_rst_n             ( S_video_out_rst_n    ),
        .I_ddr_clk           ( S_ddr_clk            ),
 
        .O_video_out_rd_busy ( S_video_out_rd_busy  ),
        .I_video_in_wr_busy  ( S_video_in_wr_busy   ),
        .I_vib_ddr_busy      ( S_vib_ddr_own        ),   // 新增：算法正在占用 DDR
        .I_video_out_rp      ( S_video_out_rp       ),
 
        .O_ddr_user_rd_en    ( S_vo_ddr_rd_en       ),
        .O_ddr_user_addr     ( S_vo_ddr_rd_addr     ),
        .I_ddr_user_ready    ( S_vo_ddr_rd_ready    ),   // 改：接仲裁器门控后的 ready
        .I_ddr_user_rd_valid ( S_vo_ddr_rd_valid    ),   // 改：经 tag 路由后的读回
        .I_ddr_user_rd_data  ( S_vo_ddr_rd_data     ),   // 改：同上

        .I_dsi_clk           ( S_hdmi_pixel_clk     ),
        .I_video_vsync       ( S_video_out_vsync    ),
        .I_video_rd_en       ( S_hdmi_window_rd_en  ),
        .O_vdieo_data        ( S_video_rd_data      )
    );



    mc_to_user_interface u_mc_to_user_interface(
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 ( S_rst_n                 ),

        .I_ddr_user_wr_en        ( S_ddr_user_wr_en        ),
        .I_ddr_user_rd_en        ( S_ddr_user_rd_en        ),
        .I_ddr_user_addr         ( S_ddr_user_addr         ),
        .I_ddr_user_wr_data      ( S_ddr_user_wr_data      ),
        .O_ddr_user_ready        ( S_ddr_user_ready        ),
        .O_ddr_user_rd_valid     ( S_ddr_user_rd_valid     ),
        .O_ddr_user_rd_data      ( S_ddr_user_rd_data      ),
            
        .O_mc_app_en             ( S_mc_app_en             ),
        .O_mc_app_addr           ( S_mc_app_addr           ),
        .O_mc_app_cmd            ( S_mc_app_cmd            ),
        .I_mc_app_rdy            ( S_mc_app_rdy            ),
        .O_mc_app_wdf_wren       ( S_mc_app_wdf_wren       ),
        .O_mc_app_wdf_data       ( S_mc_app_wdf_data       ),
        .O_mc_app_wdf_end        ( S_mc_app_wdf_end        ),
        .O_mc_app_wdf_mask       ( S_mc_app_wdf_mask       ),
        .I_mc_app_wdf_rdy        ( S_mc_app_wdf_rdy        ),
        .I_mc_app_rd_data        ( S_mc_app_rd_data        ),
        .I_mc_app_rd_data_end    ( S_mc_app_rd_data_end    ),
        .I_mc_app_rd_data_valid  ( S_mc_app_rd_data_valid  )
    );



    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper(
        .I_sys_clk              ( I_sys_clk              ),
        .I_sys_rst_n            ( S_rst_n                ),

        .O_ddr_clk              ( S_ddr_clk              ),
        .O_init_calib_complete  ( S_init_calib_complete  ),
        .I_mc_app_addr          ( S_mc_app_addr          ),
        .I_mc_app_cmd           ( S_mc_app_cmd           ),
        .I_mc_app_en            ( S_mc_app_en            ),
        .I_mc_app_wdf_data      ( S_mc_app_wdf_data      ),
        .I_mc_app_wdf_end       ( S_mc_app_wdf_end       ),
        .I_mc_app_wdf_mask      ( S_mc_app_wdf_mask      ),
        .I_mc_app_wdf_wren      ( S_mc_app_wdf_wren      ),
        .O_mc_app_rd_data       ( S_mc_app_rd_data       ),
        .O_mc_app_rd_data_end   ( S_mc_app_rd_data_end   ),
        .O_mc_app_rd_data_valid ( S_mc_app_rd_data_valid ),
        .O_mc_app_rdy           ( S_mc_app_rdy           ),
        .O_mc_app_wdf_rdy       ( S_mc_app_wdf_rdy       ),

        .ddr_addr               ( ddr_addr               ),
        .ddr_ba                 ( ddr_ba                 ),
        .ddr_cke                ( ddr_cke                ),
        .ddr_odt                ( ddr_odt                ),
        .ddr_cs_n               ( ddr_cs_n               ),
        .ddr_ras_n              ( ddr_ras_n              ),
        .ddr_cas_n              ( ddr_cas_n              ),
        .ddr_we_n               ( ddr_we_n               ),
        .ddr_ck_p               ( ddr_ck_p               ),
        .ddr_ck_n               ( ddr_ck_n               ),
        .ddr_dm                 ( ddr_dm                 ),
        .ddr_dq                 ( ddr_dq                 ),
        .ddr_dqs_p              ( ddr_dqs_p              ),
        .ddr_dqs_n              ( ddr_dqs_n              )
    );



    uivtc #(
        .H_ActiveSize ( 1280 ),
        .H_FrameSize  ( 1650 ),
        .H_SyncStart  ( 1390 ),
        .H_SyncEnd    ( 1430 ),
        .V_ActiveSize ( 720  ),
        .V_FrameSize  ( 750  ),
        .V_SyncStart  ( 725  ),
        .V_SyncEnd    ( 730  )
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    //------------------------------------------------------------------
    //  基础图像处理：video_out -> img_proc -> hdmi_mixer
    //    彩色/灰度同拍；多数滤波中心晚1行1像素，Sobel保持原有延迟；不改HDMI同步
    //------------------------------------------------------------------
    // KEY1 selects colour; KEY2 cycles gray/binary/Sobel. No parameter menu.
    img_mode_sel #(.MODE_RST(IMG_MODE), .CLK_HZ(75000000), .DB_MS(10)) u_img_mode_sel (
        .I_clk(S_hdmi_pixel_clk), .I_rst_n(S_hdmi_rst_n),
        .I_key_n(I_key[1:0]), .O_mode(S_img_mode)
    );
    assign S_awb_data = S_video_rd_data;

    color_shading u_color_shading (
        .I_clk      ( S_hdmi_pixel_clk ),
        .I_rst_n    ( S_hdmi_rst_n     ),
        .I_vs       ( S_hdmi_vsync     ),
        .I_de       ( S_hdmi_de        ),
        .I_data     ( S_awb_data       ),
        .I_k_sel   ( S_k_sel         ),
        .O_data     ( S_csc_data       )
    );

    //------------------------------------------------------------------
    //  基础图像处理：video_out -> color_shading -> img_proc
    //    灰度/Sobel固定video_out原图；二值化固定增强图像
    //    mode=0 始终显示增强后的 S_csc_data，二值化来源选择不影响彩色画面
    //                              -> osd -> hdmi_mixer
    //    彩色/灰度同拍；多数滤波中心晚1行1像素，Sobel保持原有延迟；不改HDMI同步
    //------------------------------------------------------------------
    img_proc #(
        .THRESH     ( 48       ),
        .ADAPT_EN   ( 1        ),
        .BIN_MAJORITY_EN ( 0    ),
        .TH_LOCK_EN ( 0         ),
        .GAUSSIAN_PRE_EN ( 0    ),
        .BINARY_FIXED_EN ( 1    )
    )u_img_proc(
        .I_clk      ( S_hdmi_pixel_clk ),
        .I_rst_n    ( S_hdmi_rst_n     ),
        .I_vs       ( S_hdmi_vsync     ),
        .I_de       ( S_hdmi_de        ),
        .I_mode     ( S_img_mode       ),
        .I_data     ( S_csc_data       ),
        .I_raw_data ( S_video_rd_data  ),
        .I_src_raw  ( 1'b0             ),
        .I_th_lock  ( 1'b0             ),
        .O_data     ( S_imgp_data      ),
        .O_threshold(                 ),
        .O_th_locked(                 )
    );
    //------------------------------------------------------------------
    //  OSD 叠加：右上角安路 Logo + 左上角算法名
    //    纯组合 3 选 1，数据零延迟，mixer 的 2 级对齐不受影响
    //------------------------------------------------------------------
    // Reuse the mixer's existing first pixel register; metadata aligns with it.
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_tone_stage_mode <= 3'd0;
            S_tone_stage_peak <= 8'd0;
        end else begin
            S_tone_stage_mode <= S_img_mode;
            S_tone_stage_peak <= S_tone_input_peak;
        end
    end
    fixed_n1_lift u_n1_lift (
        .I_de(S_tone_stage_de), .I_enable(S_tone_stage_mode == 3'd0),
        .I_data(S_tone_stage_data), .I_peak(S_tone_stage_peak), .O_data(S_lift_data)
    );
    osd_overlay #(
        .OSD_EN(1), .LOGO_EN(1), .H_ACTIVE(1280), .V_ACTIVE(720),
        .LOGO_W(128), .LOGO_H(80), .LOGO_X(1136), .LOGO_Y(16),
        .TEXT_X(24), .TEXT_Y(24), .BOX_PAD(8)
    )u_osd_overlay(
        .I_clk(S_hdmi_pixel_clk), .I_rst_n(S_hdmi_rst_n),
        .I_de(S_tone_stage_de), .I_vs(S_tone_stage_vs), .I_mode(S_tone_stage_mode),
        .I_data(S_lift_data), .O_data(S_osd_mix)
    );

    hdmi_mixer #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .PIXEL_STAGE_EN ( 1 )
    )u_hdmi_mixer(
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_video_vsync   ( S_hdmi_vsync       ),
        .I_video_hsync   ( S_hdmi_hsync       ),
        .I_video_de      ( S_hdmi_de          ),
        .I_video_user    ( S_hdmi_user        ),
        .I_video_last    ( S_hdmi_last        ),
        .O_video_rd_en   ( S_hdmi_window_rd_en),
        .I_video_rd_data ( S_imgp_data       ),
        .O_stage_data    ( S_tone_stage_data ),
        .O_stage_de      ( S_tone_stage_de   ),
        .O_stage_vs      ( S_tone_stage_vs   ),
        .I_stage_result  ( S_osd_mix         ),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )
    );

    assign S_vib_ddr_wr_en = 1'b0;
    assign S_vib_ddr_rd_en = 1'b0;
    assign S_vib_ddr_addr = 25'd0;
    assign S_vib_ddr_wr_data = 128'd0;
    assign S_vib_ddr_want = 1'b0;
    assign S_osd_vs = S_hdmi_out_vsync;
    assign S_osd_de = S_hdmi_out_de;
    assign S_osd_data = S_hdmi_out_data;

    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~S_hdmi_rst_n     ),
        .I_key_in           ( 1'b0              ),
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),
        .I_video_in_vs      ( S_osd_vs          ),
        .I_video_in_de      ( S_osd_de          ),
        .I_video_in_user    ( 1'b0              ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( 1'b0              ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( S_osd_data        ),
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),
        .O_tmds_clk_p       ( O_tmds_clk_p      )
    );



    // UART logging removed; keep the external TX pin at its idle level.
    assign O_uart_tx = 1'b1;
endmodule
