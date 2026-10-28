

// 振动算法通路：上一帧灰度缓存 + 帧差 It
// 振动算法通路的模块来源说明（★ 很重要，重复定义会整个编译失败）
//
//   vib_gauss3x3.v  ─┐
//   vib_lk_grid.v   ─┴─ 已经登记在 TD 的 Design Files 里（.al 中有条目）
//                       -> **不能再 `include**，否则同一模块被编译两次
//                          报重复定义，编译不生效（会继续跑旧比特流）
//
//   vib_prev_frame_ddr.v 还没有登记在 .al 里
//                       -> 仍然用 `include 拉进来
//                       （老工程也是这个套路：`include "vibration_uart_debug.v"）
//                       ★ 如果 TD 报 "cannot open include file"，就把它也加到
//                         Design Files 里，然后把下面这一行 include 删掉。
`include "vib_prev_frame_ddr.v"

// 串行除法器（48/32，恒 48 拍，约 150 FF）。
// **不要**登记到 TD 的 Design Files 里 —— 登记了又 include 会造成
// 模块重复定义、编译不生效（会继续跑旧比特流）。
`include "vibration/vib_div_serial.v"

// 振动频率识别（17 频点 Goertzel，128 帧窗口）。同样**不要**登记进 .al。
`include "vibration/vib_goertzel.v"

// Shared 48-block, 17-bin vibration chain. Each module is included once.
`include "vibration/vib_lk_grid_multi.v"
`include "vibration/vib_eram_dp.v"
`include "vibration/vib_gz_multi.v"
`include "vibration/vib_gz_peak.v"

// 屏幕调试标记（固定块外框 + 左上角 L 形参考标记）。同样不要登记进 .al。
`include "vibration/vib_osd_marker.v"

// 阶段 0 探针：48x17 状态阵列 + 上电自检（验证能不能被综合成 RAM）
`include "vibration/vib_gz_store.v"

// =====================================================================
//  调试开关：注释掉下面这一行即可恢复 HDMI 显示（一行都不用改别的）。
//
//  打开时 video_out / hdmi_mixer / hdmi_tx 都不例化，它们原本驱动的
//  信号全部显式接地，所以：
//    - DDR 仲裁器的 VO 通道收到 rd_en=0 / addr=0，握手不会异常
//    - 顶层 TMDS 差分输出被驱动到 0，不会报"输出未驱动"
//    - ISP、AWB、DDR 写入、振动算法、串口日志完全不受影响
// =====================================================================
// =====================================================================
//  ★★ VIB_NO_DISPLAY 已停用（2026-10-17 晚）
//
//  实测后果（很重要，别再犯）：
//    去掉 video_out 之后，DDR 仲裁里 video_in 失去了唯一的竞争者，
//    它每行都占满 DDR，算法端等不到 ~I_vi_busy 的空档，
//    于是 vib_prev_frame_ddr 读不出上一帧：
//        VSUM != 0（抽头正常，Σ灰度均值 93）
//        ITPX = 0, ITSM = 0, LKPX = 0（B2b 拿不到数据）
//        ITER = 2 恒定（B2b 状态机在跑，但没数据）
//    "关掉显示省资源"看似只影响显示，实际改变了 DDR 的仲裁平衡。
//
//  如果以后确实要关显示省资源，必须同时处理仲裁：
//    要么保留 video_out 但让它的读请求永不发起（busy 仍按原逻辑翻转），
//    要么改 vib_ddr_arb 给算法一个最低带宽保证。
// =====================================================================
// =====================================================================
//  ★★ 振动算法总开关（2026-10-18）★★
//  去掉下行注释 = 打开整条振动链路；保持注释 = 关闭（省约 12,400 slice）
// =====================================================================
//`define VIB_ON

// Enable the shared multi-block chain; keep the legacy single-block chain off.
`define VIB_FRAME_DIFF_ON
`define VIB_STAGE2_LK_ON
`define VIB_STAGE2_GZ_ON

//`define VIB_NO_DISPLAY

// =====================================================================
//  ★★ 图像处理"按键实时切换"开关（2026-10-23）★★
//
//  打开（默认）= 用板载 4 个按键 KEY1~KEY4 选择（按下=低）：
//        SW3 拨上 → 强制原图    SW2 拨上 → 二值化
//        KEY1=增强彩色 KEY2=算法循环 KEY3=释放 KEY4=释放
//  注释掉      = 回到编译期固定模式（用下面的 IMG_MODE），资源可回到只综合一种
//
//  ★ 与队友功能的分隔：本开关只影响两个地方 ——
//      · img_proc 的 I_mode（显示通路上最后一个纯组合选择）
//      · 新增 4 个顶层输入 I_key[3:0]（KEY1~KEY4 = D5/A9/B9/C7，按下=0）
//    不发散：I_button（ae_set 的曝光按键）、I_button 原引脚、ISP/AWB、
//    振动链路、HDMI 发射核 一行都没动。
//    （注：手册核对后 I_button 现在的 N2/J14 并不是板载按键，属历史遗留；
//      为了不影响 ae_set，这里原样保留，另开 I_key 端口。）
// =====================================================================
`define IMG_MODE_KEY

// =====================================================================
//  ★★ OSD 叠加开关（2026-10-23，基础要求 2.3(4)）★★
//
//  OSD_ON       = 打开 OSD（右上角安路 Logo + 左上角算法名）
//  OSD_LOGO_ROM = Logo 走 EG_LOGIC_BRAM + osd_logo.mif（厂商 rom_bmp.v 同款）
//                 注释掉则 Logo 恒为透明，只留文字，便于对比排查
//
//  关掉 OSD_ON 后 osd_overlay 完全不例化，mixer 直接吃 img_proc 的输出，
//  资源回到未加 OSD 的状态。
// =====================================================================
`define OSD_ON
`define OSD_LOGO_ROM

// =====================================================================
//  ★★ 简化自适应白平衡开关（2026-10-24）★★
//  打开 = 用自写的 awb_simple.v 替代厂商 awb.v（省约 5,438 slice）
//  注释掉 = 不做白平衡，画面偏紫红（传感器原始色偏）
//  注：厂商 AWB 本身由 isp_top.v 里的 `AWB_BYPASS 控制，当前为旁路状态
// =====================================================================
// 2026-10-24：厂商 AWB 已恢复（见 isp_top.v），它的白平衡 + 提亮已经够用，
//   这里不再叠加自写增益。固定增益版代码保留在 awb_simple.v，需要时再开。
//`define AWB_SIMPLE

