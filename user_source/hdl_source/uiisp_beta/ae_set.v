/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/
/*********ae_set �ֶ��������AE ***********
--�汾��1.0
*********************************************************************/

module ae_set
(
input wire I_clk,
input wire I_rst,
input wire [3:0]I_btn,
input wire [1:0]I_exp_sel,
input wire I_ae_cfg_done,
input wire I_cam_cfg_done,
output wire O_ae_req,
output wire [15:0] O_ae,
output wire [15:0] O_ag
);
	

reg 	[19:0] 	rc_ae_tick = 0; 
reg 			r_ae_tick = 0; 
reg 	[4:0] 	rc_ag_tick = 0; 
reg 			r_ag_tick = 0; 
	reg [1:0] r_exp_sync1 = 0, r_exp_sync2 = 0, r_exp_sync_d = 0;
	
always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		rc_ae_tick <= 0; 
		r_ae_tick <= 0; 
		rc_ag_tick <= 0; 
		r_ag_tick <= 0; 
	end else begin
	//	Trigger AE Inc / Dec per 1 ms. 
		rc_ae_tick <= rc_ae_tick + 1; 
		r_ae_tick <= 0; 
		if(rc_ae_tick >= 99999) begin
			rc_ae_tick <= 0; 
			r_ae_tick <= 1; 
		end 
	//	Trigger AG Inc / Dec per 32 ms. 
		rc_ag_tick <= rc_ag_tick + r_ae_tick; 
		r_ag_tick <= (&rc_ag_tick) && r_ae_tick; 
	end
end

// KEY3 在 HDMI 像素时钟域产生曝光档位；这里用两级同步，按键变化很慢，
// 每次档位变化只触发一次新的传感器曝光写入。
always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		r_exp_sync1 <= 2'd0;
		r_exp_sync2 <= 2'd0;
		r_exp_sync_d <= 2'd0;
	end else begin
		r_exp_sync1 <= I_exp_sel;
		r_exp_sync2 <= r_exp_sync1;
		r_exp_sync_d <= r_exp_sync2;
	end
end

function [15:0] f_exp_value;
	input [1:0] sel;
	begin
		case(sel)
			2'd0: f_exp_value = 16'd1991;
			2'd1: f_exp_value = 16'd1600;
			2'd2: f_exp_value = 16'd1200;
			default: f_exp_value = 16'd900;
		endcase
	end
endfunction
	
//	Use button to add / sub idelay values. I_button[0]:IncDatDly, [1]DecDatDly, [2]IncI_clkDly, [3]DecI_clkDly
reg 	[3:0] 	r_button_0 = 0, r_button_1 = 0; 
// 原厂720p60模式VTS=1000，曝光以半行计，最大值为2*VTS-9=1991。
// 2026-10-30 阶段1候选：曝光 1991 -> 1600（降约 20%）。
//   该值只改变传感器曝光寄存器默认值；AWB、shading、视频时序和按键调节逻辑保持原样。
//   ★ 为什么改曝光而不是改增益
//     实测把 r_ag_set 从 160 改到 151，亮度 137.3 -> 136.9（几乎没变），
//     SC520GainTbl 里 151/160 对应 0x3e07 = 0x9C/0xC0（数字 fine gain），
//     但实际亮度完全不动 -> 说明该 fine gain 寄存器写入没有生效。
//     而曝光时间 0x3e00~0x3e02 是每帧都要重写的，改动必然生效。
//   ★ 为什么需要降
//     增益 160 时平均亮度 137，约 16% 的像素 R+G+B>=720 被 AWB 的过曝过滤排除；
//     被排除的恰是最亮的高光（暖白，本身偏红），剩余样本偏绿 -> gain_r 偏大
//     -> 白墙偏红。实测统计样本 50~70% 的帧白墙G/R=0.866（偏红13%），
//     样本 95%+ 的帧白墙G/R=0.986（中性）。降到 1600 后亮度约 110，
//     过曝大幅减少，统计样本变全，白墙应回到中性。
// 2026-10-24：增益 144 -> 151（约 1.35 倍模拟增益）。
//   曝光 1991 已在硬件上限（720p60 下约 1/60s，整帧曝光），画面暗是因为
//   晚上教室环境光不足，只能靠模拟增益补。
//
//   ★ 为什么不是 160（最初选的）
//     实测视频发现：增益 160 时平均亮度 137，大量像素 R+G+B>=720 被 AWB 的
//     过曝过滤排除。而被排除的恰恰是「最亮的高光」（暖白，本身偏红），
//     导致剩余统计样本偏绿 -> gain_r 偏大 -> 过度提 R -> 白墙偏红。
//     数据：统计样本 50~70% 的帧 白墙G/R=0.866（偏红13%）；
//           统计样本 95%+ 的帧 白墙G/R=0.986（中性）。
//   151 约让平均亮度回到 121，此时绝大多数帧统计样本 >95%，白墙回到中性。
//   同时高光过曝也减轻（用户反馈白色监控和墙面分不开）。
reg 	[15:0] 	r_ae_set = 1600, r_ag_set = 160; 
always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		r_button_0 <= 0; 
		r_button_1 <= 0; 
		r_ae_set <= 1600; 
		r_ag_set <= 160; 
	end else begin
	//	When button pressed, r_button_1 bit is 1. 
		r_button_0 <= ~I_btn; 
		r_button_1 <= r_button_0; 
	
		if(r_exp_sync2 != r_exp_sync_d) begin
			r_ae_set <= f_exp_value(r_exp_sync2);
		end else if(r_button_1[0]) begin
			r_ae_set <= (r_ae_set > 2) ? r_ae_set - r_ae_tick : r_ae_set; 
		end else if(r_button_1[1]) begin
			r_ae_set <= (r_ae_set < 1991) ? r_ae_set + r_ae_tick : r_ae_set; 
		end 
		if(r_button_1[2]) begin
				r_ag_set <= (r_ag_set > 16) ? r_ag_set - r_ag_tick : r_ag_set; 
		end else if(r_button_1[3]) begin
				r_ag_set <= (r_ag_set < 176) ? r_ag_set + r_ag_tick : r_ag_set; 
		end 
		end
	end
	
//	Update AG / AE when changed. 
reg 	[15:0] 	r_ae ; 
reg 	[15:0] 	r_ag ; 
reg 			r_ae_req = 0; //synthesis keep
assign O_ae = r_ae;
assign O_ag = r_ag;
assign O_ae_req = r_ae_req;

always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		r_ae_req <= 0; 
		r_ae     <= 1990; 
		// Start from a value different from r_ag_set.  This deliberately
		// causes one grouped AE/AG write after the sensor setting completes;
		// otherwise the requested default gain would never reach SC520CS.
		r_ag     <= 17; 
	end else if(r_ae_req) begin
		r_ae_req <= 0; 
	end else if(((r_ae != r_ae_set) || (r_ag != r_ag_set))&&(I_cam_cfg_done==1'b1)&&(I_ae_cfg_done==1'b1)) begin
		r_ae     <= r_ae_set; 
		r_ag     <= r_ag_set; 
		r_ae_req <= 1; 
	end
end


endmodule


	
