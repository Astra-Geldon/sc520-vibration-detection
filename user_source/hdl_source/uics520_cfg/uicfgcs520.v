`timescale 1ns / 1ps

module uicfgcs520 #(
    parameter integer CLK_DIV = 16'd239,
    parameter integer AE_VERIFY_EN = 0
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_ae_req,
    input  wire [15:0] I_ae,
    input  wire [15:0] I_ag,
    output wire        O_cam_scl,
    inout  wire        IO_cam_sda,
    output reg         O_cfg_done,
    output reg         O_ae_cfg_done,
    output reg  [15:0] O_sensor_id,
    output reg         O_sensor_id_ok,
    output reg         O_iic_error,
    output reg  [1:0]  O_gain_sel_gray,
    output reg         O_gain_verified
);
    localparam [7:0] CAM_ID = 8'h6c;

    localparam [3:0] ST_IDH_REQ  = 4'd0;
    localparam [3:0] ST_IDH_BUSY = 4'd1;
    localparam [3:0] ST_IDH_DONE = 4'd2;
    localparam [3:0] ST_IDL_REQ  = 4'd3;
    localparam [3:0] ST_IDL_BUSY = 4'd4;
    localparam [3:0] ST_IDL_DONE = 4'd5;
    localparam [3:0] ST_CHECK_ID = 4'd6;
    localparam [3:0] ST_IDLE     = 4'd7;
    localparam [3:0] ST_WR_REQ   = 4'd8;
    localparam [3:0] ST_WR_BUSY  = 4'd9;
    localparam [3:0] ST_WR_DONE  = 4'd10;
    localparam [3:0] ST_ERROR    = 4'd11;
    localparam [3:0] ST_RESET_WAIT = 4'd12;
    localparam [3:0] ST_AE_RD_REQ  = 4'd13;
    localparam [3:0] ST_AE_RD_BUSY = 4'd14;
    localparam [3:0] ST_AE_RD_DONE = 4'd15;
    localparam integer RESET_WAIT_CYCLES = 119048; // 5 ms at 23.809524 MHz
    // SC520CS: a group written in frameN affects frameN+2.  At60fps,
    // 50ms spans at least that update window before verification.
    localparam integer AE_SETTLE_CYCLES = 1190477;

    reg  [3:0]  state;
    reg         iic_req;
    reg         iic_mode;
    reg  [7:0]  wr_cnt;
    reg  [7:0]  rd_cnt;
    reg  [31:0] wr_data;
    reg  [8:0]  reg_index;
    reg  [20:0] reset_wait_cnt;
    reg         ae_table_active;
    wire        iic_busy;
    wire        iic_bus_error;
    wire [7:0]  rd_data;

    wire [23:0] init_reg_data;
    wire [8:0]  init_reg_size;
    wire [23:0] ae_reg_data;
    wire [8:0]  ae_reg_size;
    wire [23:0] gain_value;
    wire [23:0] selected_reg_data = ae_table_active ? ae_reg_data : init_reg_data;
    wire [8:0]  selected_reg_size = ae_table_active ? ae_reg_size : init_reg_size;
    // Datasheet-defined exposure fields; reserved bits are not requested data.
    wire [7:0] verify_mask = (reg_index == 9'd1) ? 8'h0f :
                             (reg_index == 9'd3) ? 8'hf0 : 8'hff;
    wire verify_match = ((rd_data & verify_mask) == (ae_reg_data[7:0] & verify_mask));

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state            <= ST_IDH_REQ;
            iic_req          <= 1'b0;
            iic_mode         <= 1'b1;
            wr_cnt           <= 8'd3;
            rd_cnt           <= 8'd1;
            wr_data          <= 32'd0;
            reg_index        <= 9'd0;
            reset_wait_cnt   <= 21'd0;
            ae_table_active  <= 1'b0;
            O_cfg_done       <= 1'b0;
            O_ae_cfg_done    <= 1'b0;
            O_sensor_id      <= 16'd0;
            O_sensor_id_ok   <= 1'b0;
            O_iic_error      <= 1'b0;
            O_gain_sel_gray  <= 2'b00;
            O_gain_verified  <= 1'b0;
        end else begin
            if (iic_bus_error) begin
                O_iic_error <= 1'b1;
                O_gain_verified <= 1'b0;
            end

            case (state)
                ST_IDH_REQ: if (!iic_busy) begin
                    wr_data <= {8'h00, 8'h07, 8'h31, CAM_ID};
                    wr_cnt <= 8'd3;
                    rd_cnt <= 8'd1;
                    iic_mode <= 1'b1;
                    iic_req <= 1'b1;
                    state <= ST_IDH_BUSY;
                end
                ST_IDH_BUSY: if (iic_busy) begin
                    iic_req <= 1'b0;
                    state <= ST_IDH_DONE;
                end
                ST_IDH_DONE: if (!iic_busy) begin
                    O_sensor_id[15:8] <= rd_data;
                    state <= ST_IDL_REQ;
                end
                ST_IDL_REQ: if (!iic_busy) begin
                    wr_data <= {8'h00, 8'h08, 8'h31, CAM_ID};
                    wr_cnt <= 8'd3;
                    rd_cnt <= 8'd1;
                    iic_mode <= 1'b1;
                    iic_req <= 1'b1;
                    state <= ST_IDL_BUSY;
                end
                ST_IDL_BUSY: if (iic_busy) begin
                    iic_req <= 1'b0;
                    state <= ST_IDL_DONE;
                end
                ST_IDL_DONE: if (!iic_busy) begin
                    O_sensor_id[7:0] <= rd_data;
                    state <= ST_CHECK_ID;
                end
                ST_CHECK_ID: begin
                    if ((O_sensor_id == 16'hee4b) ||
                        (O_sensor_id == 16'h9e4b)) begin
                        O_sensor_id_ok <= 1'b1;
                        reg_index <= 9'd0;
                        ae_table_active <= 1'b0;
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_ERROR;
                    end
                end
                ST_IDLE: begin
                    if (!O_cfg_done) begin
                        if (reg_index == init_reg_size) begin
                            O_cfg_done <= 1'b1;
                            O_ae_cfg_done <= 1'b1;
                        end else begin
                            state <= ST_WR_REQ;
                        end
                    end else if (ae_table_active) begin
                        if (reg_index == ae_reg_size) begin
                            if (AE_VERIFY_EN != 0) begin
                                // Reuse entries1..6 for addresses and expected data.
                                // Keep the request held until all reads complete.
                                reg_index <= 9'd1;
                                reset_wait_cnt <= 21'd0;
                                state <= ST_RESET_WAIT;
                            end else begin
                                ae_table_active <= 1'b0;
                                O_ae_cfg_done <= 1'b1;
                            end
                        end else begin
                            state <= ST_WR_REQ;
                        end
                    end else if (I_ae_req) begin
                        ae_table_active <= 1'b1;
                        O_ae_cfg_done <= 1'b0;
                        O_gain_verified <= 1'b0;
                        reg_index <= 9'd0;
                    end
                end
                ST_WR_REQ: if (!iic_busy) begin
                    // Verified falls at request acceptance, at least one
                    // 24MHz source cycle before the new label is published.
                    // A queued request may skip a Gray position; the bundled
                    // status/data settling interval, not Gray alone, matters.
                    if (ae_table_active && (reg_index == 9'd0)) begin
                        case (I_ag)
                            16'd160: O_gain_sel_gray <= 2'b00;
                            16'd144: O_gain_sel_gray <= 2'b01;
                            16'd112: O_gain_sel_gray <= 2'b11;
                            default: O_gain_sel_gray <= 2'b10;
                        endcase
                    end
                    wr_data[7:0]   <= CAM_ID;
                    wr_data[15:8]  <= selected_reg_data[23:16];
                    wr_data[23:16] <= selected_reg_data[15:8];
                    wr_data[31:24] <= selected_reg_data[7:0];
                    wr_cnt <= 8'd4;
                    rd_cnt <= 8'd0;
                    iic_mode <= 1'b0;
                    iic_req <= 1'b1;
                    state <= ST_WR_BUSY;
                end
                ST_WR_BUSY: if (iic_busy) begin
                    iic_req <= 1'b0;
                    state <= ST_WR_DONE;
                end
                ST_WR_DONE: if (!iic_busy) begin
                    reg_index <= reg_index + 1'b1;
                    if (!ae_table_active && (reg_index == 9'd0)) begin
                        reset_wait_cnt <= 21'd0;
                        state <= ST_RESET_WAIT;
                    end else begin
                        state <= ST_IDLE;
                    end
                end
                ST_RESET_WAIT: begin
                    if (reset_wait_cnt == ((ae_table_active && (AE_VERIFY_EN != 0)) ?
                                           AE_SETTLE_CYCLES - 1 : RESET_WAIT_CYCLES - 1)) begin
                        state <= (ae_table_active && (AE_VERIFY_EN != 0)) ? ST_AE_RD_REQ : ST_IDLE;
                    end else begin
                        reset_wait_cnt <= reset_wait_cnt + 1'b1;
                    end
                end
                ST_AE_RD_REQ: if (!iic_busy) begin
                    // Same address ordering as the proven sensor-ID reads.
                    wr_data <= {8'h00, ae_reg_data[15:8], ae_reg_data[23:16], CAM_ID};
                    wr_cnt <= 8'd3;
                    rd_cnt <= 8'd1;
                    iic_mode <= 1'b1;
                    iic_req <= 1'b1;
                    state <= ST_AE_RD_BUSY;
                end
                ST_AE_RD_BUSY: if (iic_busy) begin
                    iic_req <= 1'b0;
                    state <= ST_AE_RD_DONE;
                end
                ST_AE_RD_DONE: if (!iic_busy) begin
                    if (!verify_match)
                        O_iic_error <= 1'b1;
                    if (reg_index == 9'd6) begin
                        ae_table_active <= 1'b0;
                        O_ae_cfg_done <= 1'b1;
                        O_gain_verified <= !O_iic_error && !iic_bus_error &&
                                           verify_match;
                        state <= ST_IDLE;
                    end else begin
                        reg_index <= reg_index + 1'b1;
                        state <= ST_AE_RD_REQ;
                    end
                end
                ST_ERROR: begin
                    iic_req <= 1'b0;
                    O_cfg_done <= 1'b0;
                    O_ae_cfg_done <= 1'b0;
                    O_gain_verified <= 1'b0;
                end
                default: state <= ST_ERROR;
            endcase
        end
    end

    uii2c #(
        .WMEN_LEN(4),
        .RMEN_LEN(1),
        .CLK_DIV(CLK_DIV)
    ) u_i2c (
        .I_clk(I_clk),
        .I_rstn(I_rst_n),
        .O_iic_scl(O_cam_scl),
        .IO_iic_sda(IO_cam_sda),
        .I_wr_data(wr_data),
        .I_wr_cnt(wr_cnt),
        .O_rd_data(rd_data),
        .I_rd_cnt(rd_cnt),
        .I_iic_req(iic_req),
        .I_iic_mode(iic_mode),
        .O_iic_busy(iic_busy),
        .O_iic_bus_error(iic_bus_error),
        .IO_iic_sda_dg()
    );

    // SC520CS true 1280x720@60 mode.  This test keeps the factory 0x89 table
    // but clears register 0x3222 to verify Free-run operation.
    uics520reg_720p60 u_init_regs (
        .REG_INDEX(reg_index),
        .REG_DATA(init_reg_data),
        .REG_SIZE(init_reg_size)
    );

    SC520GainTbl u_gain (
        .I_AG(I_ag),
        .O(gain_value)
    );

    uics520regAE u_ae_regs (
        .REG_INDEX(reg_index),
        .REG_DATA(ae_reg_data),
        .REG_SIZE(ae_reg_size),
        .I_AE(I_ae),
        .I_AG(gain_value)
    );
endmodule