// =====================================================================
//  ★★ 颜色阴影校正开关（2026-10-24）★★
//  打开 = 用 color_shading.v 做 10x6 分区增益，消除中央偏绿/两侧品红
//  注释掉 = 直通，用于对比开/关效果
// =====================================================================
`define SHADING_ON

module design_top_wrapper (
    input wire        I_sys_clk,
    input wire        I_rst_n,
      
    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
      
    inout wire [1:0]  I_button,

    // 板载乒乓开关 SW1~SW4（拨上=1），用于图像处理模式选择
    // 引脚见 pin.adc：A4 / B4 / E11 / D11
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
	(* keep = "true" *) wire [15:0] S_cam_sensor_id;
	(* keep = "true" *) wire        S_cam_sensor_id_ok;
	(* keep = "true" *) wire        S_cam_i2c_error;
	localparam integer CAM_PWDNB_LOW_CYCLES = 23810;  // >= 1 ms at 23.809524 MHz
	localparam integer CAM_I2C_START_CYCLES = 142857; // release + >= 5 ms
	
	wire [15:0] 	S_ae;
    wire [15:0] 	S_ag;
    wire 			S_cam_cfg_done;
    wire 			S_ae_cfg_done;
    wire 			S_ae_req; 
	
	wire        	S_csi_rx_clk;  
    wire        	S_hs_rx_valid;  
    wire[15:0]  	S_hs_rx_data;   
	wire[1:0]   	S_lane_error;
	
	wire        	S_csi_frame_start;       
	wire        	S_csi_frame_end;         
	wire        	S_csi_valid;             
	wire[31:0]  	S_csi_data;  
	(* keep = "true" *) wire [15:0] S_csi_data_length;
		
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

    // ===== 振动算法通路新增信号（DDR 三路仲裁 / 自检 / 测频）=====
    wire        S_vo_ddr_rd_valid;        // arb -> video_out（经 tag 路由后的读回）
    wire[127:0] S_vo_ddr_rd_data;         // arb -> video_out
    wire        S_vib_ddr_wr_en;
    wire        S_vib_ddr_rd_en;
    wire[24:0]  S_vib_ddr_addr;
    wire[127:0] S_vib_ddr_wr_data;
    wire        S_vib_ddr_ready;
    wire        S_vib_ddr_rd_valid;
    wire[127:0] S_vib_ddr_rd_data;
    wire        S_vib_ddr_want;
    wire        S_vib_ddr_own;
    wire[31:0]  S_ddrtest_words;
    wire[31:0]  S_ddrtest_errs;
    wire        S_ddrtest_done;
    wire[31:0]  S_mtr_csi_hz;
    wire[31:0]  S_mtr_px_per_sec;
    wire[31:0]  S_mtr_fps;
    wire[31:0]  S_mtr_px_per_frame;

    wire        S_vib_px_valid;
    wire[7:0]   S_vib_px_data;
    wire        S_vib_px_frame_start;
    wire        S_vib_px_line_end;
    wire[31:0]  S_vib_tap_px_per_frame;
    wire[15:0]  S_vib_tap_lines;
    wire[31:0]  S_vib_tap_px_sum;
    wire[31:0]  S_vib_tap_ovf;
    wire        S_vib_tap_tgl;

    // 3x3 高斯级（抽头 -> 高斯 -> 上一帧缓存）
    wire        S_g_valid;
    wire[7:0]   S_g_data;
    wire        S_g_frame_start;
    wire        S_g_line_end;
    wire[31:0]  S_g_px;
    wire[15:0]  S_g_lines;
    wire        S_g_tgl;

    // 算法 DDR 客户端：自检跑完后交棒给"上一帧缓存"模块
    wire        S_dt_wr_en, S_dt_rd_en, S_dt_want;
    wire[24:0]  S_dt_addr;
    wire[127:0] S_dt_wr_data;
    wire        S_dt_ready, S_dt_rd_valid;
    wire[127:0] S_dt_rd_data;

    wire        S_pf_wr_en, S_pf_rd_en, S_pf_want;
    wire[24:0]  S_pf_addr;
    wire[127:0] S_pf_wr_data;
    wire        S_pf_ready, S_pf_rd_valid;
    wire[127:0] S_pf_rd_data;

    wire[31:0]  S_it_px, S_it_lines, S_it_sum, S_it_err;
    wire[31:0]  S_it_line_rdy, S_it_state;
    wire signed [31:0] S_it_sgn;
    wire        S_pf_tgl;

    // B2c-1 LK 梯度级
    wire        S_lk_word_valid;
    wire[127:0] S_lk_cur_w, S_lk_prev;
    wire signed [31:0] S_lk_axx, S_lk_ayy, S_lk_axy, S_lk_bx, S_lk_by, S_lk_en;
    wire[31:0]  S_lk_px, S_lk_err;
    // 诊断采样：固定像素(行100/列100)的邻域字节与差值
    wire[7:0]   S_lk_dbg_m0, S_lk_dbg_m1, S_lk_dbg_m2, S_lk_dbg_p0;
    wire[5:0]   S_lk_dbg_sel;
    wire[7:0]   S_lk_dbg_pa, S_lk_dbg_pb;
    wire[31:0]  S_lk_dbg_ae, S_lk_dbg_af;
    wire[31:0]  S_lk_dbg_xa, S_lk_dbg_xb;
    wire[31:0]  S_fx_pos, S_fx_en;
    wire signed [31:0] S_fx_bx, S_fx_by;
    wire signed [32:0] S_fx_tex;
    // Goertzel 输出
    wire [4:0]  S_gz_bin;
    wire [7:0]  S_gz_hz10, S_gz_fcnt;
    wire [63:0] S_gz_mag;
    wire        S_gz_vld;
    // OSD 标记
    wire        S_osd_vs, S_osd_de;
    wire [23:0] S_osd_data;
    reg  [31:0] S_fx_pos_p1, S_fx_pos_p2;
    reg  [31:0] S_obj_pos_p1, S_obj_pos_p2;
    // 阶段 0：48x17 存储自检
    wire [31:0] S_gzcrc_w, S_gzcrc_r;
    wire        S_gzcrc_ok;
    wire        S_gzstore_busy, S_gzstore_done;
    wire signed [31:0] S_gz_hp, S_gz_in, S_gz_s1;
    wire signed [31:0] S_fx_axx, S_fx_ayy, S_fx_axy;
    wire               S_fx_tick;
    wire[7:0]   S_lk_dbg_la, S_lk_dbg_lb, S_lk_dbg_lc;
    wire[31:0]  S_sv_num_ld;
    wire[31:0]  S_lk_b_itsm;
    wire[31:0]  S_sv_det_h, S_sv_num_h, S_sv_quot;
    wire        S_sv_nu_neg;
    wire        S_lk_tgl;
    wire signed [31:0] S_lk_b_axx, S_lk_b_ayy, S_lk_b_axy;
    wire signed [31:0] S_lk_b_bx,  S_lk_b_by,  S_lk_b_en;
    wire [2:0]         S_lk_b_bcol, S_lk_b_brow;
    wire               S_lk_solve_req;

    // 阶段 2A：8x6 网格快照诊断信号（48 块共享 Goertzel 的输入候选）
    (* keep = "true" *) wire [255:0] S2_br_bx;
    (* keep = "true" *) wire [2:0]   S2_br_row;
    (* keep = "true" *) wire         S2_br_tick;
    (* keep = "true" *) wire [4:0]   S2_agc_exp;
    wire [39:0]  S2_axx_exp;
    wire signed [31:0] S2_fx_bx, S2_fx_by, S2_fx_en;
    wire signed [32:0] S2_fx_tex;
    wire signed [31:0] S2_fx_axx, S2_fx_ayy, S2_fx_axy;
    wire [31:0]        S2_fx_pos;
    wire signed [31:0] S2_b_axx, S2_b_ayy, S2_b_axy;
    wire signed [31:0] S2_b_bx, S2_b_by, S2_b_en;
    wire [2:0]         S2_b_bcol, S2_b_brow;
    wire [31:0]        S2_b_itsm;
    wire               S2_tgl, S2_solve_req, S2_fx_tick;
    wire [31:0]        S2_px, S2_err;
    wire signed [31:0] S2_axx, S2_ayy, S2_axy, S2_bx, S2_by, S2_en;
    wire [7:0]         S2_dbg_m0, S2_dbg_m1, S2_dbg_m2, S2_dbg_p0, S2_dbg_pa, S2_dbg_pb;
    wire [31:0]        S2_dbg_ae, S2_dbg_af, S2_dbg_xa, S2_dbg_xb;
    wire [5:0]         S2_dbg_sel;
    wire [7:0]         S2_dbg_la, S2_dbg_lb, S2_dbg_lc;

    // 阶段 2B：48 块共享 Goertzel + 峰值扫描
    wire [7:0]         S_mb_frm;
    wire               S_mb_tgl, S_mb_busy;
    wire [5:0]         S_mb_blk, S_mb_rowcnt;
    wire [4:0]         S_mb_bin;
    wire [31:0]        S_mb_rate, S_mb_ticks, S_mb_clrcnt;
    wire [4:0]         S_mb_agc_ref;
    wire [9:0]         S_pk_addr;
    wire [63:0]        S_pk_data;
    wire               S_pk_done, S_pk_busy;
    wire               S_pk_trig;
    wire [5:0]         S_pk_ntonal, S_pk_bestblk;
    wire [5:0]         S_pk_qact;        // 原始峰值与突出度通过的块数，确认前
    wire [31:0]        S_pk_bestmag;
    wire [4:0]         S_pk_bestbin;
    wire [7:0]         S_pk_hz10, S_pk_wincnt;
    wire [31:0]        S_pk_scancnt;
    wire [31:0]        S_pk_bin0, S_pk_bin12;
    wire [31:0]        S_pk_fb2, S_pk_fb4, S_pk_fb8, S_pk_fb12;
    wire [31:0]        S_pk_obj_pos, S_pk_obj_hz10;
    // 频谱/目标诊断均在扫描完成时锁存；保留旧 pn 端口名，值改为 raw peak>>8。
    wire [47:0]        S_pk_tonal_map;   // 合格块位图，bit n = row*8+col
    wire [127:0]       S_pk_obj_pn;      // 已确认目标原始峰值，与 obj_pos 同槽位
    wire [31:0]        S_pk_fx_pn;       // 本窗口全局原始峰值，尺度 raw peak>>8
    wire [31:0]        S_pk_tn, S_pk_raw_hz;
    wire [4:0]         S_pk_aexp;
    wire [2:0]         S_pk_confirmed;
    wire [4:0]         S_legacy_bin;
    wire [7:0]         S_legacy_hz10;
    wire [63:0]        S_legacy_mag;
    wire                S_legacy_valid, S_legacy_tonal, S_legacy_tgl;
    wire [31:0]        S_display_obj_pos, S_display_obj_hz10;
    wire [5:0]         S_pk_fx_sel, S_pk_chal_blk;
    wire [11:0]        S_pk_streak;
    reg  [1:0]         S_mb_tgl_s;
    reg                S_pk_done_tgl;
    wire S_selected_tgl, S_selected_done;
`ifdef VIB_LEGACY_GZ_ON
    // 旧模块的 frm_tgl 每帧翻转，不能拿它作为窗口完成标志；valid 只在窗口末脉冲。
    assign S_selected_tgl  = S_legacy_valid;
    assign S_selected_done = S_legacy_valid;
