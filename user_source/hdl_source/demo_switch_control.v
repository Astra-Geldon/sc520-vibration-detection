`ifndef DEMO_SWITCH_CONTROL_V
`define DEMO_SWITCH_CONTROL_V
// Five stable mechanical switches. One shared quiet-window counter avoids
// five full-width timers; a new vector is published only after all bits settle.
module demo_switch_debounce #(
    parameter integer DEBOUNCE_CYCLES = 500000
)(
    input wire I_clk, input wire I_rst_n,
    input wire [4:0] I_async,
    output reg [4:0] O_state,
    output reg O_valid
);
    localparam integer CW = (DEBOUNCE_CYCLES < 2) ? 1 : $clog2(DEBOUNCE_CYCLES);
    reg [4:0] sync1, sync2, candidate;
    reg [CW-1:0] count;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sync1 <= 5'b11111; sync2 <= 5'b11111;
            candidate <= 5'b11111; O_state <= 5'b11111;
            count <= 0; O_valid <= 1'b0;
        end else begin
            sync1 <= I_async; sync2 <= sync1;
            if (candidate != sync2) begin
                candidate <= sync2; count <= 0;
            end else if (count == DEBOUNCE_CYCLES - 1) begin
                O_state <= candidate; O_valid <= 1'b1;
            end else count <= count + 1'b1;
        end
    end
endmodule

// Bundled-data mailbox. The source holds its payload unchanged until the
// destination commits it at I_dst_apply and returns its toggle acknowledgment.
// Intermediate user requests may coalesce, but the latest stable value is sent
// after acknowledgment. This is not an independently synchronized data bus.
module demo_control_cdc #(
    parameter integer WIDTH = 5,
    parameter [WIDTH-1:0] INITIAL = {WIDTH{1'b1}}
)(
    input wire I_src_clk, input wire I_src_rst_n,
    input wire [WIDTH-1:0] I_src_data, input wire I_src_valid,
    input wire I_dst_clk, input wire I_dst_rst_n, input wire I_dst_apply,
    output reg [WIDTH-1:0] O_dst_data, output reg O_dst_valid
);
    reg [WIDTH-1:0] payload;
    reg request, acknowledge, sent;
    reg [1:0] acknowledge_sync, request_sync;
    always @(posedge I_src_clk or negedge I_src_rst_n) begin
        if (!I_src_rst_n) begin
            payload <= INITIAL; request <= 0; sent <= 0;
            acknowledge_sync <= 0;
        end else begin
            acknowledge_sync <= {acknowledge_sync[0], acknowledge};
            if (I_src_valid && (request == acknowledge_sync[1]) &&
                (!sent || I_src_data != payload)) begin
                payload <= I_src_data;
                request <= ~request; sent <= 1'b1;
            end
        end
    end
    always @(posedge I_dst_clk or negedge I_dst_rst_n) begin
        if (!I_dst_rst_n) begin
            request_sync <= 0; acknowledge <= 0;
            O_dst_data <= INITIAL; O_dst_valid <= 0;
        end else begin
            request_sync <= {request_sync[0], request};
            if (I_dst_apply && (request_sync[1] != acknowledge)) begin
                O_dst_data <= payload; O_dst_valid <= 1'b1;
                acknowledge <= request_sync[1];
            end
        end
    end
endmodule
`endif
