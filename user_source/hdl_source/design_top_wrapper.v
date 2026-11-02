// Five-switch demo built on the accepted E900/G12/N1 startup fix.
// KEY1/KEY2 retain colour/gray/binary/Sobel; SW6 is not connected or modified.
// Camera power-up, ISP, DDR and HDMI clocks/wiring preserve b8407f8.
// No parameter menus, statistics tap or UART; only compact applied-state OSD.
`include "fixed_n1_lift.v"
`include "demo_switch_control.v"

// Integrated vibration chain.  These modules are intentionally included here
// because the TD project registers only vib_ddr_arb.v; registering an included
// module a second time would create duplicate definitions.
`include "vib_prev_frame_ddr.v"
`include "vibration/vib_video_tap.v"
`include "vib_gauss3x3.v"
`include "vibration/vib_lk_grid_multi.v"
`include "vibration/vib_bbox_grid.v"
`include "vibration/vib_eram_dp.v"
`include "vibration/vib_gz_multi.v"
`include "vibration/vib_gz_peak.v"
`include "vibration/vib_osd_marker.v"
`include "uart_tx.v"
`include "uart_log_debug.v"

// Current backup RTL: 640x360 tap, 8x6 grid, 64-frame window, 27 bins.
// KEY3 gates the instantiated chain at run time; the image/HDMI path remains
// the main-project implementation below.
`define VIB_FRAME_DIFF_ON
`define VIB_STAGE2_LK_ON
`define VIB_STAGE2_GZ_ON

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
    // SW1 AWB, SW2 Gamma+N1, SW3 shading, SW4 demosaic, SW5 exposure.
    input wire [4:0]  I_sw,

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
    wire S_latency_write_start, S_latency_read_start;
    wire [1:0] S_latency_write_slot;
    wire [15:0] S_latency_bcd;
    wire S_latency_valid;

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

    // -----------------------------------------------------------------
    // Integrated vibration chain signals
    // -----------------------------------------------------------------
    wire        S_vib_enable_sys;
    wire        S_vib_enable_csi;
    wire        S_vib_enable_ddr;
    wire        S_vib_enable_hdmi;

    wire [31:0] S_mtr_csi_hz, S_mtr_px_per_sec, S_mtr_fps, S_mtr_px_per_frame;
    wire        S_vib_px_valid, S_vib_px_frame_start, S_vib_px_line_end;
    wire [7:0]  S_vib_px_data;
    wire [31:0] S_vib_tap_px_per_frame, S_vib_tap_px_sum, S_vib_tap_ovf;
    wire [15:0] S_vib_tap_lines;
    wire        S_vib_tap_tgl;

    wire        S_g_valid, S_g_frame_start, S_g_line_end;
    wire [7:0]  S_g_data;
    wire [31:0] S_g_px;
    wire [15:0] S_g_lines;
    wire        S_g_tgl;

    wire        S_pf_wr_en, S_pf_rd_en, S_pf_want;
    wire [24:0] S_pf_addr;
    wire [127:0] S_pf_wr_data, S_pf_rd_data;
    wire        S_pf_ready, S_pf_rd_valid, S_pf_tgl;
    wire [31:0] S_it_px, S_it_sum, S_it_err, S_it_line_rdy, S_it_state, S_it_lines;
    wire signed [31:0] S_it_sgn;
    wire        S_lk_word_valid;
    wire [127:0] S_lk_cur_w, S_lk_prev;

    wire signed [31:0] S2_axx, S2_ayy, S2_axy, S2_bx, S2_by, S2_en;
    wire [31:0] S2_px, S2_err, S2_b_itsm, S2_fx_pos;
    wire [39:0] S2_axx_exp;
    wire [4:0] S2_agc_exp;
    wire [255:0] S2_br_bx;
    wire [2:0] S2_br_row;
    wire S2_br_tick, S2_tgl, S2_solve_req, S2_fx_tick;
    wire signed [31:0] S2_fx_bx, S2_fx_by, S2_fx_en;
    wire signed [32:0] S2_fx_tex;
    wire signed [31:0] S2_fx_axx, S2_fx_ayy, S2_fx_axy;
    wire signed [31:0] S2_b_axx, S2_b_ayy, S2_b_axy;
    wire signed [31:0] S2_b_bx, S2_b_by, S2_b_en;
    wire [2:0] S2_b_bcol, S2_b_brow;
    wire [31:0] S2_dbg_unused;

    wire [7:0] S_mb_frm, S_mb_bin, S_mb_rowcnt;
    wire [5:0] S_mb_blk;
    wire [31:0] S_mb_rate, S_mb_ticks, S_mb_clrcnt;
    wire [4:0] S_mb_agc_ref;
    wire S_mb_tgl, S_mb_busy;
    wire [10:0] S_pk_addr;
    wire [63:0] S_pk_data;
    wire S_pk_done, S_pk_busy, S_pk_trig;
    wire [5:0] S_pk_ntonal, S_pk_qact, S_pk_bestblk;
    wire [31:0] S_pk_bestmag, S_pk_scancnt, S_pk_tn, S_pk_raw_hz;
    wire [4:0] S_pk_bestbin;
    wire [7:0] S_pk_hz10, S_pk_wincnt;
    wire [31:0] S_pk_bin0, S_pk_bin12, S_pk_fb2, S_pk_fb4, S_pk_fb8, S_pk_fb12;
    wire [31:0] S_pk_obj_pos, S_pk_obj_hz10;
    wire [47:0] S_pk_tonal_map;
    wire [239:0] S_pk_tonal_bins;
    wire [127:0] S_pk_obj_pn;
    wire [31:0] S_pk_fx_pn;
    wire [5:0] S_pk_fx_sel, S_pk_chal_blk;
    wire [11:0] S_pk_streak;
    wire [4:0] S_pk_aexp;
    wire [2:0] S_pk_confirmed;
    wire [7:0] S_pk_diag_qual_hz, S_pk_diag_second_hz;
    wire [31:0] S_pk_diag_qual_mag, S_pk_diag_qual_status, S_pk_diag_second_mag;
    reg S_pk_done_tgl;

    wire S_bbox_px_valid;
    wire [8:0] S_bbox_px_diff, S_bbox_px_edge;
    wire [9:0] S_bbox_px_x, S_bbox_px_y;
    wire [43:0] S_bbox_x0, S_bbox_x1;
    wire [39:0] S_bbox_y0, S_bbox_y1;
    wire [3:0] S_bbox_vld;
    wire S_bbox_tgl;
    reg [1:0] S_bbox_tgl_p;
    reg S_bbox_tgl_d;
    reg [43:0] S_bbox_x0_p2, S_bbox_x1_p2;
    reg [39:0] S_bbox_y0_p2, S_bbox_y1_p2;
    reg [3:0] S_bbox_vld_p2;
    reg [31:0] S_obj_pos_p2, S_obj_hz_p2;
    reg [1:0] S_obj_tgl_p;
    reg S_obj_tgl_d;

    // UART snapshot fields.  The source-domain values are held by the
    // vibration modules until the next frame/window; the first integration
    // keeps the diagnostic schema intact while using stable representative
    // fields for the remaining legacy entries.
    reg [31:0] c_tap_px, c_tap_lines, c_tap_sum, c_tap_ovf;
    reg [31:0] c_it_px, c_it_lines, c_it_sum, c_it_err;
    reg [31:0] c_mb_frm, c_mb_hz10, c_mb_mag, c_mb_scan, c_mb_win;
    reg [31:0] c_mb_ticks, c_mb_ntonal, c_mb_obj_pos, c_mb_obj_hz10;
    reg [31:0] c_mb_active, c_mb_agc_ref, c_mb_best_blk, c_mb_streak, c_mb_clr;
    reg [31:0] c_mb_fxbx, c_mb_fxen, c_mb_b2, c_mb_b4, c_mb_b8, c_mb_b12;
    reg [47:0] c_tonal_map;
    reg [127:0] c_obj_pn;
    reg [31:0] c_chal_blk, c_fx_pn, c_qact, c_raw_bin, c_raw_hz, c_raw_aexp;
    reg [31:0] c_confirmed, c_tn, c_motion_info;
    reg [31:0] c_diag_qual_hz, c_diag_qual_mag, c_diag_qual_status;
    reg [31:0] c_diag_second_hz, c_diag_second_mag, c_wprd;
    reg        S_vib_enable_sys_reg;
    reg [2:0]  S_key3_sync;
    reg        S_key3_stable, S_key3_last;
    reg [22:0] S_key3_debounce;
    reg [1:0]  S_vib_csi_sync, S_vib_ddr_sync, S_vib_hdmi_sync;

    assign S_vib_enable_sys = S_vib_enable_sys_reg;

    // KEY3 is an active-low, debounced toggle.  It defaults OFF so the
    // accepted image-only behavior remains available immediately after reset.
    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_key3_sync          <= 3'b111;
            S_key3_stable        <= 1'b1;
            S_key3_last          <= 1'b1;
            S_key3_debounce      <= 23'd0;
            S_vib_enable_sys_reg <= 1'b0;
        end else begin
            S_key3_sync <= {S_key3_sync[1:0], I_key[2]};
            if (S_key3_sync[2] != S_key3_stable) begin
                if (S_key3_debounce == 23'd4_999_999) begin
                    S_key3_stable   <= S_key3_sync[2];
                    S_key3_debounce <= 23'd0;
                end else begin
                    S_key3_debounce <= S_key3_debounce + 1'b1;
                end
            end else begin
                S_key3_debounce <= 23'd0;
            end
            S_key3_last <= S_key3_stable;
            if (S_key3_last && !S_key3_stable)
                S_vib_enable_sys_reg <= ~S_vib_enable_sys_reg;
        end
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_vib_csi_sync <= 2'b00;
        else         S_vib_csi_sync <= {S_vib_csi_sync[0], S_vib_enable_sys};
    end
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_vib_ddr_sync <= 2'b00;
        else         S_vib_ddr_sync <= {S_vib_ddr_sync[0], S_vib_enable_sys};
    end
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) S_vib_hdmi_sync <= 2'b00;
        else               S_vib_hdmi_sync <= {S_vib_hdmi_sync[0], S_vib_enable_sys};
    end
    assign S_vib_enable_csi  = S_vib_csi_sync[1];
    assign S_vib_enable_ddr  = S_vib_ddr_sync[1];
    assign S_vib_enable_hdmi = S_vib_hdmi_sync[1];

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
    wire [23:0] S_imgp_data, S_awb_data, S_csc_data, S_csc_corrected, S_osd_mix;
    wire [2:0] S_img_mode;
    wire [23:0] S_lift_data, S_tone_stage_data;
    wire [3:0] S_n1_extra_strength;
    wire S_tone_stage_de, S_tone_stage_vs;
    wire [23:0] S_post_stage_data, S_post_lift_data;
    wire S_post_stage_de, S_post_stage_vs;
    reg [7:0] S_post_stage_peak;
    reg [2:0] S_post_stage_mode;
    reg S_post_stage_enable;
    reg [3:0] S_post_stage_strength;
    reg [5:0] S_post_alg_state, S_post_alg_pending;
    reg [15:0] S_post_latency_bcd;
    reg S_post_latency_valid;
    wire [7:0] S_lift_rg_max = (S_imgp_data[23:16] > S_imgp_data[15:8]) ?
                               S_imgp_data[23:16] : S_imgp_data[15:8];
    wire [7:0] S_tone_input_peak = (S_lift_rg_max > S_imgp_data[7:0]) ?
                                  S_lift_rg_max : S_imgp_data[7:0];
    reg [7:0] S_tone_stage_peak;
    reg [2:0] S_tone_stage_mode;

    assign O_screen_pwm = 1'b1;
    assign S_video_out_vsync = ~S_hdmi_vsync;

    wire [4:0] S_demo_switches, S_demo_mipi, S_demo_mipi_status;
    wire [5:0] S_demo_hdmi;
    wire S_demo_switch_valid, S_demo_mipi_valid, S_demo_hdmi_valid, S_demo_mipi_status_valid;
    wire [3:0] S_demo_sensor_controls;
    wire S_demo_sensor_controls_valid;
    wire S_ae_enable_sys, S_auto_applied;
    wire [5:0] S_ae_luma, S_ae_measure_mipi, S_ae_measure_sensor;
    wire S_ae_luma_valid, S_ae_luma_fs, S_ae_measure_valid, S_ae_measure_sensor_valid;
    wire S_protect_applied, S_protect_pending, S_protect_valid;
    wire S_ae_paused = S_demo_sensor_controls[1] &&
                       (S_demo_sensor_controls[2] || S_demo_sensor_controls[3]);
    wire [3:0] S_demo_sensor_status;
    wire S_demo_sensor_status_valid;
    reg S_demo_vs_d;
    wire S_demo_frame_apply = S_hdmi_vsync && !S_demo_vs_d;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
        if (!S_hdmi_rst_n) S_demo_vs_d <= 1'b0;
        else S_demo_vs_d <= S_hdmi_vsync;

    demo_switch_debounce u_demo_switches (
        .I_clk(I_sys_clk), .I_rst_n(S_rst_n), .I_async(I_sw),
        .O_state(S_demo_switches), .O_valid(S_demo_switch_valid)
    );
    // C7 / I_key[3]: active-low K3, one toggle per debounced press.
    ae_key_toggle #(.DEFAULT_ENABLE(1'b1)) u_ae_key (
        .I_clk(I_sys_clk), .I_rst_n(S_rst_n), .I_key_n(I_key[3]),
        .O_enable(S_ae_enable_sys)
    );
    demo_control_cdc u_demo_mipi_controls (
        .I_src_clk(I_sys_clk), .I_src_rst_n(S_rst_n),
        .I_src_data(S_demo_switches), .I_src_valid(S_demo_switch_valid),
        .I_dst_clk(S_csi_rx_clk), .I_dst_rst_n(S_rst_n), .I_dst_apply(S_raw_tuser),
        .O_dst_data(S_demo_mipi), .O_dst_valid(S_demo_mipi_valid)
    );
    demo_control_cdc #(.WIDTH(6), .INITIAL(6'b111111)) u_demo_hdmi_controls (
        .I_src_clk(I_sys_clk), .I_src_rst_n(S_rst_n),
        .I_src_data({S_ae_enable_sys, S_demo_switches}), .I_src_valid(S_demo_switch_valid),
        .I_dst_clk(S_hdmi_pixel_clk), .I_dst_rst_n(S_hdmi_rst_n), .I_dst_apply(S_demo_frame_apply),
        .O_dst_data(S_demo_hdmi), .O_dst_valid(S_demo_hdmi_valid)
    );
    demo_control_cdc #(.WIDTH(4), .INITIAL(4'b0011)) u_demo_sensor_controls (
        .I_src_clk(I_sys_clk), .I_src_rst_n(S_rst_n),
        .I_src_data({~S_demo_switches[3], S_vib_enable_sys, S_ae_enable_sys, S_demo_switches[4]}),
        .I_src_valid(S_demo_switch_valid),
        .I_dst_clk(S_24m_clk), .I_dst_rst_n(S_rst_n), .I_dst_apply(1'b1),
        .O_dst_data(S_demo_sensor_controls), .O_dst_valid(S_demo_sensor_controls_valid)
    );
    // Return committed states, not the mechanical switch request, to the OSD.
    demo_control_cdc u_demo_mipi_status (
        .I_src_clk(S_csi_rx_clk), .I_src_rst_n(S_rst_n),
        .I_src_data(S_demo_mipi), .I_src_valid(S_demo_mipi_valid),
        .I_dst_clk(S_hdmi_pixel_clk), .I_dst_rst_n(S_hdmi_rst_n), .I_dst_apply(S_demo_frame_apply),
        .O_dst_data(S_demo_mipi_status), .O_dst_valid(S_demo_mipi_status_valid)
    );
    demo_control_cdc #(.WIDTH(4), .INITIAL(4'b0110)) u_demo_sensor_status (
        .I_src_clk(S_24m_clk), .I_src_rst_n(S_rst_n),
        .I_src_data({S_auto_applied, S_protect_applied, (S_protect_pending || S_ae_paused), S_protect_valid}), .I_src_valid(1'b1),
        .I_dst_clk(S_hdmi_pixel_clk), .I_dst_rst_n(S_hdmi_rst_n), .I_dst_apply(S_demo_frame_apply),
        .O_dst_data(S_demo_sensor_status), .O_dst_valid(S_demo_sensor_status_valid)
    );
    wire S_demo_raw = !S_demo_mipi_status[3];
    wire [5:0] S_demo_alg_state = {
        S_demo_mipi_status[3],
        S_demo_sensor_status[3],
        S_demo_hdmi[1] && !S_demo_raw && (S_tone_stage_mode == 0),
        S_demo_hdmi[2] && !S_demo_raw && ((S_tone_stage_mode == 0) || (S_tone_stage_mode == 2)),
        S_demo_mipi_status[1],
        S_demo_mipi_status[0] && !S_demo_raw
    };
    wire [5:0] S_demo_alg_pending = {
        !S_demo_mipi_status_valid || (S_demo_mipi_status[3] != S_demo_hdmi[3]),
        !S_demo_hdmi_valid || !S_demo_sensor_status_valid || !S_demo_sensor_status[0] || S_demo_sensor_status[1] ||
            (S_demo_sensor_status[3] != S_demo_hdmi[5]) ||
            (!S_demo_hdmi[5] && (S_demo_sensor_status[2] != S_demo_hdmi[4])),
        !S_demo_hdmi_valid || !S_demo_mipi_status_valid ||
            (S_demo_mipi_status[3:1] != S_demo_hdmi[3:1]),
        !S_demo_hdmi_valid || !S_demo_mipi_status_valid ||
            (S_demo_mipi_status[3] != S_demo_hdmi[3]),
        !S_demo_mipi_status_valid || (S_demo_mipi_status[1] != S_demo_hdmi[1]),
        !S_demo_mipi_status_valid ||
            ({S_demo_mipi_status[3], S_demo_mipi_status[0]} != {S_demo_hdmi[3], S_demo_hdmi[0]})
    };
	
	
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
      .I_protect_en(S_demo_sensor_controls[0]),
      .I_auto_en(S_demo_sensor_controls[1]),
      .I_freeze(S_demo_sensor_controls[2] || S_demo_sensor_controls[3]),
      .I_measure(S_ae_measure_sensor), .I_measure_valid(S_ae_measure_sensor_valid),
      .O_ae_req(S_ae_req),
      .O_ae(S_ae),
      .O_ag(S_ag),
      .O_protect_applied(S_protect_applied), .O_pending(S_protect_pending), .O_valid(S_protect_valid),
      .O_auto_applied(S_auto_applied)
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
.I_demosaic_en(S_demo_mipi[3]),
.I_awb_en(S_demo_mipi[0]),
.I_gamma_en(S_demo_mipi[1]),
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
.I_tready        (),
.O_ae_luma(S_ae_luma), .O_ae_valid(S_ae_luma_valid), .O_ae_frame_start(S_ae_luma_fs)
  );

    ae_luma_sampler u_ae_sampler (
        .I_clk(S_csi_rx_clk), .I_rst_n(S_rst_n),
        .I_frame_start(S_ae_luma_fs), .I_valid(S_ae_luma_valid),
        .I_luma(S_ae_luma), .I_enable(S_demo_mipi[3]),
        .O_measure(S_ae_measure_mipi), .O_valid(S_ae_measure_valid)
    );
    demo_control_cdc #(.WIDTH(6), .INITIAL(6'b000011)) u_ae_measure_cdc (
        .I_src_clk(S_csi_rx_clk), .I_src_rst_n(S_rst_n),
        .I_src_data(S_ae_measure_mipi), .I_src_valid(S_ae_measure_valid),
        .I_dst_clk(S_24m_clk), .I_dst_rst_n(S_rst_n), .I_dst_apply(1'b1),
        .O_dst_data(S_ae_measure_sensor), .O_dst_valid(S_ae_measure_sensor_valid)
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
        .O_latency_frame_start(S_latency_write_start ),
        .O_latency_frame_slot (S_latency_write_slot  ),

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
        .O_latency_frame_start(S_latency_read_start),
 
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



    // Observe the existing frame path. Nothing feeds back into DDR or pixels.
    video_latency_monitor u_video_latency (
        .I_rst_n(S_rst_n), .I_ddr_clk(S_ddr_clk),
        .I_camera_toggle(S_cam_frame_toggle),
        .I_write_start(S_latency_write_start), .I_write_slot(S_latency_write_slot),
        .I_read_start(S_latency_read_start), .I_read_slot(S_video_out_rp),
        .I_pixel_clk(S_hdmi_pixel_clk),
        .I_output_vs(S_hdmi_out_vsync), .I_output_de(S_hdmi_out_de),
        .O_bcd(S_latency_bcd), .O_valid(S_latency_valid)
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
        .O_data     ( S_csc_corrected  )
    );
    // Keep the original constant k arithmetic and DSP mapping. Switching only
    // selects the zero-latency result, rather than making k a new multiplier.
    assign S_csc_data = (S_demo_hdmi[2] && !S_demo_raw) ? S_csc_corrected : S_awb_data;

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
    adaptive_n1_control u_adaptive_n1_control (
        .I_clk(S_hdmi_pixel_clk), .I_rst_n(S_hdmi_rst_n),
        .I_vs(S_tone_stage_vs), .I_de(S_tone_stage_de),
        .I_enable((S_tone_stage_mode == 3'd0) && S_demo_hdmi[1] && !S_demo_raw),
        .I_data(S_tone_stage_data), .O_strength(S_n1_extra_strength)
    );
    // 原N1和额外补亮分别占用混合器已有的两个寄存间隔，总延迟不变。
    fixed_n1_lift u_n1_lift (
        .I_de(S_tone_stage_de), .I_enable((S_tone_stage_mode == 3'd0) && S_demo_hdmi[1] && !S_demo_raw),
        .I_data(S_tone_stage_data), .I_peak(S_tone_stage_peak),
        .I_extra_strength(4'd0), .O_data(S_lift_data)
    );
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_post_stage_peak <= 0; S_post_stage_mode <= 0;
            S_post_stage_enable <= 0; S_post_stage_strength <= 0;
            S_post_alg_state <= 0; S_post_alg_pending <= 0;
            S_post_latency_bcd <= 0; S_post_latency_valid <= 0;
        end else begin
            S_post_stage_peak <= S_tone_stage_peak;
            S_post_stage_mode <= S_tone_stage_mode;
            S_post_stage_enable <= (S_tone_stage_mode == 3'd0) && S_demo_hdmi[1] && !S_demo_raw;
            S_post_stage_strength <= S_n1_extra_strength;
            S_post_alg_state <= S_demo_alg_state;
            S_post_alg_pending <= S_demo_alg_pending;
            S_post_latency_bcd <= S_latency_bcd;
            S_post_latency_valid <= S_latency_valid;
        end
    end
    fixed_n1_extra_lift u_n1_extra_lift (
        .I_de(S_post_stage_de), .I_enable(S_post_stage_enable),
        .I_data(S_post_stage_data), .I_peak(S_post_stage_peak),
        .I_extra_strength(S_post_stage_strength), .O_data(S_post_lift_data)
    );
    osd_overlay #(
        .OSD_EN(1), .LOGO_EN(1), .H_ACTIVE(1280), .V_ACTIVE(720),
        .LOGO_W(128), .LOGO_H(80), .LOGO_X(1136), .LOGO_Y(16),
        .TEXT_X(24), .TEXT_Y(24), .BOX_PAD(8)
    )u_osd_overlay(
        .I_clk(S_hdmi_pixel_clk), .I_rst_n(S_hdmi_rst_n),
        .I_de(S_post_stage_de), .I_vs(S_post_stage_vs), .I_mode(S_post_stage_mode),
        .I_latency_bcd(S_post_latency_bcd), .I_latency_valid(S_post_latency_valid),
        .I_alg_state(S_post_alg_state), .I_alg_pending(S_post_alg_pending),
        .I_data(S_post_lift_data), .O_data(S_osd_mix)
    );

    hdmi_mixer #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .PIXEL_STAGE_EN ( 1 ),
        .POST_STAGE_EN ( 1 )
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
        .I_stage_result  ( S_lift_data       ),
        .O_post_stage_data ( S_post_stage_data ),
        .O_post_stage_de ( S_post_stage_de   ),
        .O_post_stage_vs ( S_post_stage_vs   ),
        .I_post_stage_result ( S_osd_mix     ),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )
    );

    // -----------------------------------------------------------------
    // Vibration path from the backup branch.  The tap is passive: it sees
    // the ISP stream but has no ready/feedback path into the display chain.
    // Every algorithm stage is held in reset while KEY3 is OFF.
    // -----------------------------------------------------------------
    vib_video_tap u_vib_video_tap (
        .clk            ( S_csi_rx_clk          ),
        .rst_n          ( S_rst_n & S_vib_enable_csi ),
        .in_valid       ( S_ISP_O_tvalid & S_vib_enable_csi ),
        .in_data        ( S_ISP_O_tdata           ),
        .in_frame_start ( S_ISP_O_tuser & S_vib_enable_csi ),
        .in_line_end    ( S_ISP_O_tlast           ),
        .px_valid       ( S_vib_px_valid          ),
        .px_data        ( S_vib_px_data           ),
        .px_frame_start ( S_vib_px_frame_start    ),
        .px_line_end    ( S_vib_px_line_end       ),
        .st_frame_px    ( S_vib_tap_px_per_frame  ),
        .st_frame_ln    ( S_vib_tap_lines         ),
        .st_px_sum      ( S_vib_tap_px_sum        ),
        .st_ovf         ( S_vib_tap_ovf            ),
        .st_tgl         ( S_vib_tap_tgl            )
    );

    vib_gauss3x3 u_vib_gauss3x3 (
        .clk            ( S_csi_rx_clk          ),
        .rst_n          ( S_rst_n & S_vib_enable_csi ),
        .px_valid       ( S_vib_px_valid         ),
        .px_data        ( S_vib_px_data          ),
        .px_frame_start ( S_vib_px_frame_start   ),
        .px_line_end    ( S_vib_px_line_end      ),
        .g_valid        ( S_g_valid              ),
        .g_data         ( S_g_data               ),
        .g_frame_start  ( S_g_frame_start        ),
        .g_line_end     ( S_g_line_end           ),
        .st_g_px        ( S_g_px                 ),
        .st_g_lines     ( S_g_lines              ),
        .st_tgl         ( S_g_tgl                )
    );

    vib_prev_frame_ddr u_vib_prev_frame_ddr (
        .csi_clk        ( S_csi_rx_clk          ),
        .csi_rst_n      ( S_rst_n & S_vib_enable_csi ),
        .px_valid       ( S_g_valid              ),
        .px_data        ( S_g_data               ),
        .px_frame_start ( S_g_frame_start        ),
        .px_line_end    ( S_g_line_end           ),
        .clk            ( S_ddr_clk              ),
        .rst_n          ( S_rst_n & S_vib_enable_ddr ),
        .O_wr_en        ( S_pf_wr_en             ),
        .O_rd_en        ( S_pf_rd_en             ),
        .O_addr         ( S_pf_addr              ),
        .O_wr_data      ( S_pf_wr_data           ),
        .I_ready        ( S_pf_ready             ),
        .I_rd_valid     ( S_pf_rd_valid          ),
        .I_rd_data      ( S_pf_rd_data           ),
        .O_want         ( S_pf_want              ),
        .st_it_px       ( S_it_px                ),
        .st_it_sum      ( S_it_sum               ),
        .st_it_sgn      ( S_it_sgn               ),
        .st_lines       ( S_it_lines             ),
        .st_err         ( S_it_err               ),
        .st_line_rdy    ( S_it_line_rdy          ),
        .st_state       ( S_it_state             ),
        .st_tgl         ( S_pf_tgl               ),
        .lk_word_valid  ( S_lk_word_valid        ),
        .lk_cur_w       ( S_lk_cur_w             ),
        .lk_prev_w      ( S_lk_prev               )
    );

    (* keep_hierarchy = "yes" *) vib_lk_grid_multi u_vib_lk_grid_multi (
        .clk            ( S_ddr_clk              ),
        .rst_n          ( S_rst_n & S_vib_enable_ddr ),
        .word_valid     ( S_lk_word_valid        ),
        .word_cur       ( S_lk_cur_w             ),
        .word_prev      ( S_lk_prev              ),
        .st_axx         ( S2_axx                 ),
        .st_ayy         ( S2_ayy                 ),
        .st_axy         ( S2_axy                 ),
        .st_bx          ( S2_bx                  ),
        .st_by          ( S2_by                  ),
        .st_en          ( S2_en                  ),
        .st_px          ( S2_px                  ),
        .st_err         ( S2_err                 ),
        .st_tgl         ( S2_tgl                 ),
        .st_b_itsm      ( S2_b_itsm              ),
        .i_it_sum       ( S_it_sum               ),
        .st_br_bx       ( S2_br_bx               ),
        .st_br_row      ( S2_br_row              ),
        .st_br_tick     ( S2_br_tick             ),
        .st_fx_pos      ( S2_fx_pos              ),
        .st_fx_bx       ( S2_fx_bx               ),
        .st_fx_by       ( S2_fx_by               ),
        .st_fx_en       ( S2_fx_en               ),
        .st_fx_tex      ( S2_fx_tex              ),
        .st_fx_axx      ( S2_fx_axx              ),
        .st_fx_ayy      ( S2_fx_ayy              ),
        .st_fx_axy      ( S2_fx_axy              ),
        .st_fx_tick     ( S2_fx_tick             ),
        .st_b_axx       ( S2_b_axx               ),
        .st_b_ayy       ( S2_b_ayy               ),
        .st_b_axy       ( S2_b_axy               ),
        .st_b_bx        ( S2_b_bx                ),
        .st_b_by        ( S2_b_by                ),
        .st_b_en        ( S2_b_en                ),
        .st_b_bcol      ( S2_b_bcol              ),
        .st_b_brow      ( S2_b_brow              ),
        .st_solve_req   ( S2_solve_req           ),
        .st_solve_ack   ( 1'b0                   ),
        .o_px_valid     ( S_bbox_px_valid        ),
        .o_px_it        ( S_bbox_px_diff         ),
        .o_px_edge      ( S_bbox_px_edge         ),
        .o_px_x         ( S_bbox_px_x             ),
        .o_px_y         ( S_bbox_px_y             ),
        .o_axx_exp      ( S2_axx_exp             ),
        .o_agc_exp      ( S2_agc_exp             )
    );

    vib_gz_multi #(.NFRM(64), .NBIN(27), .NROW(6), .NCOL(8)) u_vib_gz_multi (
        .clk         ( S_ddr_clk       ),
        .rst_n       ( S_rst_n & S_vib_enable_ddr ),
        .i_bx8       ( S2_br_bx        ),
        .i_agc_exp   ( S2_agc_exp      ),
        .i_row       ( S2_br_row       ),
        .i_tick      ( S2_br_tick      ),
        .o_frm       ( S_mb_frm        ),
        .o_frm_tgl   ( S_mb_tgl        ),
        .o_busy      ( S_mb_busy       ),
        .o_dbg_blk   ( S_mb_blk        ),
        .o_dbg_bin   ( S_mb_bin        ),
        .o_dbg_rate  ( S_mb_rate       ),
        .o_dbg_rowcnt( S_mb_rowcnt     ),
        .o_tick_cnt  ( S_mb_ticks      ),
        .i_pk_done   ( S_pk_done       ),
        .o_clr_cnt   ( S_mb_clrcnt     ),
        .o_dbg_agc_ref( S_mb_agc_ref   ),
        .pk_b_addr   ( S_pk_addr       ),
        .pk_b_data   ( S_pk_data       )
    );

    reg [1:0] S_mb_tgl_s;
    wire S_mb_tgl_p = S_mb_tgl_s[1] ^ S_mb_tgl_s[0];
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if (!S_rst_n) begin
            S_mb_tgl_s   <= 2'b00;
            S_pk_done_tgl <= 1'b0;
        end else begin
            S_mb_tgl_s <= {S_mb_tgl_s[0], S_mb_tgl};
            if (!S_vib_enable_ddr) S_pk_done_tgl <= 1'b0;
            else if (S_pk_done) S_pk_done_tgl <= ~S_pk_done_tgl;
        end
    end
    assign S_pk_trig = S_mb_tgl_p & ~S_pk_busy;

    vib_gz_peak #(.NBIN(27), .NB(48), .BIN_MIN(0), .TONE_RATIO(0), .COMMON_MOTION_ON(0)) u_vib_gz_peak (
        .clk        ( S_ddr_clk       ),
        .rst_n      ( S_rst_n & S_vib_enable_ddr ),
        .trig       ( S_pk_trig       ),
        .i_motion_veto( 1'b0          ),
        .i_fx_blk   ( S2_fx_pos[5:0]  ),
        .i_axx_exp  ( S2_axx_exp      ),
        .i_tick     ( S2_br_tick      ),
        .i_row      ( S2_br_row       ),
        .st_addr    ( S_pk_addr       ),
        .st_data    ( S_pk_data       ),
        .busy       ( S_pk_busy       ),
        .done       ( S_pk_done       ),
        .o_ntonal   ( S_pk_ntonal     ),
        .o_qact     ( S_pk_qact       ),
        .o_best_blk ( S_pk_bestblk    ),
        .o_best_mag ( S_pk_bestmag    ),
        .o_best_bin ( S_pk_bestbin    ),
        .o_best_hz10( S_pk_hz10       ),
        .o_mb_bin0  ( S_pk_bin0       ),
        .o_mb_b12   ( S_pk_bin12      ),
        .o_fb2       ( S_pk_fb2       ),
        .o_fb4       ( S_pk_fb4       ),
        .o_fb8       ( S_pk_fb8       ),
        .o_fb12      ( S_pk_fb12      ),
        .o_tn        ( S_pk_tn        ),
        .o_raw_hz    ( S_pk_raw_hz    ),
        .o_trk_pos   (                ),
        .o_bb_x0     (                ),
        .o_bb_y0     (                ),
        .o_bb_x1     (                ),
        .o_bb_y1     (                ),
        .o_bb_vld    (                ),
        .o_obj_pos   ( S_pk_obj_pos   ),
        .o_obj_hz10  ( S_pk_obj_hz10  ),
        .o_tonal_map ( S_pk_tonal_map ),
        .o_tonal_bins( S_pk_tonal_bins),
        .o_obj_pn    ( S_pk_obj_pn    ),
        .o_fx_pn     ( S_pk_fx_pn     ),
        .o_scan_cnt  ( S_pk_scancnt   ),
        .o_win_cnt   ( S_pk_wincnt    ),
        .o_dbg_fx_sel( S_pk_fx_sel    ),
        .o_dbg_chal_blk( S_pk_chal_blk ),
        .o_dbg_streak( S_pk_streak    ),
        .o_dbg_aexp  ( S_pk_aexp      ),
        .o_confirmed ( S_pk_confirmed ),
        .o_dbg_qual_hz10 ( S_pk_diag_qual_hz ),
        .o_dbg_qual_mag  ( S_pk_diag_qual_mag ),
        .o_dbg_qual_status( S_pk_diag_qual_status ),
        .o_dbg_second_hz10( S_pk_diag_second_hz ),
        .o_dbg_second_mag( S_pk_diag_second_mag )
    );

    vib_bbox_grid u_vib_bbox_grid (
        .clk        ( S_ddr_clk       ),
        .rst_n      ( S_rst_n & S_vib_enable_ddr ),
        .i_px_valid ( S_bbox_px_valid ),
        .i_px_diff  ( S_bbox_px_diff  ),
        .i_px_edge  ( S_bbox_px_edge  ),
        .i_px_x     ( S_bbox_px_x     ),
        .i_px_y     ( S_bbox_px_y     ),
        .i_obj_pos  ( S_pk_obj_pos    ),
        .i_tonal_map( S_pk_tonal_map  ),
        .i_tonal_bins( S_pk_tonal_bins ),
        .o_x0       ( S_bbox_x0       ),
        .o_y0       ( S_bbox_y0       ),
        .o_x1       ( S_bbox_x1       ),
        .o_y1       ( S_bbox_y1       ),
        .o_vld      ( S_bbox_vld      ),
        .o_tgl      ( S_bbox_tgl      )
    );

    assign S_pf_ready    = S_vib_ddr_ready & S_vib_enable_ddr;
    assign S_pf_rd_valid = S_vib_ddr_rd_valid & S_vib_enable_ddr;
    assign S_pf_rd_data  = S_vib_ddr_rd_data;
    assign S_vib_ddr_wr_en   = S_pf_wr_en & S_vib_enable_ddr;
    assign S_vib_ddr_rd_en   = S_pf_rd_en & S_vib_enable_ddr;
    assign S_vib_ddr_addr    = S_pf_addr;
    assign S_vib_ddr_wr_data = S_pf_wr_data;
    assign S_vib_ddr_want    = S_pf_want & S_vib_enable_ddr;

    // CDC of the stable bounding-box/result buses into the HDMI domain.
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_obj_pos_p2 <= 32'd0;
            S_obj_hz_p2  <= 32'd0;
            S_obj_tgl_p  <= 2'b00;
            S_obj_tgl_d  <= 1'b0;
            S_bbox_tgl_p <= 2'b00;
            S_bbox_tgl_d <= 1'b0;
            S_bbox_x0_p2 <= 44'd0; S_bbox_x1_p2 <= 44'd0;
            S_bbox_y0_p2 <= 40'd0; S_bbox_y1_p2 <= 40'd0;
            S_bbox_vld_p2 <= 4'd0;
        end else begin
            S_obj_tgl_p <= {S_obj_tgl_p[0], S_pk_done_tgl};
            S_obj_tgl_d <= S_obj_tgl_p[1];
            if (S_obj_tgl_p[1] != S_obj_tgl_d) begin
                S_obj_pos_p2 <= S_pk_obj_pos;
                S_obj_hz_p2  <= S_pk_obj_hz10;
            end
            S_bbox_tgl_p <= {S_bbox_tgl_p[0], S_bbox_tgl};
            S_bbox_tgl_d <= S_bbox_tgl_p[1];
            if (S_bbox_tgl_p[1] != S_bbox_tgl_d) begin
                S_bbox_x0_p2 <= S_bbox_x0; S_bbox_x1_p2 <= S_bbox_x1;
                S_bbox_y0_p2 <= S_bbox_y0; S_bbox_y1_p2 <= S_bbox_y1;
                S_bbox_vld_p2 <= S_bbox_vld;
            end
        end
    end

    wire S_vib_marker_vs, S_vib_marker_de;
    wire [23:0] S_vib_marker_data;
    vib_osd_marker u_vib_osd_marker (
        .clk       ( S_hdmi_pixel_clk ),
        .rst_n     ( S_hdmi_rst_n & S_vib_enable_hdmi ),
        .I_vs      ( S_hdmi_out_vsync ),
        .I_de      ( S_hdmi_out_de    ),
        .I_data    ( S_hdmi_out_data  ),
        .I_obj_pos ( S_obj_pos_p2     ),
        .I_obj_hz10( S_obj_hz_p2      ),
        .I_bbox_x0 ( S_bbox_x0_p2     ),
        .I_bbox_y0 ( S_bbox_y0_p2     ),
        .I_bbox_x1 ( S_bbox_x1_p2     ),
        .I_bbox_y1 ( S_bbox_y1_p2     ),
        .I_bbox_vld( S_bbox_vld_p2    ),
        .O_vs      ( S_vib_marker_vs  ),
        .O_de      ( S_vib_marker_de  ),
        .O_data    ( S_vib_marker_data )
    );
    assign S_osd_vs   = S_vib_enable_hdmi ? S_vib_marker_vs  : S_hdmi_out_vsync;
    assign S_osd_de   = S_vib_enable_hdmi ? S_vib_marker_de  : S_hdmi_out_de;
    assign S_osd_data = S_vib_enable_hdmi ? S_vib_marker_data : S_hdmi_out_data;

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



    // UART diagnostic snapshot.  The fields are sampled in the existing
    // 50 MHz system-clock domain and retain the backup branch's 115200 8N1
    // format.  This stage has no influence on the HDMI or DDR arbitration.
    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            c_tap_px <= 0; c_tap_lines <= 0; c_tap_sum <= 0; c_tap_ovf <= 0;
            c_it_px <= 0; c_it_lines <= 0; c_it_sum <= 0; c_it_err <= 0;
            c_mb_frm <= 0; c_mb_hz10 <= 0; c_mb_mag <= 0; c_mb_scan <= 0;
            c_mb_win <= 0; c_mb_ticks <= 0; c_mb_ntonal <= 0;
            c_mb_obj_pos <= 0; c_mb_obj_hz10 <= 0; c_mb_active <= 0;
            c_mb_agc_ref <= 0; c_mb_best_blk <= 0; c_mb_streak <= 0; c_mb_clr <= 0;
            c_mb_fxbx <= 0; c_mb_fxen <= 0; c_mb_b2 <= 0; c_mb_b4 <= 0;
            c_mb_b8 <= 0; c_mb_b12 <= 0; c_tonal_map <= 0; c_obj_pn <= 0;
            c_chal_blk <= 0; c_fx_pn <= 0; c_qact <= 0; c_raw_bin <= 0;
            c_raw_hz <= 0; c_raw_aexp <= 0; c_confirmed <= 0; c_tn <= 0;
            c_motion_info <= 0; c_diag_qual_hz <= 0; c_diag_qual_mag <= 0;
            c_diag_qual_status <= 0; c_diag_second_hz <= 0; c_diag_second_mag <= 0;
            c_wprd <= 0;
        end else begin
            c_tap_px <= S_vib_tap_px_per_frame;
            c_tap_lines <= {16'd0, S_vib_tap_lines};
            c_tap_sum <= S_vib_tap_px_sum;
            c_tap_ovf <= S_vib_tap_ovf;
            c_it_px <= S_it_px; c_it_lines <= S_it_lines;
            c_it_sum <= S_it_sum; c_it_err <= S_it_err;
            c_mb_frm <= {24'd0, S_mb_frm};
            c_mb_hz10 <= {24'd0, S_pk_hz10};
            c_mb_mag <= S_pk_bestmag;
            c_mb_scan <= S_pk_scancnt;
            c_mb_win <= {24'd0, S_pk_wincnt};
            c_mb_ticks <= S_mb_ticks;
            c_mb_ntonal <= {26'd0, S_pk_ntonal};
            c_mb_obj_pos <= S_pk_obj_pos;
            c_mb_obj_hz10 <= S_pk_obj_hz10;
            c_mb_active <= {26'd0, S_pk_ntonal};
            c_mb_agc_ref <= {27'd0, S_mb_agc_ref};
            c_mb_best_blk <= {26'd0, S_pk_bestblk};
            c_mb_streak <= {20'd0, S_pk_streak};
            c_mb_clr <= S_mb_clrcnt;
            c_mb_fxbx <= 0; c_mb_fxen <= 0;
            c_mb_b2 <= S_pk_fb2; c_mb_b4 <= S_pk_fb4;
            c_mb_b8 <= S_pk_fb8; c_mb_b12 <= S_pk_fb12;
            c_tonal_map <= S_pk_tonal_map; c_obj_pn <= S_pk_obj_pn;
            c_chal_blk <= {26'd0, S_pk_chal_blk}; c_fx_pn <= S_pk_fx_pn;
            c_qact <= {26'd0, S_pk_qact}; c_raw_bin <= {27'd0, S_pk_bestbin};
            c_raw_hz <= S_pk_raw_hz; c_raw_aexp <= {27'd0, S_pk_aexp};
            c_confirmed <= {29'd0, S_pk_confirmed}; c_tn <= S_pk_tn;
            c_motion_info <= 0;
            c_diag_qual_hz <= {24'd0, S_pk_diag_qual_hz};
            c_diag_qual_mag <= S_pk_diag_qual_mag;
            c_diag_qual_status <= S_pk_diag_qual_status;
            c_diag_second_hz <= {24'd0, S_pk_diag_second_hz};
            c_diag_second_mag <= S_pk_diag_second_mag;
        end
    end

    uart_log_debug #(.CLK_HZ(50_000_000), .BAUD(115200)) u_uart_log_debug (
        .clk(I_sys_clk), .rst_n(I_rst_n), .pll_lock(S_pll_lock),
        .ddr_init_done(S_init_calib_complete), .cam_cfg_done(S_cam_cfg_done),
        .cam_i2c_error(S_cam_i2c_error), .sensor_id(S_cam_sensor_id),
        .sensor_id_ok(S_cam_sensor_id_ok), .mipi_diag_status(4'd0),
        .hs_seen(S_hs_rx_valid), .csi_frame_seen(S_csi_frame_start),
        .raw10_seen(S_raw10_valid),
        .video_nonzero_seen(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0)),
        .tap_px_per_frame(c_tap_px), .tap_lines(c_tap_lines),
        .it_px(c_it_px), .it_lines(c_it_lines), .vsum(c_tap_sum),
        .mb_frm(c_mb_frm), .mb_active(c_mb_active), .mb_obj_hz10(c_mb_obj_hz10),
        .mb_agc_ref(c_mb_agc_ref), .mb_best_blk(c_mb_best_blk),
        .mb_streak(c_mb_streak), .mb_clr(c_mb_clr), .mb_mag(c_mb_mag),
        .fx_bx(c_mb_fxbx), .fx_en(c_mb_fxen), .b2(c_mb_b2), .b4(c_mb_b4),
        .b8(c_mb_b8), .b12(c_mb_b12),
        .tonal_map_lo(c_tonal_map[31:0]),
        .tonal_map_hi({16'd0, c_tonal_map[47:32]}),
        .obj_pos(c_mb_obj_pos), .fx_pn(c_fx_pn),
        .obj_pn0(c_obj_pn[31:0]), .obj_pn1(c_obj_pn[63:32]),
        .obj_pn2(c_obj_pn[95:64]), .obj_pn3(c_obj_pn[127:96]),
        .chal_blk(c_chal_blk), .qact(c_qact), .wprd(c_wprd),
        .tap_ovf(c_tap_ovf), .it_err(c_it_err), .mb_scan(c_mb_scan),
        .mb_win(c_mb_win), .raw_bin(c_raw_bin), .raw_hz(c_raw_hz),
        .raw_aexp(c_raw_aexp), .confirmed(c_confirmed), .tn_status(c_tn),
        .motion_info(c_motion_info), .diag_qual_hz(c_diag_qual_hz),
        .diag_qual_mag(c_diag_qual_mag), .diag_qual_status(c_diag_qual_status),
        .diag_second_hz(c_diag_second_hz), .diag_second_mag(c_diag_second_mag),
        .tx(O_uart_tx)
    );
endmodule