`else
    assign S_selected_tgl  = S_mb_tgl;
    assign S_selected_done = S_pk_done;
`endif
    wire               S_mb_tgl_p = S_mb_tgl_s[1] ^ S_mb_tgl_s[0];
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_mb_tgl_s <= 2'b00;
        else          S_mb_tgl_s <= {S_mb_tgl_s[0], S_selected_tgl};
    end
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if (!S_rst_n) S_pk_done_tgl <= 1'b0;
        else if (S_selected_done) S_pk_done_tgl <= ~S_pk_done_tgl;
    end
    assign S_pk_trig = S_mb_tgl_p & ~S_pk_busy;

    // B2c-2a 求解器
    wire signed [31:0] S_sv_u, S_sv_v;
    wire [31:0]        S_sv_en;
    wire [2:0]         S_sv_bcol, S_sv_brow;
    wire               S_sv_valid, S_sv_tgl;
    // ★ 注意：S_sv_det_h / S_sv_num_h / S_sv_quot / S_sv_nu_neg 已在上面
    //   （LK 诊断那一组，第 210~211 行）声明过，这里不能再声明一次——
    //   重复声明同一 net 是非法写法，会造成"到底用哪一个"的歧义。
    wire[31:0]         S_sv_den_h, S_sv_rem_h;
    wire               S_solve_ack;

    wire        S_vo_dbg_fifo_rst;
    wire        S_vo_dbg_ddr_rd_valid;
    wire        S_vo_dbg_fifo_rd_en;
    wire        S_vo_dbg_fifo_empty;

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
    wire        S_mc_dbg_fifo_afull;
    wire        S_mc_dbg_app_rdy;
    wire        S_mc_dbg_wdf_rdy;
    wire        S_mc_dbg_cmd_pop;

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

    // ===== 基础图像处理（基础要求 2.3(2)）=====
    //   插在 video_out 与 hdmi_mixer 之间，同属 S_hdmi_pixel_clk 域。
    //   I_mode: 0=原图 1=灰度 2=二值化（详见 img_proc.v 文件头）
    //   模式 0/1/2 是纯组合、零延迟，因此 mixer 的时序对齐不用改；
    //   模式 3（Sobel）因为要缓存两行，会晚 1 行 + 2 像素。
    //   `IMG_MODE_KEY 打开时由板载 KEY1~KEY4 运行期切换（见 img_mode_sel.v）；
    //   关掉那个宏则退回编译期固定模式 IMG_MODE。
    localparam integer IMG_MODE = 0;      // 上电默认：0=原图（KEY1~KEY4 可切，见 img_mode_sel.v）
    wire[23:0]  S_imgp_data;
    wire[23:0]  S_awb_data;
    wire[23:0]  S_csc_data;
    wire[23:0]  S_osd_mix;
    wire[ 2:0]  S_img_mode;
    wire        S_img_src_raw;
    wire        S_img_th_lock_req;
    wire        S_img_th_locked;
    wire[ 7:0]  S_img_threshold;
    wire        S_img_k_step;

    reg         S_dbg_raw_seen;
    reg         S_dbg_isp_seen;
    reg         S_dbg_ddr_wr_seen;
    reg         S_dbg_ddr_rd_seen;
    reg         S_dbg_cam_cfg_seen;
    reg         S_dbg_hs_seen;
    reg         S_dbg_csi_seen;
    reg         S_dbg_raw10_seen;
    reg         S_dbg_isp_fs_seen;
    reg         S_dbg_isp_valid_seen;
    reg         S_dbg_ddr_req_seen;
    reg         S_dbg_ddr_ready_seen;
    reg [1:0]   S_dbg_raw_seen_sync;
    reg [1:0]   S_dbg_isp_seen_sync;
    reg [1:0]   S_dbg_ddr_wr_seen_sync;
    reg [1:0]   S_dbg_ddr_rd_seen_sync;
    reg [1:0]   S_dbg_cam_cfg_seen_sync;
    reg [1:0]   S_dbg_hs_seen_sync;
    reg [1:0]   S_dbg_csi_seen_sync;
    reg [1:0]   S_dbg_raw10_seen_sync;
    reg [1:0]   S_dbg_isp_fs_seen_sync;
    reg [1:0]   S_dbg_isp_valid_seen_sync;
    reg [1:0]   S_dbg_ddr_req_seen_sync;
    reg [1:0]   S_dbg_ddr_ready_seen_sync;
    reg         S_dbg_video_nonzero_seen;
    reg         S_dbg_rd_req_seen;
    reg         S_dbg_rd_valid_seen;
    reg         S_dbg_rd_nonzero_seen;
    reg [1:0]   S_dbg_rd_req_seen_sync;
    reg [1:0]   S_dbg_rd_valid_seen_sync;
    reg [1:0]   S_dbg_rd_nonzero_seen_sync;
    reg         S_dbg_mc_init_seen;
    reg         S_dbg_mc_app_rdy_seen;
    reg         S_dbg_mc_wdf_rdy_seen;
    reg         S_dbg_mc_cmd_pop_seen;
    reg [1:0]   S_dbg_mc_init_seen_sync;
    reg [1:0]   S_dbg_mc_app_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_wdf_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_cmd_pop_seen_sync;
    wire[3:0]   S_hdmi_debug_status;
    wire        S_lane_error_any;
    wire        S_csi_packet_start;
    reg         S_csi_length_active_d;
    reg [10:0]  S_mipi_line_count;
    reg         S_mipi_length_error;
    reg         S_mipi_lane_error;
    reg         S_mipi_frame_seen;
    reg         S_mipi_frame_done;
    reg         S_mipi_last_length_error;
    reg         S_mipi_last_line_error;
    reg         S_mipi_last_lane_error;
    wire[3:0]   S_mipi_diag_status_async;
    reg [3:0]   S_mipi_diag_status_sync1;
    reg [3:0]   S_mipi_diag_status_sync2;


    assign O_screen_pwm = 1'b1;
    assign S_video_out_vsync = ~S_hdmi_vsync;
	
	
    assign S_rst_n 		= S_pll_lock;
    // HDMI 域要等 74.25/371.25 的那颗 PLL 也锁定
    // 2026-10-24：HDMI 时钟已改由主 PLL 输出，没有第二个 PLL 了
    assign S_hdmi_rst_n = S_pll_lock;

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw_seen <= 1'b0;
        else if(S_raw10_frame_start | S_axis_tvalid)
            S_dbg_raw_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_seen <= 1'b0;
        else if(S_ISP_O_tuser | S_ISP_O_tvalid)
            S_dbg_isp_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_wr_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_wr_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_rd_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_ddr_rd_seen <= 1'b1;
    end

    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_cam_cfg_seen <= 1'b0;
        else if(S_cam_cfg_done)
            S_dbg_cam_cfg_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_hs_seen <= 1'b0;
        else if(S_hs_rx_valid)
            S_dbg_hs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_csi_seen <= 1'b0;
        else if(S_csi_frame_start | S_csi_valid)
            S_dbg_csi_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw10_seen <= 1'b0;
        else if(S_raw10_frame_start | S_raw10_valid)
            S_dbg_raw10_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_fs_seen <= 1'b0;
        else if(S_ISP_O_tuser)
            S_dbg_isp_fs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_valid_seen <= 1'b0;
        else if(S_ISP_O_tvalid)
            S_dbg_isp_valid_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_req_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_ready_seen <= 1'b0;
        else if(S_ddr_user_ready)
            S_dbg_ddr_ready_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_vo_ddr_rd_en)
            S_dbg_rd_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_rd_valid_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
            S_dbg_rd_nonzero_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_init_seen <= 1'b0;
        else if(S_init_calib_complete)
            S_dbg_mc_init_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_app_rdy_seen <= 1'b0;
        else if(S_mc_dbg_app_rdy)
            S_dbg_mc_app_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_wdf_rdy_seen <= 1'b0;
        else if(S_mc_dbg_wdf_rdy)
            S_dbg_mc_wdf_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_cmd_pop_seen <= 1'b0;
        else if(S_mc_dbg_cmd_pop)
            S_dbg_mc_cmd_pop_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_dbg_cam_cfg_seen_sync <= 2'b00;
            S_dbg_hs_seen_sync      <= 2'b00;
            S_dbg_csi_seen_sync     <= 2'b00;
            S_dbg_raw10_seen_sync   <= 2'b00;
            S_dbg_raw_seen_sync    <= 2'b00;
            S_dbg_isp_seen_sync    <= 2'b00;
            S_dbg_ddr_wr_seen_sync <= 2'b00;
            S_dbg_ddr_rd_seen_sync <= 2'b00;
            S_dbg_isp_fs_seen_sync  <= 2'b00;
            S_dbg_isp_valid_seen_sync <= 2'b00;
            S_dbg_ddr_req_seen_sync <= 2'b00;
            S_dbg_ddr_ready_seen_sync <= 2'b00;
            S_dbg_video_nonzero_seen <= 1'b0;
            S_dbg_rd_req_seen_sync <= 2'b00;
            S_dbg_rd_valid_seen_sync <= 2'b00;
            S_dbg_rd_nonzero_seen_sync <= 2'b00;
            S_dbg_mc_init_seen_sync <= 2'b00;
            S_dbg_mc_app_rdy_seen_sync <= 2'b00;
            S_dbg_mc_wdf_rdy_seen_sync <= 2'b00;
            S_dbg_mc_cmd_pop_seen_sync <= 2'b00;
        end
        else begin
            S_dbg_cam_cfg_seen_sync <= {S_dbg_cam_cfg_seen_sync[0], S_dbg_cam_cfg_seen};
            S_dbg_hs_seen_sync      <= {S_dbg_hs_seen_sync[0],      S_dbg_hs_seen};
            S_dbg_csi_seen_sync     <= {S_dbg_csi_seen_sync[0],     S_dbg_csi_seen};
            S_dbg_raw10_seen_sync   <= {S_dbg_raw10_seen_sync[0],   S_dbg_raw10_seen};
            S_dbg_raw_seen_sync    <= {S_dbg_raw_seen_sync[0],    S_dbg_raw_seen};
            S_dbg_isp_seen_sync    <= {S_dbg_isp_seen_sync[0],    S_dbg_isp_seen};
            S_dbg_ddr_wr_seen_sync <= {S_dbg_ddr_wr_seen_sync[0], S_dbg_ddr_wr_seen};
            S_dbg_ddr_rd_seen_sync <= {S_dbg_ddr_rd_seen_sync[0], S_dbg_ddr_rd_seen};
            S_dbg_isp_fs_seen_sync  <= {S_dbg_isp_fs_seen_sync[0],  S_dbg_isp_fs_seen};
            S_dbg_isp_valid_seen_sync <= {S_dbg_isp_valid_seen_sync[0], S_dbg_isp_valid_seen};
            S_dbg_ddr_req_seen_sync <= {S_dbg_ddr_req_seen_sync[0], S_dbg_ddr_req_seen};
            S_dbg_ddr_ready_seen_sync <= {S_dbg_ddr_ready_seen_sync[0], S_dbg_ddr_ready_seen};
            S_dbg_rd_req_seen_sync <= {S_dbg_rd_req_seen_sync[0], S_dbg_rd_req_seen};
            S_dbg_rd_valid_seen_sync <= {S_dbg_rd_valid_seen_sync[0], S_dbg_rd_valid_seen};
            S_dbg_rd_nonzero_seen_sync <= {S_dbg_rd_nonzero_seen_sync[0], S_dbg_rd_nonzero_seen};
            S_dbg_mc_init_seen_sync <= {S_dbg_mc_init_seen_sync[0], S_dbg_mc_init_seen};
            S_dbg_mc_app_rdy_seen_sync <= {S_dbg_mc_app_rdy_seen_sync[0], S_dbg_mc_app_rdy_seen};
            S_dbg_mc_wdf_rdy_seen_sync <= {S_dbg_mc_wdf_rdy_seen_sync[0], S_dbg_mc_wdf_rdy_seen};
            S_dbg_mc_cmd_pop_seen_sync <= {S_dbg_mc_cmd_pop_seen_sync[0], S_dbg_mc_cmd_pop_seen};
            if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
                S_dbg_video_nonzero_seen <= 1'b1;
        end
    end

    assign S_lane_error_any = |S_lane_error;

    // A RAW10 line contains 1280 * 10 / 8 = 1600 bytes.  The CSI parser
    // reports the number of 16-bit lane words, therefore the expected value
    // is 1600 / 2 = 800 = 16'h0320.  Count one long packet whenever that
    // decoded length changes from zero to non-zero.
    assign S_csi_packet_start = (S_csi_data_length != 16'd0) &&
                                !S_csi_length_active_d;

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_csi_length_active_d      <= 1'b0;
            S_mipi_line_count          <= 11'd0;
            S_mipi_length_error        <= 1'b0;
            S_mipi_lane_error          <= 1'b0;
            S_mipi_frame_seen          <= 1'b0;
            S_mipi_frame_done          <= 1'b0;
            S_mipi_last_length_error   <= 1'b0;
            S_mipi_last_line_error     <= 1'b0;
            S_mipi_last_lane_error     <= 1'b0;
        end
        else begin
            S_csi_length_active_d <= (S_csi_data_length != 16'd0);

            if(S_csi_frame_start) begin
                S_mipi_line_count   <= 11'd0;
                S_mipi_length_error <= 1'b0;
                S_mipi_lane_error   <= 1'b0;
                S_mipi_frame_seen   <= 1'b1;
            end
            else begin
                if(S_csi_packet_start) begin
                    S_mipi_line_count <= S_mipi_line_count + 11'd1;
                    if(S_csi_data_length != 16'h0320)
                        S_mipi_length_error <= 1'b1;
                end

                if(S_lane_error_any)
                    S_mipi_lane_error <= 1'b1;
            end

            // Publish only a completed frame, so the HDMI-domain diagnostic
            // sees a stable result rather than counters changing every line.
            if(S_csi_frame_end) begin
                S_mipi_frame_done        <= 1'b1;
                S_mipi_last_length_error <= S_mipi_length_error;
                S_mipi_last_line_error   <= (S_mipi_line_count != 11'd720);
                S_mipi_last_lane_error   <= S_mipi_lane_error |
                                            S_lane_error_any;
            end
        end
    end

    // Diagnostic result codes consumed by hdmi_mixer DEBUG_MODE=4:
    // 0=config incomplete, 1=no HS traffic, 2=no completed CSI frame,
    // 3=lane error, 4=wrong RAW10 line length, 5=wrong lines/frame,
    // 6=the observed MIPI frame structure is correct, 7=I2C error.
    // I2C error has the highest priority because O_cfg_done only indicates
    // that the write sequencer reached its end; it does not prove that every
    // sensor register write was acknowledged successfully.
    assign S_mipi_diag_status_async =
        S_cam_i2c_error              ? 4'd7 :
        !S_cam_cfg_done              ? 4'd0 :
        !S_dbg_hs_seen               ? 4'd1 :
        !(S_mipi_frame_seen &&
          S_mipi_frame_done)         ? 4'd2 :
        S_mipi_last_lane_error       ? 4'd3 :
        S_mipi_last_length_error     ? 4'd4 :
        S_mipi_last_line_error       ? 4'd5 : 4'd6;

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_mipi_diag_status_sync1 <= 4'd0;
            S_mipi_diag_status_sync2 <= 4'd0;
        end
        else begin
            S_mipi_diag_status_sync1 <= S_mipi_diag_status_async;
            S_mipi_diag_status_sync2 <= S_mipi_diag_status_sync1;
        end
    end

    assign S_vo_dbg_fifo_rst = 1'b0;
    assign S_vo_dbg_ddr_rd_valid = 1'b0;
    assign S_vo_dbg_fifo_rd_en = 1'b0;
    assign S_vo_dbg_fifo_empty = 1'b0;
    assign S_mc_dbg_fifo_afull = 1'b0;
    assign S_mc_dbg_app_rdy = 1'b0;
    assign S_mc_dbg_wdf_rdy = 1'b0;
    assign S_mc_dbg_cmd_pop = 1'b0;

    assign S_hdmi_debug_status = S_mipi_diag_status_sync2;
	
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
      .I_btn({I_button,2'b11}),
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
//------------------------------------------------------------------
//  ★ 颜色校正强度固定（KEY4 已释放）
//    档位 0: 关闭 | 1: k=0.5 | 2: k=0.75 | 3: k=1.0
//    **按一下切一档并循环**；上电默认档位 2（k=0.75）。
//    当前固定使用默认档位 2，KEY4 不再参与颜色校正或阈值控制。
//
//  ★ 2026-10-24 修正：第一版写成「按住连发」（每 7ms 切一档），
//    按一下会连跳十几档，无法使用。现改为标准消抖 + **下降沿单次触发**：
//      KEY4 已释放，不再生成同步、去抖和切换逻辑。
//------------------------------------------------------------------
// KEY4 已释放：颜色校正固定在原来的默认档位 2，按键不再改变它。
wire [1:0] S_k_sel = 2'd2;

// （CSC 强度档在 hdmi 时钟域直接使用，无需跨时钟同步）

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

`ifndef VIB_NO_DISPLAY
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
`else
    // ---- 显示关闭：video_out 原本驱动的信号全部接地 ----
    //   O_video_out_rd_busy / O_ddr_user_rd_en / O_ddr_user_rd_addr 直接送给
    //   DDR 仲裁器的 VO 通道，必须驱动到确定电平，否则仲裁器握手会异常。
    assign S_video_out_rd_busy = 1'b0;
    assign S_vo_ddr_rd_en      = 1'b0;
    assign S_vo_ddr_rd_addr    = 25'd0;
    assign S_video_rd_data     = 24'd0;
`endif



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

`ifndef VIB_NO_DISPLAY
    //------------------------------------------------------------------
    //  基础图像处理：video_out -> img_proc -> hdmi_mixer
    //    彩色/灰度同拍；多数滤波中心晚1行1像素，Sobel保持原有延迟；不改HDMI同步
    //------------------------------------------------------------------
//----------------------------------------------------------------------
//  模式选择：板载 4 个按键（KEY1..KEY4 = D5/A9/B9/C7，按下=0）
//      KEY1=增强彩色 KEY2=算法循环 KEY3=释放 KEY4=释放
//    独立模块 img_mode_sel.v（内部10ms去抖 + 按下锁存），输出3 bit模式码。
//    `IMG_MODE_KEY 关掉时退回编译期固定模式 IMG_MODE。
//----------------------------------------------------------------------
`ifdef IMG_MODE_KEY
    img_mode_sel #(
        .MODE_RST   ( IMG_MODE   ),   // 上电默认模式
        .CLK_HZ     ( 75000000   ),   // = S_hdmi_pixel_clk（2026-10-24 起 75 MHz）
        .DB_MS      ( 10         )
    )u_img_mode_sel(
        .I_clk      ( S_hdmi_pixel_clk ),
        .I_rst_n    ( S_hdmi_rst_n     ),
        .I_key_n    ( I_key            ),   // {KEY4,KEY3,KEY2,KEY1}，按下=0
        .O_mode     ( S_img_mode       ),
        // KEY3已释放；最终二值化固定使用增强图像。
        .O_th_lock  ( S_img_th_lock_req),
        .O_k_step   ( S_img_k_step     )
    );
`else
    assign S_img_mode = IMG_MODE[2:0];
    assign S_img_th_lock_req = 1'b0;
    assign S_img_k_step = 1'b0;
`endif
    // 最终二值化固定增强源，KEY3不再改变视频或OSD状态。
    assign S_img_src_raw = 1'b0;

    //------------------------------------------------------------------
    //  简化自适应白平衡（2026-10-24）
    //    替代厂商 awb.v（省约 5,438 slice）：用"上一帧统计、当前帧应用"，
    //    零延迟、零 ERAM。详见 awb_simple.v 文件头。
    //    `AWB_SIMPLE 关掉则整段旁路（画面会偏紫红，因为传感器色偏没被校正）。
    //------------------------------------------------------------------
`ifdef AWB_SIMPLE
    awb_simple u_awb_simple (
        .I_clk      ( S_hdmi_pixel_clk ),
        .I_rst_n    ( S_hdmi_rst_n     ),
        .I_vs       ( S_hdmi_vsync     ),
        .I_de       ( S_hdmi_de        ),
        .I_data     ( S_video_rd_data  ),
        .O_data     ( S_awb_data       )
    );
`else
    assign S_awb_data = S_video_rd_data;
`endif

    //------------------------------------------------------------------
    //  颜色阴影校正（2026-10-24）
    //    实测偏色是**空间不均匀**的：左侧 G-R≈-10（品红）、中央≈+21（绿）、
    //    右侧≈-5。跨 2 小时抓的 4 帧该分布相关系数 0.993~0.998，
    //    所以是镜头/传感器固定 pattern，不是光源、全局 AWB 修不了。
    //    用 10x6 分区增益校正，零延迟、零 ERAM。详见 color_shading.v。
    //    `SHADING_ON 注释掉则直通（用于对比开/关效果）。
    //------------------------------------------------------------------
`ifdef SHADING_ON
    color_shading u_color_shading (
        .I_clk      ( S_hdmi_pixel_clk ),
        .I_rst_n    ( S_hdmi_rst_n     ),
        .I_vs       ( S_hdmi_vsync     ),
        .I_de       ( S_hdmi_de        ),
        .I_data     ( S_awb_data       ),
        .I_k_sel   ( S_k_sel         ),
        .O_data     ( S_csc_data       )
    );
`else
    assign S_csc_data = S_awb_data;
`endif

    //------------------------------------------------------------------
    //  基础图像处理：video_out -> awb_simple -> color_shading -> img_proc
    //    灰度/Sobel固定video_out原图；二值化固定增强图像，KEY3释放
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
        .I_src_raw  ( S_img_src_raw    ),
        .I_th_lock  ( S_img_th_lock_req),
        .O_data     ( S_imgp_data      ),
        .O_threshold( S_img_threshold ),
        .O_th_locked( S_img_th_locked )
    );
    //------------------------------------------------------------------
    //  OSD 叠加：右上角安路 Logo + 左上角算法名
    //    纯组合 3 选 1，数据零延迟，mixer 的 2 级对齐不受影响
    //------------------------------------------------------------------
`ifdef OSD_ON
    osd_overlay #(
        .OSD_EN     ( 1    ),
        .TH_DEBUG_EN( 0    ),
        .LOGO_EN    ( 0    ),
        .H_ACTIVE   ( 1280 ),
        .V_ACTIVE   ( 720  ),
        .LOGO_W     ( 128  ),
        .LOGO_H     ( 80   ),
        .LOGO_X     ( 1136 ),
        .LOGO_Y     ( 16   ),
        .TEXT_X     ( 24   ),
        .TEXT_Y     ( 24   ),
        .BOX_PAD    ( 8    )
    )u_osd_overlay(
        .I_clk      ( S_hdmi_pixel_clk ),
        .I_rst_n    ( S_hdmi_rst_n     ),
        .I_de       ( S_hdmi_de        ),
        .I_vs       ( S_hdmi_vsync     ),
        .I_mode     ( S_img_mode       ),
        .I_src_raw  ( S_img_src_raw    ),
        .I_threshold( S_img_threshold ),
        .I_th_locked( S_img_th_locked ),
        .I_k_sel    ( S_k_sel           ),
        .I_data     ( S_imgp_data      ),
        .O_data     ( S_osd_mix        )
    );
`else
    assign S_osd_mix = S_imgp_data;
`endif

    hdmi_mixer #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        // Normal camera display.  Set to 4 only when the MIPI diagnostic
        // full-screen status page is needed.
        // 2026-10-21：彩条诊断已通过（OBS 抓到八色条，证明 HDMI 链路 OK），
        //              改回 0 = 正常显示 img_proc 处理后的摄像头画面。
        .DEBUG_MODE ( 0    )
    )u_hdmi_mixer(
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_video_vsync   ( S_hdmi_vsync       ),
        .I_video_hsync   ( S_hdmi_hsync       ),
        .I_video_de      ( S_hdmi_de          ),
        .I_video_user    ( S_hdmi_user        ),
        .I_video_last    ( S_hdmi_last        ),
        .I_debug_status  ( S_hdmi_debug_status),
        .O_video_rd_en   ( S_hdmi_window_rd_en),
        .I_video_rd_data ( S_osd_mix        ),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )
    );

    //==================================================================
    //  屏幕调试标记：在 hdmi_mixer 和 hdmi_tx 之间叠加
    //    · 左上角绿色 L 形参考标记 → 判断画面有没有镜像/翻转
    //        正常：长臂指向右；镜像：长臂指向左
    //    · 固定纹理块的品红外框（2 像素）
    //  这两样都画在算法取数之后，不影响振动算法。
    //
    //  st_fx_pos 在 S_ddr_clk 域，这里是 S_hdmi_pixel_clk 域，
    //  加两级同步；它是慢变信号（128 帧更新一次），单帧采错无所谓。
    //==================================================================
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_fx_pos_p1 <= 32'd0;
            S_fx_pos_p2 <= 32'd0;
            S_obj_pos_p1 <= 32'd0;
            S_obj_pos_p2 <= 32'd0;
        end
        else begin
            S_fx_pos_p1 <= S_fx_pos;
            S_fx_pos_p2 <= S_fx_pos_p1;
            S_obj_pos_p1 <= S_pk_obj_pos;
            S_obj_pos_p2 <= S_obj_pos_p1;
        end
    end

`ifdef VIB_STAGE2_GZ_ON   // vib_osd_marker
    vib_osd_marker u_vib_osd_marker (
        .clk    ( S_hdmi_pixel_clk ),
        .rst_n  ( S_hdmi_rst_n     ),
        .I_vs   ( S_hdmi_out_vsync ),
        .I_de   ( S_hdmi_out_de    ),
        .I_data ( S_hdmi_out_data  ),
        .I_pos  ( S_fx_pos_p2      ),
        .I_obj_pos ( S_obj_pos_p2   ),
        .O_vs   ( S_osd_vs         ),
        .O_de   ( S_osd_de         ),
        .O_data ( S_osd_data       )
    );
`endif   // VIB_STAGE2_GZ_ON   (vib_osd_marker)

//=============================================================================
//  VIB_ON 未定义时：振动链路关闭，这里补齐 tie-off
//    · 保留 vib_video_tap（只给 VSUM，约 880 slice，是"摄像头活着"的唯一证据）
//    · 关闭：gauss3x3 / prev_frame_ddr / lk_grid / lk_solve /
//            goertzel / gz_store / osd_marker
//=============================================================================
`ifndef VIB_FRAME_DIFF_ON
    assign S_vib_ddr_wr_en   = 1'b0;
    assign S_vib_ddr_rd_en   = 1'b0;
    assign S_vib_ddr_addr    = 32'd0;
    assign S_vib_ddr_wr_data = 128'd0;
    assign S_vib_ddr_want    = 1'b0;
`endif

// 阶段 1仍然使用帧差 DDR，但 VIB_ON 没有打开振动 OSD；因此 HDMI TX
// 必须继续使用 mixer 的正常视频输出，不能因为帧差宏打开而留下未驱动端口。
`ifndef VIB_STAGE2_GZ_ON
    assign S_fx_pos   = 32'd0;
    assign S_osd_vs   = S_hdmi_out_vsync;
    assign S_osd_de   = S_hdmi_out_de;
    assign S_osd_data = S_hdmi_out_data;
`endif

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
`else
    // ---- 显示关闭：hdmi_mixer / hdmi_tx 原本驱动的信号全部接地 ----
    //   顶层 TMDS 差分输出必须驱动，否则会报输出未驱动。
    assign S_imgp_data         = 24'd0;
    assign S_hdmi_window_rd_en = 1'b0;
    assign S_hdmi_out_vsync    = 1'b0;
    assign S_hdmi_out_hsync    = 1'b0;
    assign S_hdmi_out_de       = 1'b0;
    assign S_hdmi_out_data     = 24'd0;
    assign O_tmds_ch0_p        = 1'b0;
    assign O_tmds_ch1_p        = 1'b0;
    assign O_tmds_ch2_p        = 1'b0;
    assign O_tmds_clk_p        = 1'b0;
`endif


    // =================================================================
    //  DDR 算法区域自检  ——  先独立证明"算法专用 DDR 区域"可用
    //    区域：基址 24_000_000 地址单位 = 48 MB，14400 拍 = 230400 字节
    //          （正好是 640x360 灰度上一帧缓存的大小）
    //    官方 4 个 RGB 帧缓存占 0~22_382_400 单位（0~44.8 MB），
    //    总空间 2^25 单位 = 64 MB，所以 48 MB 处空闲，不会踩到显示通路。
    //    结果走串口：DTRD 应 = 0x00003840(14400)，DTER 必须 = 0
    // =================================================================
    // =================================================================
    //  DDR 一次性自检已移除（节省资源，提升布局布线速度）。
    //  该自检与振动算法无关，只是上电时验证 DDR 读写通路。
    //  恢复方法：把 vib_handwritten_divider_backup_20261017 里对应版本的
    //  这段例化贴回，并把下面 S_dt_active 改回 ~S_ddrtest_done。
    // =================================================================

    // =================================================================
    //  上一帧灰度缓存 + 帧差 It（B2b）
    //    csi 域收抽头的 640x360 灰度，打包后跨时钟域交给 ddr 域；
    //    ddr 域从 DDR 读回上一帧同一行、算 |It|、再把当前行写回同一地址。
    //    自检（S_ddrtest_done）跑完之后才交棒给这个模块，两者共用同一个
    //    DDR 区域（48 MB 处），自检的图案会被第一帧覆盖掉。
    //    自检：ITPX 应 = 0x00038400，ITLN 应 = 360，ITER 必须 = 0；
    //          ITSM(Σ|It|) 静止时接近 0，画面一动立刻涨。
    // =================================================================
    // =================================================================
    //  3x3 高斯平滑（B2c 前置级）
    //    抽头输出的原始灰度 -> 高斯后的灰度 -> 送给上一帧缓存做帧差
    //    自检：GOFP 应 = 0x00038400（230400），GOFL 应 = 360 = 0x00000168
    //    注意本模块输出行比输入行晚一行（竖直 3 行窗口），末行靠回放补齐
    // =================================================================
`ifdef VIB_FRAME_DIFF_ON   // vib_gauss3x3
    vib_gauss3x3 u_vib_gauss3x3 (
        .clk            ( S_csi_rx_clk           ),
        .rst_n          ( S_rst_n                ),

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
`endif   // VIB_FRAME_DIFF_ON   (vib_gauss3x3)

`ifdef VIB_FRAME_DIFF_ON   // vib_prev_frame_ddr
    vib_prev_frame_ddr u_vib_prev_frame_ddr (
        .csi_clk        ( S_csi_rx_clk           ),
        .csi_rst_n      ( S_rst_n                ),
        .px_valid       ( S_g_valid              ),
        .px_data        ( S_g_data               ),
        .px_frame_start ( S_g_frame_start        ),
        .px_line_end    ( S_g_line_end           ),

        .clk            ( S_ddr_clk              ),
        .rst_n          ( S_rst_n                ),

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
`endif   // VIB_FRAME_DIFF_ON   (vib_prev_frame_ddr)

    // =================================================================
`ifdef VIB_FRAME_DIFF_ON   // DDR二选一
    //  DDR 算法客户端二选一：自检完成前给自检，完成后给上一帧缓存
    //    两者共用 vib_ddr_arb 的同一个 vib 端口，必须互斥。
    //    ready / 读回也按同样条件门控，避免未选中那个误收数据。
    // =================================================================
    wire S_dt_active = 1'b0;   // 自检已移除，恒走上一帧通路

    assign S_vib_ddr_wr_en   = S_dt_active ? S_dt_wr_en   : S_pf_wr_en;
    assign S_vib_ddr_rd_en   = S_dt_active ? S_dt_rd_en   : S_pf_rd_en;
    assign S_vib_ddr_addr    = S_dt_active ? S_dt_addr    : S_pf_addr;
    assign S_vib_ddr_wr_data = S_dt_active ? S_dt_wr_data : S_pf_wr_data;
    assign S_vib_ddr_want    = S_dt_active ? S_dt_want    : S_pf_want;

    assign S_dt_ready        = S_vib_ddr_ready    &  S_dt_active;
    assign S_pf_ready        = S_vib_ddr_ready    & ~S_dt_active;
    assign S_dt_rd_valid     = S_vib_ddr_rd_valid &  S_dt_active;
    assign S_pf_rd_valid     = S_vib_ddr_rd_valid & ~S_dt_active;
    assign S_dt_rd_data      = S_vib_ddr_rd_data;
    assign S_pf_rd_data      = S_vib_ddr_rd_data;
`endif   // VIB_FRAME_DIFF_ON   (DDR二选一)

    // =================================================================
    //  实测 S_csi_rx_clk 频率 / ISP 像素率 / 帧率 / 每帧像素数
    //    用 I_sys_clk(50MHz) 做 1 秒基准窗口做计数，不需要除法器。
    //    PXFR 应恒等于 1280*720 = 921600 = 0x000E1000（最强的一条自检）
    //    CSIH / PIXS 的比值 = 平均每像素有几个 csi 时钟，决定数据通路宽度
    // =================================================================
    clk_pixel_meter #(
        .REF_HZ      (50_000_000),
        .IMG_W       (1280),
        .IMG_H       (720)
    ) u_clk_pixel_meter (
        .ref_clk        ( I_sys_clk          ),
        .ref_rst_n      ( I_rst_n            ),
        .csi_clk        ( S_csi_rx_clk       ),
        .csi_rst_n      ( S_rst_n            ),
        .beat_valid     ( S_ISP_O_tvalid     ),
        .frame_start    ( S_ISP_O_tuser      ),

        .csi_hz         ( S_mtr_csi_hz       ),
        .px_per_sec     ( S_mtr_px_per_sec   ),
        .fps            ( S_mtr_fps          ),
        .px_per_frame   ( S_mtr_px_per_frame )
    );


    // =================================================================
    //  视频抽头：ISP 输出 -> 灰度(R+2G+B)>>2 + 2x2 盒式平均 -> 640x360 灰度
    //    * 纯只读监听，没有 ready / 反压，不可能影响显示通路
    //    * 覆盖整幅 1280x720（全屏识别，不做固定 ROI）
    //    * ISP 的 128bit 是连续 24bit/像素流（5.33 像素/拍），不是 4 个槽位
    //    自检：VOFP 应 = 230400 = 0x00038400，VOFL 应 = 360，VTAP 必须 = 0
    //    px_* 输出留给下一步（DDR 上一帧缓存 + 帧差）使用
    // =================================================================
    vib_video_tap u_vib_video_tap (
        .clk            ( S_csi_rx_clk            ),
        .rst_n          ( S_rst_n                 ),

        .in_valid       ( S_ISP_O_tvalid          ),
        .in_data        ( S_ISP_O_tdata           ),
        .in_frame_start ( S_ISP_O_tuser           ),
        .in_line_end    ( S_ISP_O_tlast           ),

        .px_valid       ( S_vib_px_valid          ),
        .px_data        ( S_vib_px_data           ),
        .px_frame_start ( S_vib_px_frame_start    ),
        .px_line_end    ( S_vib_px_line_end       ),

        .st_frame_px    ( S_vib_tap_px_per_frame  ),
        .st_frame_ln    ( S_vib_tap_lines         ),
        .st_px_sum      ( S_vib_tap_px_sum        ),
        .st_ovf         ( S_vib_tap_ovf           ),
        .st_tgl         ( S_vib_tap_tgl           )
    );


    // =================================================================
    //  串口日志输出 (UART log)  ——  从老工程 lab_ex1_mipi_hdmi 移植
    //    时钟  : I_sys_clk = 50MHz（见 camera_to_dsi_display.sdc: sys_clk_50m）
    //    引脚  : O_uart_tx -> H1（见 pin.adc）
    //    格式  : 115200 8N1；上电先打一轮，之后每 1 秒一轮，字段由生成器管理
    //    内容  : 见 uart_log_debug.v 文件头说明
    //    复位  : 用 I_rst_n，这样 PLL 还没锁的时候串口就已经在打印了
    // =================================================================
    //  B2c-1：Lucas-Kanade 梯度级 + 8x6 块累加器
    //    直接消费 B2b 的流式输出（同在 S_ddr_clk 域，不需要跨时钟域）
    //    自检：LKPX 应 = 0x00038400，LKER 必须 = 0
    //          LKAX/LKAY 是块(0,0)的 ΣdIx²/ΣdIy²（dIx = g[x+1]-g[x-1] 未除 2）
    //          与 Python 对比：axx_hw = 4*axx_py，bx_hw = 2*bx_py，en 相同
    // =================================================================
`ifdef VIB_STAGE2_LK_ON
    // Enhanced 8x6 grid snapshots feed the shared 17-bin Goertzel engine.
    // 旧单块 LK 仍由 VIB_ON 控制，两个模块不会同时驱动同一信号。
    (* keep_hierarchy = "yes" *) vib_lk_grid_multi u_vib_lk_grid_multi (
        .clk            ( S_ddr_clk              ),
        .rst_n          ( S_rst_n                ),
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
        .o_px_valid     (                        ),
        .o_px_it        (                        ),
        .o_px_x         (                        ),
        .o_px_y         (                        ),
        .o_axx_exp      ( S2_axx_exp             ),
        .o_agc_exp      ( S2_agc_exp             )
    );
`endif

`ifdef VIB_STAGE2_GZ_ON
`ifndef VIB_LEGACY_GZ_ON
    vib_gz_multi #(
        .NFRM(64), .NBIN(17), .NROW(6), .NCOL(8)
    ) u_vib_gz_multi (
        .clk        ( S_ddr_clk       ),
        .rst_n      ( S_rst_n         ),
        .i_bx8      ( S2_br_bx        ),
        .i_agc_exp  ( S2_agc_exp      ),
        .i_row      ( S2_br_row       ),
        .i_tick     ( S2_br_tick      ),
        .o_frm      ( S_mb_frm        ),
        .o_frm_tgl  ( S_mb_tgl        ),
        .o_busy     ( S_mb_busy       ),
        .o_dbg_blk  ( S_mb_blk        ),
        .o_dbg_bin  ( S_mb_bin        ),
        .o_dbg_rate ( S_mb_rate       ),
        .o_dbg_rowcnt( S_mb_rowcnt   ),
        .o_tick_cnt ( S_mb_ticks      ),
        .i_pk_done  ( S_pk_done       ),
        .o_clr_cnt  ( S_mb_clrcnt     ),
        .o_dbg_agc_ref( S_mb_agc_ref  ),
        .pk_b_addr  ( S_pk_addr       ),
        .pk_b_data  ( S_pk_data       )
    );

    // 17 个频点覆盖 2.0~10.0Hz，步进 0.5Hz。
    // TONE_RATIO=0 采用旧工程 raw 峰值突出度；四目标按位置/频率独立确认。
    vib_gz_peak #(.NBIN(17), .NB(48), .BIN_MIN(0), .TONE_RATIO(0)) u_vib_gz_peak (
        .clk        ( S_ddr_clk       ),
        .rst_n      ( S_rst_n         ),
        .trig       ( S_pk_trig       ),
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
        .o_obj_pn    ( S_pk_obj_pn    ),
        .o_fx_pn     ( S_pk_fx_pn     ),
        .o_scan_cnt  ( S_pk_scancnt   ),
        .o_win_cnt   ( S_pk_wincnt    ),
        .o_dbg_fx_sel   ( S_pk_fx_sel   ),
        .o_dbg_chal_blk ( S_pk_chal_blk ),
        .o_dbg_streak   ( S_pk_streak   ),
        .o_dbg_aexp     ( S_pk_aexp     ),
        .o_confirmed    ( S_pk_confirmed)
    );
