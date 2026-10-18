//=====================================================================
//  vib_gauss3x3.v  ——  3x3 整数高斯平滑（可分离）
//
//  与 Python 逐位一致（vision_basic.py:141 gaussian3x3_hw_like）：
//      1 2 1
//      2 4 2     总和 16，右移 4 位；边界用 mode="edge"（复制边缘）
//      1 2 1
//  可分离实现（先竖直 [1 2 1] 再水平 [1 2 1]）。整数加法可结合，
//  与直接展开 3x3 逐位相同。
//
//  ★ 为什么需要这一级：
//      Python 的帧差是 it = g - prev，其中 g 是**高斯后**的灰度、
//      prev 存的也是高斯后的灰度（vision_multi_object.py:434 与 :1366）。
//      所以 B2b（上一帧缓存 + 帧差）的输入必须是高斯后的灰度，
//      否则后面 min_grad_sum / It 的量纲都对不上 Python 的黄金数据。
//
//  时序：1 输入像素 -> 1 输出像素，纯流水，不阻塞。
//        输出行比输入行**晚一行**（竖直 3 行窗口要等下一行到达）。
//        竖直：v[r-1][x] = raw[r-2][x] + 2*raw[r-1][x] + raw[r][x]
//        水平：g[r-1][x-1] = (v[x-2] + 2*v[x-1] + v[x]) >> 4
//              —— 用两拍移位 d1=v[x-1], d2=v[x-2]，与本拍的 v[x] 组合，
//                 所以是**组合输出**，不需要额外流水级。
//
//  边界处理（对应 numpy 的 mode="edge"）：
//    * 输出行 0：raw[-1] 用 raw[0] 顶替
//    * 输出列 0：v[-1]  用 v[0]  顶替（用 d1 代替 d2）
//    * 输出列 639：v[640] 用 v[639] 顶替 —— 每行末尾额外 1 拍，
//                  把上一拍的 v 保持住再算一次
//    * 输入行 0 不产出（没有 out_row = -1）
//    * 末行：输出行 359 需要 raw[360]=raw[359]，
//            在输入第 359 行结束后**回放**它（从行缓存读），
//            正好落在行消隐里，不占额外时间
//
//  自检：GOFP 应 = 0x00038400，GOFL 应 = 360 = 0x00000168
//=====================================================================
module vib_gauss3x3 (
    input  wire       clk,
    input  wire       rst_n,

    // 来自 vib_video_tap 的 640x360 灰度
    input  wire       px_valid,
    input  wire [7:0] px_data,
    input  wire       px_frame_start,     // 输出行 0 的第 1 个像素
    input  wire       px_line_end,        // 每行最后一个像素（本模块不用，仅占位）

    // 高斯后的 640x360 灰度（给 vib_prev_frame_ddr）
    output reg        g_valid,
    output reg  [7:0] g_data,
    output reg        g_frame_start,
    output reg        g_line_end,

    output reg  [31:0] st_g_px,           // 每帧输出像素数，应 = 0x00038400
    output reg  [15:0] st_g_lines,        // 每帧输出行数，  应 = 360
    output reg         st_tgl             // 统计量已更新（供跨域原子快照）
);

    localparam [9:0] LASTX = 10'd639;
    localparam [9:0] LASTY = 10'd359;

    //==================================================================
    // 三个行缓存，各自独立读口
    //   写第 r 行 -> lb[r%3]；同时读 lb[(r-1)%3]=raw[r-1], lb[(r-2)%3]=raw[r-2]
    //   三个分开的 RAM 各有 1 个读口，避免"一拍读两行"的多口问题
    //==================================================================
    reg  [7:0] lb0 [0:LASTX];
    reg  [7:0] lb1 [0:LASTX];
    reg  [7:0] lb2 [0:LASTX];

    //==================================================================
    // ★ ccol：**当前这个像素**的列号
    //   早先直接用寄存器 col 去写行缓存和判 LASTX，但 col 是在本拍末尾
    //   才 +1 的，于是：
    //     - 每行第 2 个像素被写到 col 0（覆盖第 1 个）
    //     - 第 640 个像素（ccol=639）永远判不到 LASTX，要等**下一行第 1 个
    //       像素**来触发 extra，那个像素就被写到上一行的 col 639 上
    //     - 每行因此多花 1 拍，累积 359 拍后下一帧帧首会撞进上一帧末行
    //   板上表现：GOFP 少 1000、GOFL 少 2，且末行整行为空。
    //   这个 off-by-one 是被逐拍 Python 模型抓出来的。
    //==================================================================
    
    reg  [9:0] row_in;
    reg  [9:0] col;                       // 含义改为"下一个像素的列号"
    reg  [1:0] wr_sel, rd1_sel, rd2_sel;
    reg        replay;
    reg        extra;

    wire [9:0] ccol = px_frame_start ? 10'd0 : col;

    wire [7:0] lb0_rd = lb0[ccol];
    wire [7:0] lb1_rd = lb1[ccol];
    wire [7:0] lb2_rd = lb2[ccol];

    reg  [7:0] gA, gB;                    // raw[r-2], raw[r-1]
    always @(*) begin
        case (rd2_sel) 2'd0: gA = lb0_rd; 2'd1: gA = lb1_rd; default: gA = lb2_rd; endcase
        case (rd1_sel) 2'd0: gB = lb0_rd; 2'd1: gB = lb1_rd; default: gB = lb2_rd; endcase
    end

    // 回放输出行 359：raw[358]=lb1, raw[359]=lb2, raw[360]=raw[359]=lb2
    wire [9:0] rpA = {2'b0, lb1[ccol]};
    wire [9:0] rpB = {2'b0, lb2[ccol]};

    //==================================================================
    // 竖直级
    //==================================================================
    wire [9:0] gA_x = {2'b0, gA};
    wire [9:0] gB_x = {2'b0, gB};
    wire [9:0] gC_x = {2'b0, px_data};

    wire       out_row0 = (row_in == 10'd1);
    wire [9:0] v_norm  = (out_row0 ? gB_x : gA_x) + {gB_x, 1'b0} + gC_x;
    wire [9:0] v_rply  = rpA + {rpB, 1'b0} + rpB;     // raw[358] + 2*r359 + r359

    // 本拍是否有有效像素推进流水
    //   ★ row_ok 必须同时约束 extra：第 0 行的行末额外拍对应的是
    //     "输出行 -1"（不存在），不加这个门会多出 640 个像素 + 1 行，
    //     表现为 GOFP=231040 / GOFL=361 的 off-by-one。
    //   ★ frm_done：回放结束后到下一帧 px_frame_start 之间屏蔽输出，
    //     防止期间若有杂散 px_valid 把上一行又输出一遍。
    wire       row_ok  = (row_in != 10'd0);
    wire       v_en    = ((px_valid & row_ok) | replay | (extra & row_ok)) & ~frm_done;
    wire [9:0] v_now   = replay ? v_rply : v_norm;

    // 行末额外那一拍要把 v 保持住（v[640] = v[639]）
    reg  [9:0] v_hold;
    wire [9:0] v       = extra ? v_hold : v_now;

    //==================================================================
    // 水平级：两拍移位 + 组合输出
    //   本拍 v = v[x]，d1 = v[x-1]，d2 = v[x-2]
    //   输出列 = x-1，值 = (d2 + 2*d1 + v) >> 4
    //==================================================================
    reg  [9:0] d1, d2;

    wire [9:0] out_x = extra ? LASTX : (ccol - 10'd1);
    wire       hL    = (out_x == 10'd0) ? d1 : d2;     // 列 0：v[-1]=v[0]
    wire [11:0] hsum = {2'b0, hL} + {d1, 1'b0} + {2'b0, v};
    wire [7:0]  gpx  = hsum[11:4];

    // 本拍是否真的产出
    wire       oen   = v_en & (extra | (ccol != 10'd0));

    //==================================================================
    // 主控
    //==================================================================
    reg  [31:0] px_acc;
    reg  [15:0] ln_acc;
    reg         fs_pend;
    reg         frm_done;                 // 回放结束 -> 本帧完成，等下帧帧首

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_in        <= 10'd0;
            col           <= 10'd0;
            wr_sel        <= 2'd0;
            rd1_sel       <= 2'd2;
            rd2_sel       <= 2'd1;
            replay        <= 1'b0;
            extra         <= 1'b0;
            frm_done      <= 1'b0;
            d1            <= 10'd0;
            d2            <= 10'd0;
            v_hold        <= 10'd0;
            g_valid       <= 1'b0;
            g_data        <= 8'd0;
            g_frame_start <= 1'b0;
            g_line_end    <= 1'b0;
            st_g_px       <= 32'd0;
            st_g_lines    <= 16'd0;
            st_tgl        <= 1'b0;
            px_acc        <= 32'd0;
            ln_acc        <= 16'd0;
            fs_pend       <= 1'b0;
        end
        else begin
            g_valid       <= 1'b0;
            g_frame_start <= 1'b0;
            g_line_end    <= 1'b0;

            //-----------------------------------------------
            // 行缓存写入（回放时不写）
            //-----------------------------------------------
            // ★ 必须排除 extra 拍：行末额外那一拍 col 仍停在 639，
            //   若此时 px_valid 仍为 1（下一行首像素紧跟其后），就会用
            //   下一行的第 0 个像素覆盖 lb[wr_sel][639]，污染竖直窗口的
            //   第三个 tap —— 而 GOFP/GOFL 依然正确，图像错却极难定位。
            if (px_valid && !replay && !extra) begin
                case (wr_sel)
                2'd0: lb0[ccol] <= px_data;
                2'd1: lb1[ccol] <= px_data;
                default: lb2[ccol] <= px_data;
                endcase
            end

            //-----------------------------------------------
            // 水平移位
            //-----------------------------------------------
            if (v_en) begin
                d1     <= v;
                d2     <= d1;
                v_hold <= v_now;
            end

            //-----------------------------------------------
            // 输出
            //-----------------------------------------------
            if (oen) begin
                g_valid <= 1'b1;
                g_data  <= gpx;

                // ★ 只有帧首才锁存/复位统计。之前写成"每行开头(out_x==0)"复位，
                //   于是 px_acc/ln_acc 每行被清一次，GOFP 只会读到一行的 640、
                //   GOFL 读到 1 —— 这个 off-by-一行 是被逐拍 Python 模型抓出来的。
                if (fs_pend && (out_x == 10'd0)) begin
                    g_frame_start <= 1'b1;
                    fs_pend       <= 1'b0;
                    st_g_px       <= px_acc;      // 上一帧总数
                    st_g_lines    <= ln_acc;
                    st_tgl        <= ~st_tgl;     // 统计量已更新（供跨域原子快照）
                    px_acc        <= 32'd1;       // 本像素算新帧第 1 个
                    ln_acc        <= 16'd0;
                end
                else begin
                    px_acc <= px_acc + 32'd1;
                    if (out_x == LASTX) begin
                        g_line_end <= 1'b1;
                        ln_acc     <= ln_acc + 16'd1;
                    end
                end
            end

            //-----------------------------------------------
            // 列 / 行推进
            //-----------------------------------------------
            if (replay) begin
                // ★ 回放的收尾必须在这里自己处理。
                //   之前写成"col==LASTX 时置 extra，靠下面的 else if (extra) 分支收尾"，
                //   但 replay=1 时 if (replay) 永远优先，extra 分支永远轮不到 ->
                //   回放死循环、统计量无限累加（实测 ln_acc 冲到 48 万）。
                if (extra) begin
                    replay   <= 1'b0;
                    extra    <= 1'b0;
                    frm_done <= 1'b1;
                    col      <= 10'd0;
                end
                else if (col == LASTX) extra <= 1'b1;
                else                   col   <= col + 10'd1;
            end
            else if (extra) begin
                extra <= 1'b0;
                col   <= 10'd0;
                if (row_in == LASTY) begin
                    replay  <= 1'b1;              // 末行结束 -> 回放
                end
                else begin
                    row_in <= row_in + 10'd1;
                    case (wr_sel)
                    2'd0: begin wr_sel <= 2'd1; rd1_sel <= 2'd0; rd2_sel <= 2'd2; end
                    2'd1: begin wr_sel <= 2'd2; rd1_sel <= 2'd1; rd2_sel <= 2'd0; end
                    default: begin wr_sel <= 2'd0; rd1_sel <= 2'd2; rd2_sel <= 2'd1; end
                    endcase
                end
            end
            else if (px_valid) begin
                if (px_frame_start) begin
                    row_in  <= 10'd0;
                    col     <= 10'd1;          // 本像素是列 0，下一个是列 1
                    wr_sel  <= 2'd0;
                    rd1_sel <= 2'd2;
                    rd2_sel <= 2'd1;
                    fs_pend <= 1'b1;
                    frm_done <= 1'b0;
                end
                else if (ccol == LASTX) begin
                    extra <= 1'b1;                // 行末：额外 1 拍发最后一个输出像素
                end
                else col <= ccol + 10'd1;
            end
        end
    end

endmodule
