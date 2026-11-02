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
// 融合版的唯一曝光入口：KEY4控制自动曝光，增益固定为G12。
// 关闭自动曝光恢复E900，SW5只属于显示端补亮，不改变传感器参数。
// 请求值与已生效值分离，后者只在真实组写及生效等待完成后发布。
(* dsp_style = "no" *)
module fusion_exposure_control (
    input  wire        I_clk,
    input  wire        I_rst,
    input  wire        I_auto_en,
    input  wire        I_freeze,
    input  wire [5:0]  I_measure,
    input  wire        I_measure_valid,
    input  wire        I_ae_cfg_done,
    input  wire        I_cam_cfg_done,
    output reg         O_ae_req = 1'b0,
    output reg [15:0]   O_ae,
    output reg [15:0]   O_ag,
    output reg         O_auto_applied,
    output wire        O_pending,
    output reg         O_valid,
    output reg [15:0]   O_applied_exposure,
    output wire        O_exposure_valid
);
    localparam [15:0] FIXED_EXPOSURE = 16'd900;
    localparam [15:0] FIXED_GAIN = 16'd128;
    localparam [15:0] AUTO_MIN = 16'd128;
    localparam [15:0] AUTO_MAX = 16'd1991;
    reg in_flight, saw_busy, requested_auto;
    reg measure_seen;
    reg [3:0] last_sequence;
    reg freeze_d;
    reg [1:0] settle_frames;
    reg [1:0] last_direction;
    reg direction_seen;
    wire new_measure = I_measure_valid &&
                       (!measure_seen || I_measure[5:2] != last_sequence);
    wire [15:0] step = (O_ae < 16'd16) ? 16'd1 : (O_ae >> 4);
    wire [15:0] raised = O_ae + step;
    wire [15:0] lowered = O_ae - step;
    wire [15:0] next_exposure = (I_measure[1:0] == 2'b01) ?
                ((raised > AUTO_MAX) ? AUTO_MAX : raised) :
                ((lowered < AUTO_MIN) ? AUTO_MIN : lowered);

    assign O_pending = in_flight || !O_valid || !I_cam_cfg_done ||
                       (O_auto_applied != I_auto_en);
    // 保留最近生效E，但参数在途、模式切换及冻结时不得采信新场景统计。
    assign O_exposure_valid = O_valid && !O_pending &&
                              !I_freeze && !freeze_d && I_cam_cfg_done;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            O_ae_req <= 1'b0;
            O_ae <= 16'd1990;
            O_ag <= 16'd17;
            O_auto_applied <= 1'b0;
            O_valid <= 1'b0;
            O_applied_exposure <= 16'd0;
            in_flight <= 1'b0;
            saw_busy <= 1'b0;
            requested_auto <= 1'b0;
            measure_seen <= 1'b0;
            last_sequence <= 0;
            freeze_d <= 1'b0;
            settle_frames <= 2'd3;
            last_direction <= 0;
            direction_seen <= 0;
        end else begin
            O_ae_req <= 1'b0;
            freeze_d <= I_freeze;
            // 写入和冻结期间仍消费序号，防止旧帧稍后变成新的反馈。
            if (new_measure) begin
                measure_seen <= 1'b1;
                last_sequence <= I_measure[5:2];
            end
            if (I_freeze || freeze_d || !I_auto_en) begin
                settle_frames <= 2'd3;
                direction_seen <= 0;
            end
            if (in_flight) begin
                direction_seen <= 0;
                if (!I_ae_cfg_done) begin
                    saw_busy <= 1'b1;
                end else if (saw_busy && I_cam_cfg_done) begin
                    O_auto_applied <= requested_auto;
                    O_applied_exposure <= O_ae;
                    O_valid <= 1'b1;
                    in_flight <= 1'b0;
                    saw_busy <= 1'b0;
                    settle_frames <= 2'd3;
                end
            end else if (I_cam_cfg_done && I_ae_cfg_done &&
                         (!O_valid || O_auto_applied != I_auto_en)) begin
                // 初始化和模式归一化允许在冻结时完成，暂停的是自主调整。
                O_ae <= FIXED_EXPOSURE;
                O_ag <= FIXED_GAIN;
                requested_auto <= I_auto_en;
                O_ae_req <= 1'b1;
                O_valid <= 1'b0;
                in_flight <= 1'b1;
                saw_busy <= 1'b0;
                direction_seen <= 0;
                settle_frames <= 2'd3;
            end else if (I_cam_cfg_done && I_ae_cfg_done && O_valid &&
                         I_auto_en && O_auto_applied &&
                         !I_freeze && !freeze_d && new_measure) begin
                if (settle_frames != 0) begin
                    settle_frames <= settle_frames - 1'b1;
                    direction_seen <= 0;
                end else if (I_measure[1:0] == 2'b01 || I_measure[1:0] == 2'b10) begin
                    if (direction_seen && last_direction == I_measure[1:0]) begin
                        direction_seen <= 0;
                        // 到达边界只消费反馈，避免反复重写同一参数组。
                        if (next_exposure != O_ae) begin
                            O_ae <= next_exposure;
                            O_ag <= FIXED_GAIN;
                            requested_auto <= 1'b1;
                            O_ae_req <= 1'b1;
                            O_valid <= 1'b0;
                            in_flight <= 1'b1;
                            saw_busy <= 1'b0;
                        end
                    end else begin
                        direction_seen <= 1'b1;
                        last_direction <= I_measure[1:0];
                    end
                end else begin
                    direction_seen <= 0;
                end
            end
        end
    end
endmodule