`else
    // 旧工程单块 Goertzel 对照链：固定使用纹理最强块的 bx，
    // 每个窗口给出一个频率结果。当前多目标链保持不例化，节省 DSP。
    vib_goertzel #(.NFRM(128), .NBIN(17)) u_vib_legacy_goertzel (
        .clk       ( S_ddr_clk       ),
        .rst_n     ( S_rst_n         ),
        .tick      ( S2_fx_tick      ),
        .bx        ( S2_fx_bx        ),
        .peak_bin  ( S_legacy_bin    ),
        .peak_hz10 ( S_legacy_hz10   ),
        .peak_mag  ( S_legacy_mag    ),
        .valid     ( S_legacy_valid  ),
        .frm_cnt   (                 ),
        .frm_tgl   ( S_legacy_tgl    ),
        .dbg_hp    (                 ),
        .dbg_in    (                 ),
        .dbg_s1    (                 )
    );
    assign S_pk_done    = 1'b0;
    assign S_pk_busy    = 1'b0;
    assign S_pk_hz10    = S_legacy_hz10;
    assign S_pk_bestmag = S_legacy_mag[31:0];
    // 当前工程版本的 vib_goertzel 没有 tonal/total_mag/psum_hi 端口。
    // 旧链路用窗口有效结果和峰值绝对门限作为旁路判据。
    wire legacy_keep = (S_legacy_mag > 64'd4000);
    assign S_pk_obj_pos = legacy_keep ?
                          {25'd0, S2_fx_pos[6:0]} : 32'd0;
    assign S_pk_obj_hz10 = legacy_keep ?
                           {24'd0, S_legacy_hz10} : 32'd0;
    assign S_pk_ntonal  = legacy_keep ? 6'd1 : 6'd0;
    assign S_pk_qact    = legacy_keep ? 6'd1 : 6'd0;
    assign S_pk_scancnt = 32'd0;
    // 多块诊断在旧单块分支不存在，显式接地；与活动分支互斥。
    assign S_pk_bestbin   = 5'd0;
    assign S_pk_bestblk   = 6'd0;
    assign S_pk_chal_blk  = 6'd0;
    assign S_pk_fb2       = 32'd0;
    assign S_pk_fb4       = 32'd0;
    assign S_pk_fb8       = 32'd0;
    assign S_pk_fb12      = 32'd0;
    assign S_pk_tn        = 32'd0;
    assign S_pk_raw_hz    = 32'd0;
    assign S_pk_aexp      = 5'd0;
    assign S_pk_confirmed = 3'd0;
    assign S_pk_tonal_map = 48'd0;
    assign S_pk_obj_pn    = 128'd0;
    assign S_pk_fx_pn     = 32'd0;
    assign S_pk_wincnt  = 8'd0;
    assign S_pk_fx_sel  = S2_fx_pos[5:0];
    assign S_pk_streak  = legacy_keep ? 12'd1 : 12'd0;
    assign S_mb_agc_ref = 5'd18;
    assign S_mb_clrcnt  = 32'd17;
    // 当前工程没有打开旧 VIB_ON 单块 LK，OSD 的固定块标记改用阶段2A块坐标。
`endif
    assign S_fx_pos = S2_fx_pos;
