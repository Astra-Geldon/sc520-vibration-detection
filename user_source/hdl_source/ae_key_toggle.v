// Active-low K3. Debounced level changes generate one toggle per press.
// A key held at reset must be released before it can toggle the default state.
module ae_key_toggle #(
    parameter integer DEBOUNCE_CYCLES = 500000,
    parameter DEFAULT_ENABLE = 1'b1
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire I_key_n,
    output reg O_enable
);
    localparam integer COUNT_W = (DEBOUNCE_CYCLES <= 1) ? 1 : $clog2(DEBOUNCE_CYCLES);
    (* async_reg = "true", preserve = "true" *) reg key_meta;
    (* async_reg = "true", preserve = "true" *) reg key_sync;
    reg stable_key;
    reg [COUNT_W-1:0] debounce_count;
    reg release_armed;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            key_meta <= 1'b0;
            key_sync <= 1'b0;
            stable_key <= 1'b0;
            debounce_count <= 0;
            release_armed <= 1'b0;
            O_enable <= DEFAULT_ENABLE;
        end else begin
            key_meta <= I_key_n;
            key_sync <= key_meta;
            if (key_sync == stable_key) begin
                debounce_count <= 0;
            end else if (DEBOUNCE_CYCLES <= 1 || debounce_count == DEBOUNCE_CYCLES-1) begin
                debounce_count <= 0;
                stable_key <= key_sync;
                if (key_sync) begin
                    release_armed <= 1'b1;
                end else if (release_armed) begin
                    O_enable <= ~O_enable;
                    release_armed <= 1'b0;
                end
            end else begin
                debounce_count <= debounce_count + 1'b1;
            end
        end
    end
endmodule
