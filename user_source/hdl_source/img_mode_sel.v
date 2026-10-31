// Normal image modes only. Exposure/gain and the N1 curve are fixed in the
// production image; KEY3/KEY4 have no experiment logic in this module.
// KEY1 (D5): enhanced colour. KEY2 (A9): gray -> binary -> Sobel -> gray.
// Active-low keys retain two-stage synchronization and 10ms debounce.
module img_mode_sel #(
    parameter integer MODE_RST = 0,
    parameter integer CLK_HZ = 75000000,
    parameter integer DB_MS = 10
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire [1:0] I_key_n,
    output reg [2:0] O_mode
);
    localparam integer CNT_MAX = (CLK_HZ / 1000) * DB_MS;
    localparam integer CNT_W = 20;
    localparam [2:0] RST3 = MODE_RST;
    wire [1:0] S_press;

    genvar gi;
    generate
        for (gi = 0; gi < 2; gi = gi + 1) begin : g_key
            reg [1:0] S_sync;
            reg [CNT_W-1:0] S_cnt;
            reg S_level, S_level_d;
            wire S_key_n = S_sync[1];
            always @(posedge I_clk or negedge I_rst_n) begin
                if (!I_rst_n) S_sync <= 2'b11;
                else S_sync <= {S_sync[0], I_key_n[gi]};
            end
            always @(posedge I_clk or negedge I_rst_n) begin
                if (!I_rst_n) begin
                    S_cnt <= {CNT_W{1'b0}};
                    S_level <= 1'b1;
                    S_level_d <= 1'b1;
                end else begin
                    S_level_d <= S_level;
                    if (S_key_n != S_level) begin
                        if (S_cnt == CNT_MAX) begin
                            S_level <= S_key_n;
                            S_cnt <= {CNT_W{1'b0}};
                        end else S_cnt <= S_cnt + 1'b1;
                    end else S_cnt <= {CNT_W{1'b0}};
                end
            end
            assign S_press[gi] = S_level_d & ~S_level;
        end
    endgenerate

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) O_mode <= RST3;
        else if (S_press[0]) O_mode <= 3'd0;
        else if (S_press[1]) begin
            if (O_mode == 3'd1) O_mode <= 3'd2;
            else if (O_mode == 3'd2) O_mode <= 3'd3;
            else O_mode <= 3'd1;
        end
    end
endmodule