`endif

`ifdef VIB_ON   // vib_lk_grid
    vib_lk_grid u_vib_lk_grid (
        .clk            ( S_ddr_clk              ),
        .rst_n          ( S_rst_n                ),

        .word_valid     ( S_lk_word_valid        ),
        .word_cur       ( S_lk_cur_w             ),
        .word_prev      ( S_lk_prev               ),

        .st_axx         ( S_lk_axx               ),
        .st_ayy         ( S_lk_ayy               ),
        .st_axy         ( S_lk_axy               ),
        .st_bx          ( S_lk_bx                ),
        .st_by          ( S_lk_by                ),
        .st_en          ( S_lk_en                ),

        .st_px          ( S_lk_px                ),
        .st_err         ( S_lk_err               ),
        .st_dbg_m0      ( S_lk_dbg_m0            ),
        .st_dbg_m1      ( S_lk_dbg_m1            ),
        .st_dbg_m2      ( S_lk_dbg_m2            ),
        .st_dbg_p0      ( S_lk_dbg_p0            ),
        .st_dbg_pa      ( S_lk_dbg_pa            ),
        .st_dbg_pb      ( S_lk_dbg_pb            ),
        .st_dbg_ae      ( S_lk_dbg_ae            ),
        .st_dbg_af      ( S_lk_dbg_af            ),
        .st_dbg_xa      ( S_lk_dbg_xa            ),
        .st_dbg_xb      ( S_lk_dbg_xb            ),
        .st_dbg_sel     ( S_lk_dbg_sel           ),
        .st_dbg_la      ( S_lk_dbg_la            ),
        .st_dbg_lb      ( S_lk_dbg_lb            ),
        .st_dbg_lc      ( S_lk_dbg_lc            ),
        .st_b_itsm      ( S_lk_b_itsm            ),
        .i_it_sum       ( S_it_sum               ),
        .st_tgl         ( S_lk_tgl               ),
        .st_b_axx       ( S_lk_b_axx             ),
        .st_b_ayy       ( S_lk_b_ayy             ),
        .st_b_axy       ( S_lk_b_axy             ),
        .st_b_bx        ( S_lk_b_bx              ),
        .st_b_by        ( S_lk_b_by              ),
        .st_b_en        ( S_lk_b_en              ),
        .st_fx_pos      ( S_fx_pos               ),
        .st_fx_bx       ( S_fx_bx                ),
        .st_fx_by       ( S_fx_by                ),
        .st_fx_en       ( S_fx_en                ),
        .st_fx_tex      ( S_fx_tex               ),
        .st_fx_axx      ( S_fx_axx               ),
        .st_fx_ayy      ( S_fx_ayy               ),
        .st_fx_axy      ( S_fx_axy               ),
        .st_fx_tick     ( S_fx_tick              ),
        .st_b_bcol      ( S_lk_b_bcol            ),
        .st_b_brow      ( S_lk_b_brow            ),
        .st_solve_req   ( S_lk_solve_req         ),
        .st_solve_ack   ( S_solve_ack            )
    );
