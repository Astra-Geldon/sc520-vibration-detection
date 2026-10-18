//=============================================================================
//  vib_div_serial.v  ——  48/32 串行恢复余数除法器（Verilog-2001）
//
//  为什么用串行：
//    振动算法一帧只做 2 次除法（u = nu/det、v = nv/det）。
//    帧周期 16.7 ms @74.43 MHz ≈ 124 万个时钟，48 拍一次只占 0.008%。
//    之前照抄 AWB 的厂商 divider（PIPLE=50 全流水）实测占掉
//    1127 logic + 1084 ripple + 2806 FF ≈ 5017 个 SLICE，
//    而它的 50 级流水 98% 的时间是空闲的 —— 这是选型错误。
//
//  算法（与 model_serial_div.py 逐行对应，已用穷举+15 万组随机验证）：
//      rem = 0;  quot = numer
//      每拍: (rem, quot) 一起左移一位（numer 的 MSB 移进 rem 的最低一位）
//            if (rem >= denom) { rem -= denom; quot[0] = 1; }
//      48 拍后 quot = numer / denom, rem = numer % denom
//
//  除零：denom = 0 时不会卡死（rem 恒 >= 0，商变成全 1），
//        由调用方判 denom == 0 并标记结果无效。
//
//  ★ 本文件**不要**登记到 TD 的 Design Files 里，
//    而是由 design_top_wrapper.v 用 `include 拉进来
//    （登记了又 include 会造成模块重复定义，编译不生效）。
//=============================================================================
`ifndef VIB_DIV_SERIAL_V
`define VIB_DIV_SERIAL_V

module vib_div_serial #(
    parameter W  = 48,          // 被除数 / 商 位宽
    parameter DW = 32           // 除数位宽
)(
    input  wire          clk,
    input  wire          rst_n,      // 异步低有效
    input  wire          start,      // 1 拍脉冲，发起一次除法
    input  wire [W-1:0]  numer,      // 被除数（无符号）
    input  wire [DW-1:0] denom,      // 除数（无符号）
    output reg  [W-1:0]  quot,       // 商（除法完成那一拍更新）
    output reg  [W-1:0]  rem,        // 余数（诊断用）
    output reg           done        // 完成时 1 拍脉冲
);

    localparam [6:0] LAST = W[6:0] - 7'd1;     // 47

    reg  [W-1:0]  quot_r;
    reg  [W-1:0]  rem_r;
    reg  [DW-1:0] den_r;
    reg  [6:0]    cnt;
    reg           busy;

    // ---- 组合：一拍除法 ----
    wire [W:0] rem_sh   = {rem_r, quot_r[W-1]};          // 左移 + 移入被除数 MSB
    wire [W-1:0] quot_sh = {quot_r[W-2:0], 1'b0};        // 左移，最低位待填
    wire [W:0] den_x    = {{(W-DW+1){1'b0}}, den_r};     // 零扩展到 W+1 位
    wire        ge      = (rem_sh >= den_x);
    wire [W:0] rem_next = ge ? (rem_sh - den_x) : rem_sh;
    wire [W-1:0] quot_set = ge ? (quot_sh | {{(W-1){1'b0}}, 1'b1}) : quot_sh;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            quot_r <= {W{1'b0}};
            rem_r  <= {W{1'b0}};
            den_r  <= {DW{1'b0}};
            cnt    <= 7'd0;
            busy   <= 1'b0;
            quot   <= {W{1'b0}};
            rem    <= {W{1'b0}};
            done   <= 1'b0;
        end
        else begin
            done <= 1'b0;

            if (start) begin
                // 装载：被除数进 quot，余数清零
                quot_r <= numer;
                rem_r  <= {W{1'b0}};
                den_r  <= denom;
                cnt    <= 7'd0;
                busy   <= 1'b1;
            end
            else if (busy) begin
                rem_r  <= rem_next[W-1:0];
                quot_r <= quot_set;
                cnt    <= cnt + 7'd1;
                if (cnt == LAST) begin
                    // 第 W 拍：完成，把结果搬到输出并给 done 脉冲
                    busy <= 1'b0;
                    done <= 1'b1;
                    quot <= quot_set;
                    rem  <= rem_next[W-1:0];
                end
            end
        end
    end

endmodule

`endif