`endif   // VIB_ON   (vib_lk_grid)

    // =================================================================
    //  B2c-2a：对"本帧变化最大的块"做 2x2 Lucas-Kanade 求解
    //    输出 u/v 为 Q8.8（1 LSB = 1/256 像素/帧），已按 u_py = 2*u_hw
    //    换算回 Python 的像素单位，可直接与 Python 的 u/v 比较。
    //    LKVA=0 表示该块没通过门限（梯度不足或条件数太差），u/v 无意义。
    // =================================================================
    //==================================================================
    //  Goertzel：固定块的 bx 每帧一个采样点 → 17 频点 → 峰值频率
    //
    //  和 LK 同在 S_ddr_clk 域，bx 直接接，**不需要 CDC**。
    //  st_fx_tick 是固定块锁存那一拍的脉冲，正好是"新采样点就绪"。
    //
    //  上次实测（用 model_goertzel.py + check_goertzel_rtl.py 验证）：
    //    7 个纯音 2.0~10.0 Hz 全部识别正确，加噪声 3/3
    //    35.5 拍/帧，占用 0.003%
    //==================================================================
    //==================================================================
    //  阶段 0：48x17 Goertzel 状态阵列 + 上电自检
    //    只验证"26,112 bit 能不能进 RAM"，不接任何算法数据。
    //    自检期望：sum1 = 0x000512E8、sum2 = 0xFFFAED18
    //==================================================================
`ifdef VIB_ON   // vib_gz_store
    vib_gz_store #(
        .NB   ( 48 ),
        .NBIN ( 17 )
    ) u_vib_gz_store (
        .clk    ( S_ddr_clk        ),
        .rst_n  ( S_rst_n          ),
        .o_wcrc ( S_gzcrc_w        ),
        .o_rcrc ( S_gzcrc_r        ),
        .o_match( S_gzcrc_ok       ),
        .o_busy ( S_gzstore_busy   ),
        .o_done ( S_gzstore_done   )
    );
`endif   // VIB_ON   (vib_gz_store)

`ifdef VIB_ON   // vib_goertzel
    vib_goertzel #(
        .NFRM ( 128 ),
        .NBIN ( 17  )
    ) u_vib_goertzel (
        .clk        ( S_ddr_clk    ),
        .rst_n      ( S_rst_n      ),
        .tick       ( S_fx_tick    ),
        .bx         ( S_fx_bx      ),
        .peak_bin   ( S_gz_bin     ),
        .peak_hz10  ( S_gz_hz10    ),
        .peak_mag   ( S_gz_mag     ),
        .valid      ( S_gz_vld     ),
        .frm_cnt    ( S_gz_fcnt    ),
        .dbg_hp     ( S_gz_hp      ),
        .dbg_in     ( S_gz_in      ),
        .dbg_s1     ( S_gz_s1      ),
        .frm_tgl    (              )
    );
`endif   // VIB_ON   (vib_goertzel)

`ifdef VIB_ON   // vib_lk_solve
    vib_lk_solve u_vib_lk_solve (
        .clk            ( S_ddr_clk              ),
        .rst_n          ( S_rst_n                ),

        .req            ( S_lk_solve_req         ),
        // ★ 求解器输入改用**纹理固定块**（fx_*），不再用最大变化块（st_b_*）。
        //   最大变化块的坐标每帧都会跳（实测 blk2→blk3→blk1→blk5→blk4→blk6），
        //   时间序列中途换信号源会让 Goertzel 看到虚假的突变成分。
        .s_axx          ( S_fx_axx               ),
        .s_ayy          ( S_fx_ayy               ),
        .s_axy          ( S_fx_axy               ),
        .s_bx           ( S_fx_bx                ),
        .s_by           ( S_fx_by                ),
        .s_en           ( S_fx_en                ),
        .s_bcol         ( S_fx_pos[2:0]          ),
        .s_brow         ( S_fx_pos[5:3]          ),

        .ack            ( S_solve_ack            ),
        .r_u            ( S_sv_u                 ),
        .r_v            ( S_sv_v                 ),
        .r_en           ( S_sv_en                ),
        .r_bcol         ( S_sv_bcol              ),
        .r_brow         ( S_sv_brow              ),
        .r_valid        ( S_sv_valid             ),
        .r_tgl          ( S_sv_tgl               ),
        .r_det_h        ( S_sv_det_h             ),
        .r_num_h        ( S_sv_num_h             ),
        .r_quot         ( S_sv_quot              ),
        .r_nu_neg       ( S_sv_nu_neg            ),
        .r_den_h        ( S_sv_den_h             ),
        .r_rem_h        ( S_sv_rem_h             ),
        .r_num_ld       ( S_sv_num_ld            )
    );
`endif   // VIB_ON   (vib_lk_solve)

    // =================================================================
    //  统计量的跨时钟域**原子快照**（修一个真实观测到的问题）
    //
    //  为什么要做：
    //    这些 32bit 统计量原本是**直接**从 csi/ddr 域接到 I_sys_clk 域的
    //    串口模块上的（连两拍同步都没有）。它们只在帧边界更新一次、然后
    //    稳定保持 16.7 ms，所以平时看不出问题；但只要采到跳变那一拍，
    //    就会拿到"半新半旧"的撕裂值。
    //    ★ 逐比特 2FF **不能**给 32bit 总线提供原子性 —— 它只抑制亚稳态。
    //      正确做法是"数据 + 翻转标志"：
    //        源域：数据更新时同时翻一个 toggle（数据本身已稳定保持）
    //        目的域：对 toggle 做 2FF + 边沿检测，看到翻转后再整组复制
    //      复制时数据在源域已稳定 >= 3 个目的域周期，所有比特都收敛了，
    //      所以整组一定是同一帧的值 ✓
    //
    //  注意：这里和 uart_log_debug 里的"每轮快照"是**两件不同的事**：
    //    这里解决"同一帧的原子性"；UART 里解决"整轮字段互相自洽"。
    //    两个都要有 —— 只做后者会锁存到撕裂值，只做前者则 ITSM/ITSS
    //    仍可能落在不同帧上。
    // =================================================================

    // ---- 组 1a：csi 域 · 抽头 ----
    reg  [1:0] tgl_csi_s;
    reg        tgl_csi_d;
    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tgl_csi_s <= 2'b00;
            tgl_csi_d <= 1'b0;
        end
        else begin
            tgl_csi_s <= {tgl_csi_s[0], S_vib_tap_tgl};
            tgl_csi_d <= tgl_csi_s[1];
        end
    end
    wire upd_csi = tgl_csi_s[1] ^ tgl_csi_d;

    reg  [31:0] c_tap_px, c_tap_lines, c_tap_sum, c_tap_ovf;
    always @(posedge I_sys_clk) begin
        if (upd_csi) begin
            c_tap_px    <= S_vib_tap_px_per_frame;
            c_tap_lines <= {16'd0, S_vib_tap_lines};
            c_tap_sum   <= S_vib_tap_px_sum;
            c_tap_ovf   <= S_vib_tap_ovf;
        end
    end

    // ---- 组 1b：csi 域 · 高斯（和抽头差一行，所以单独一组） ----
    reg  [1:0] tgl_g_s;
    reg        tgl_g_d;
    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tgl_g_s <= 2'b00;
            tgl_g_d <= 1'b0;
        end
        else begin
            tgl_g_s <= {tgl_g_s[0], S_g_tgl};
            tgl_g_d <= tgl_g_s[1];
        end
    end
    wire upd_g = tgl_g_s[1] ^ tgl_g_d;

    reg  [31:0] c_g_px, c_g_lines;
    always @(posedge I_sys_clk) begin
        if (upd_g) begin
            c_g_px    <= S_g_px;
            c_g_lines <= {16'd0, S_g_lines};
        end
    end

    // ---- 组 2：ddr 域 · 帧差 ----
    reg  [1:0] tgl_ddr_s;
    reg        tgl_ddr_d;
    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tgl_ddr_s <= 2'b00;
            tgl_ddr_d <= 1'b0;
        end
        else begin
            tgl_ddr_s <= {tgl_ddr_s[0], S_pf_tgl};
            tgl_ddr_d <= tgl_ddr_s[1];
        end
    end
    wire upd_ddr = tgl_ddr_s[1] ^ tgl_ddr_d;

    reg  [31:0] c_it_px, c_it_lines, c_it_sum, c_it_sgn, c_it_err, c_it_rdy, c_it_state;
    always @(posedge I_sys_clk) begin
        if (upd_ddr) begin
            c_it_px    <= S_it_px;
            c_it_lines <= S_it_lines;
            c_it_sum   <= S_it_sum;
            c_it_sgn   <= S_it_sgn;
            c_it_err   <= S_it_err;
            c_it_rdy   <= S_it_line_rdy;
            c_it_state <= S_it_state;
        end
    end

    // ---- 组 3：ddr 域 · LK 梯度级 ----
    reg  [1:0] tgl_lk_s;
    reg        tgl_lk_d;
    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tgl_lk_s <= 2'b00;
            tgl_lk_d <= 1'b0;
        end
        else begin
            tgl_lk_s <= {tgl_lk_s[0], S_lk_tgl};
            tgl_lk_d <= tgl_lk_s[1];
        end
    end
    wire upd_lk = tgl_lk_s[1] ^ tgl_lk_d;

    reg  signed [31:0] c_lk_axx, c_lk_ayy, c_lk_axy, c_lk_bx, c_lk_by, c_lk_en;
    reg  [31:0]        c_lk_px, c_lk_err;
    reg  [31:0]        c_fx_pos, c_fx_en;
    reg  [7:0]         c_gz_hz10, c_gz_fcnt;
    reg  [4:0]         c_gz_bin;
    reg  [31:0]        c_gz_mag;
    reg  signed [31:0] c_gz_hp, c_gz_in, c_gz_s1;
    reg  signed [31:0] c_fx_bx, c_fx_by;
    reg  signed [32:0] c_fx_tex;
    reg  [7:0]         c_lk_dbg_m0, c_lk_dbg_m1, c_lk_dbg_m2, c_lk_dbg_p0;
    reg  [5:0]         c_lk_dbg_sel;
    reg  [7:0]         c_lk_dbg_pa, c_lk_dbg_pb;
    reg  [31:0]        c_lk_dbg_ae, c_lk_dbg_af;
    reg  [31:0]        c_lk_dbg_xa, c_lk_dbg_xb;
    reg  [7:0]         c_lk_dbg_la, c_lk_dbg_lb, c_lk_dbg_lc;
    reg  [31:0]        c_sv_num_ld;
    reg  [31:0]        c_sv_en;
    always @(posedge I_sys_clk) begin
        if (upd_lk) begin
            c_lk_axx <= S_lk_axx; c_lk_ayy <= S_lk_ayy; c_lk_axy <= S_lk_axy;
            c_lk_bx  <= S_lk_bx;  c_lk_by  <= S_lk_by;  c_lk_en  <= S_lk_en;
            c_lk_px  <= S_lk_px;  c_lk_err <= S_lk_err;
            c_fx_pos <= S_fx_pos; c_fx_en <= S_fx_en;
            c_fx_bx  <= S_fx_bx;  c_fx_by <= S_fx_by;
            c_fx_tex <= S_fx_tex;
            c_gz_bin  <= S_gz_bin;
            c_gz_hz10 <= S_gz_hz10;
            c_gz_fcnt <= S_gz_fcnt;
            // ★ mag² 内部是 64 位，这里取 [39:8] 而不是 [31:0]：
            //   实测量级 mag² ≈ 2.5e6（弱振动）~ 2.5e11（强振动），
            //   32 位只能到 4.3e9，强振动会回绕 → GZMG 反而变小，误判。
            //   [39:8] 覆盖到 5.5e11，且弱振动下仍有 ~1e4 的分辨率。
            c_gz_mag  <= S_gz_mag[39:8];
            c_gz_hp   <= S_gz_hp;
            c_gz_in   <= S_gz_in;
            c_gz_s1   <= S_gz_s1;
            c_lk_dbg_m0 <= S_lk_dbg_m0; c_lk_dbg_m1 <= S_lk_dbg_m1;
            c_lk_dbg_m2 <= S_lk_dbg_m2; c_lk_dbg_p0 <= S_lk_dbg_p0;
            c_lk_dbg_sel <= S_lk_dbg_sel;
            c_lk_dbg_pa <= S_lk_dbg_pa; c_lk_dbg_pb <= S_lk_dbg_pb;
            c_lk_dbg_ae <= S_lk_dbg_ae; c_lk_dbg_af <= S_lk_dbg_af;
            c_lk_dbg_xa <= S_lk_dbg_xa; c_lk_dbg_xb <= S_lk_dbg_xb;
            c_lk_dbg_la <= S_lk_dbg_la; c_lk_dbg_lb <= S_lk_dbg_lb;
            c_lk_dbg_lc <= S_lk_dbg_lc;
        end
    end


    // ---- 组 3b：ddr 域 · 48 块 Goertzel 窗口结果 ----
    reg [1:0] tgl_mb_s;
    reg       tgl_mb_d;
    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tgl_mb_s <= 2'b00;
            tgl_mb_d <= 1'b0;
        end else begin
            tgl_mb_s <= {tgl_mb_s[0], S_pk_done_tgl};
            tgl_mb_d <= tgl_mb_s[1];
        end
    end
    wire upd_mb = tgl_mb_s[1] ^ tgl_mb_d;
    reg [31:0] c_mb_frm, c_mb_hz10, c_mb_mag, c_mb_scan, c_mb_win, c_mb_ticks, c_mb_ntonal;
    reg [31:0] c_mb_obj_pos, c_mb_obj_hz10, c_mb_active;
    reg [31:0] c_mb_agc_ref, c_mb_best_blk, c_mb_streak, c_mb_clr;
    reg [31:0] c_mb_fxbx, c_mb_fxen, c_mb_b2, c_mb_b4, c_mb_b8, c_mb_b12;
    // 频谱、候选和确认诊断随窗口完成 toggle 原子复制。
    reg [47:0]  c_tonal_map;
    reg [127:0] c_obj_pn;
    reg [31:0]  c_chal_blk;
    reg [31:0]  c_fx_pn;
    reg [31:0]  c_qact;
    reg [31:0]  c_raw_bin, c_raw_hz, c_raw_aexp, c_confirmed, c_tn;
    //------------------------------------------------------------------
    //  ★ 2026-10-27：窗口周期计数 —— 用来反推<b>真实帧率</b>
    //    fs = 64 帧 / 周期（周期单位 = I_sys_clk 50MHz 的拍数）
    //    预期值：60 fps -> 53,333,333 = 0x032DCDCD
    //            48 fps -> 66,666,666 = 0x03F9A0A0
    //    系数按 fs=59.5Hz 标定；64*50MHz/WPRD 可核对实际采样率。
    //    频点编码固定为 Hz10=20+5*bin；采样率偏差会影响真实中心频率。
    //    32 位 @50MHz 约 85.9 秒绕一圈，窗口约 1 秒，两次快照之间不会绕。
    //------------------------------------------------------------------
    reg [31:0] wcnt;
    reg [31:0] wcnt_prev, c_wprd;
    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) wcnt <= 32'd0;
        else          wcnt <= wcnt + 32'd1;
    end
    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            c_wprd <= 32'd0;
            wcnt_prev <= 32'd0;
        end else if (upd_mb) begin
            c_wprd    <= wcnt - wcnt_prev;
            wcnt_prev <= wcnt;
        end
    end
    always @(posedge I_sys_clk) begin
        if (upd_mb) begin
            // Goertzel 在窗口完成后会把当前帧计数清零；这里报告刚完成的
            // 64 帧窗口，避免 UART 的 MBFR 永远显示 0。
`ifdef VIB_LEGACY_GZ_ON
            c_mb_frm   <= 32'd128;
`else
            c_mb_frm   <= 32'd64;
`endif
            c_mb_hz10  <= {24'd0, S_pk_hz10};
            c_mb_mag   <= S_pk_bestmag;
            c_mb_scan  <= S_pk_scancnt;
            c_mb_win   <= {24'd0, S_pk_wincnt};
            c_mb_ticks <= S_mb_ticks;
            c_mb_ntonal<= {26'd0, S_pk_ntonal};
            c_qact      <= {26'd0, S_pk_qact};
            c_mb_obj_pos <= S_pk_obj_pos;
            c_mb_obj_hz10 <= S_pk_obj_hz10;
            c_mb_active <= {26'd0, S_pk_ntonal};
            c_mb_agc_ref <= {27'd0, S_mb_agc_ref};
            // PBLK/RBIN/RHZ/AEXP 和 F04/F06/F08/F10 均指本窗口全局 raw 最强块。
            c_mb_best_blk <= {26'd0, S_pk_bestblk};
            c_raw_bin  <= {27'd0, S_pk_bestbin};
            c_raw_hz   <= S_pk_raw_hz;
            c_raw_aexp <= {27'd0, S_pk_aexp};
            c_confirmed<= {29'd0, S_pk_confirmed};
            c_tn       <= S_pk_tn;
            c_mb_streak <= {20'd0, S_pk_streak};
            c_mb_clr <= S_mb_clrcnt;
            c_tonal_map <= S_pk_tonal_map;
            c_obj_pn    <= S_pk_obj_pn;
            c_chal_blk  <= {26'd0, S_pk_chal_blk};
            c_fx_pn     <= S_pk_fx_pn;
            c_mb_fxbx <= S2_fx_bx;
            c_mb_fxen <= S2_fx_en;
            c_mb_b2   <= S_pk_fb2;
            c_mb_b4   <= S_pk_fb4;
            c_mb_b8   <= S_pk_fb8;
            c_mb_b12  <= S_pk_fb12;
        end
    end


    // ---- 组 4：ddr 域 · 2x2 求解结果 ----
    reg  [1:0] tgl_sv_s;
    reg        tgl_sv_d;
    always @(posedge I_sys_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            tgl_sv_s <= 2'b00;
            tgl_sv_d <= 1'b0;
        end
        else begin
            tgl_sv_s <= {tgl_sv_s[0], S_sv_tgl};
            tgl_sv_d <= tgl_sv_s[1];
        end
    end
    wire upd_sv = tgl_sv_s[1] ^ tgl_sv_d;

    reg  signed [31:0] c_sv_u, c_sv_v;
    reg  [2:0]         c_sv_bcol, c_sv_brow;
    reg  [31:0]        c_sv_itsm;   // 与本帧最大块同帧的 ITSM（帧末锁存）
    reg  [31:0]        c_sv_det_h, c_sv_num_h, c_sv_quot;
    reg                c_sv_nu_neg;
    reg  [31:0]        c_sv_den_h, c_sv_rem_h;
    reg                c_sv_valid;
    always @(posedge I_sys_clk) begin
        if (upd_sv) begin
            c_sv_u     <= S_sv_u;
            c_sv_v     <= S_sv_v;
            c_sv_itsm  <= S_lk_b_itsm;
            c_sv_det_h <= S_sv_det_h;
            c_sv_num_h <= S_sv_num_h;
            c_sv_quot  <= S_sv_quot;
            c_sv_nu_neg<= S_sv_nu_neg;
            c_sv_den_h <= S_sv_den_h;
            c_sv_rem_h <= S_sv_rem_h;
            c_sv_num_ld <= S_sv_num_ld;
            c_sv_en     <= S_sv_en;
            c_sv_bcol  <= S_sv_bcol;
            c_sv_brow  <= S_sv_brow;
            c_sv_valid <= S_sv_valid;
        end
    end
    // =================================================================
    //  串口日志
    //    内容  : 见 uart_log_debug.v 文件头说明
    //    复位  : 用 I_rst_n，这样 PLL 还没锁的时候串口就已经在打印了
    //    ★ 统计量一律接上面的 c_* 原子快照，不接源域原始信号
    // =================================================================
    uart_log_debug #(
        .CLK_HZ (50_000_000),
        .BAUD   (115200)
    ) u_uart_log_debug (
        .clk                (I_sys_clk),
        .rst_n              (I_rst_n),
        .pll_lock           (S_pll_lock),
        .ddr_init_done      (S_init_calib_complete),
        .cam_cfg_done       (S_dbg_cam_cfg_seen),
        .cam_i2c_error      (S_cam_i2c_error),
        .sensor_id          (S_cam_sensor_id),
        .sensor_id_ok       (S_cam_sensor_id_ok),
        .mipi_diag_status   (S_mipi_diag_status_async),
        .hs_seen            (S_dbg_hs_seen),
        .csi_frame_seen     (S_dbg_csi_seen),
        .raw10_seen         (S_dbg_raw10_seen),
        .video_nonzero_seen (S_dbg_video_nonzero_seen),
        .tap_px_per_frame    (c_tap_px),
        .tap_lines           (c_tap_lines),
        .it_px               (c_it_px),
        .it_lines            (c_it_lines),
        .vsum                (c_tap_sum),
        .mb_frm              (c_mb_frm),
        .mb_active           (c_mb_active),
        .mb_obj_hz10         (c_mb_obj_hz10),
        .mb_agc_ref          (c_mb_agc_ref),
        .mb_best_blk         (c_mb_best_blk),
        .mb_streak           (c_mb_streak),
        .mb_clr              (c_mb_clr),
        .mb_mag              (c_mb_mag),
        .fx_bx               (c_mb_fxbx),
        .fx_en               (c_mb_fxen),
        .b2                  (c_mb_b2),
        .b4                  (c_mb_b4),
        .b8                  (c_mb_b8),
        .b12                 (c_mb_b12),
        .tonal_map_lo        (c_tonal_map[31:0]),
        .tonal_map_hi        ({16'd0, c_tonal_map[47:32]}),
        .obj_pos             (c_mb_obj_pos),
        .fx_pn               (c_fx_pn),
        .obj_pn0             (c_obj_pn[31:0]),
        .obj_pn1             (c_obj_pn[63:32]),
        .obj_pn2             (c_obj_pn[95:64]),
        .obj_pn3             (c_obj_pn[127:96]),
        .chal_blk            (c_chal_blk),
        .qact                (c_qact),
        .wprd                (c_wprd),
        .tap_ovf             (c_tap_ovf),
        .it_err              (c_it_err),
        .mb_scan             (c_mb_scan),
        .mb_win              (c_mb_win),
        .raw_bin             (c_raw_bin),
        .raw_hz              (c_raw_hz),
        .raw_aexp            (c_raw_aexp),
        .confirmed           (c_confirmed),
        .tn_status           (c_tn),
        .tx                 (O_uart_tx)
    );

endmodule
