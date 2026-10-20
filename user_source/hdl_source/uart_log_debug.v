//=====================================================================
//  uart_log_debug.v  ——  串口日志打印（老工程移植 + 逐步扩展）
//
//  作用：通过串口每秒打印一轮板级状态，用来确认 UART 通路是否打通、
//        时钟/像素速率是否符合预期、以及各功能块跑到哪一步了。
//
//  时钟：clk = I_sys_clk = 50 MHz（见 camera_to_dsi_display.sdc: sys_clk_50m）
//  引脚：tx -> O_uart_tx -> 板子 H1（见 pin.adc）
//  串口：115200 8N1；板子 TX(H1) 接 USB-TTL 的 RXD，GND 共地
//
//  ---------------------------------------------------------------------
//  每轮先打 1 行横幅，再打 27 行状态，每行 15 字节，共 442 字节//  （115200 下约 38.4 ms 打完，所以"每秒一轮"绰绰有余）：
//
//      SC520 MIPI-HDMI UART LOG 115200 8N1\r\n
//      SEC  00000000   运行秒数（每轮 +1）
//      VSUM 00000000   抽头 Σ灰度（摄像头活着的证据）
//      GPIX 00000000   高斯每帧输出像素数（应 230400）
//      ITSM 00000000   每帧 Σ|It|：静止接近 0，一动就涨
//      ITER 00000000   上一帧差分异常计数，必须 = 0
//      LKPX 00000000   LK 每帧像素数，应 = 0x00038400
//      LKER 00000000   LK 异常计数，必须 = 0
//      LKU  00000000   u 的 Q8.8（像素/帧，有符号）
//      LKV  00000000   v 的 Q8.8（像素/帧，有符号）
//      LKVA 00000000   该块通过门限（1=有效）
//      LKBL 00000000   最大变化块的列 0..7
//      LKBR 00000000   最大变化块的行 0..5
//      LKBE 00000000   最大块 en
//      FXPS 00000000   固定块 {valid,row,col}
//      FXBX 00000000   固定块 bx
//      FXBY 00000000   固定块 by
//      FXEN 00000000   固定块 en
//      FXTX 00000000   固定块 Σmin(ix²,iy²)（二维可观测性）
//      GZHZ 00000000   Goertzel 峰值频率×10（55=5.5Hz）
//      GZBN 00000000   Goertzel 峰值频点 0..16
//      GZMG 00000000   Goertzel 峰值幅度² >>8（防 32 位回绕）
//      GZFR 00000000   Goertzel 窗口已累计帧数 0..128
//      GZWC 00000000   阶段0 写流校验（旋转XOR）
//      GZRC 00000000   阶段0 读流校验，应等于 GZWC
//      GZOK 00000000   阶段0 存储自检通过（GZWC==GZRC）
//      GZS1 00000000   bin6(5Hz) 的 s1 状态
//      LKIS 00000000   与 LKBE 同拍锁存的 ITSM
//
//  判读方法：
//    * 能看到整齐的上面这些行        -> 波特率 / 帧格式 / 引脚 都对 ✓
//    * SEC 每秒 +1，连续不乱         -> 时钟假设正确 ✓
//    * DIV = 000001B2（434）         -> 分频值正确（50MHz 下 115200）✓
//    * PXFR = 000E1000（921600）     -> 视频流是 1280x720，抽头正确 ✓
//    * CSIH / PIXS                   -> 平均每像素几个 csi 时钟
//    * DTRD = 00003840 且 DTER = 0   -> DDR 算法区域读写自检通过 ✓
//    * 全是乱码                      -> 十有八九是 CLK_HZ 与真实时钟不符 ✗
//
//  ---------------------------------------------------------------------
//  ★ 与底层 uart_tx.v 的握手说明（沿用老工程踩过坑之后的写法）
//     底层 uart_tx.v 用的是 ready/valid 握手，但它的 tx_data_ready 不是
//     "空闲常高"，而且在状态切换那一拍有竞争。历史上用**电平**推进会出现
//     "每个字节被重发"（现象：串口里看到重复字符）。所以这里：
//        ① 等 tx_ready=1（uart 空闲）才装载下一个字节
//        ② tx_valid 只给 **1 拍脉冲**，数据与它同拍寄存
//        ③ 再等 ready 变低（字节被取走）后变高（这一字节发完）
//     这样 uart 每个字节只会在唯一的那个 IDLE 拍被锁存一次，不会重复 ✓
//  ---------------------------------------------------------------------
//  复位说明：rst_n 接 I_rst_n（板级复位），这样 PLL 还没锁的时候
//            串口就已经在打印了，便于定位问题。
//            状态输入分两类，都做了两拍同步：
//              a) 粘滞标志 / 慢变化电平（PLL/CAM/I2C/HS/...）—— 安全
//              b) 每秒刷新的测量值（CSIH/PIXS/FPS/PXFR/DTRD/DTER）
//                 —— 它们本来就只 1 秒变一次，跨域采样同样安全
//=====================================================================
module uart_log_debug #(
    parameter integer CLK_HZ = 50_000_000,   // 本模块时钟频率（Hz）
    parameter integer BAUD   = 115200        // 波特率
)(
    input  wire        clk,                 // I_sys_clk = 50MHz
    input  wire        rst_n,               // 异步复位，低有效
    input  wire        pll_lock,            // PLL 锁定
    input  wire        ddr_init_done,       // DDR 初始化校准完成
    input  wire        cam_cfg_done,        // 摄像头寄存器配置完成（粘滞）
    input  wire        cam_i2c_error,       // 摄像头 I2C 错误
    input  wire [15:0] sensor_id,           // 摄像头 Sensor ID
    input  wire        sensor_id_ok,        // 摄像头 ID 校验通过（0xEE4B/0x9E4B）
    input  wire [3:0]  mipi_diag_status,    // MIPI 诊断码 0..7
    input  wire        hs_seen,             // 已收到 MIPI HS 数据（粘滞）
    input  wire        csi_frame_seen,      // 已解析出 CSI 帧（粘滞）
    input  wire        raw10_seen,          // 已出现 RAW10 流水（粘滞）
    input  wire        video_nonzero_seen,  // 已读到非零视频数据（粘滞）
    input wire [31:0] vsum, // 抽头每帧 Σ灰度：非 0 说明抽头拿到像素了
    input wire [31:0] gpx, // 高斯每帧输出像素数，应恒为 230400
    input wire [31:0] it_sum,             // 每帧 Σ|It|：静止场景接近 0，画面一动立刻涨
    input wire [31:0] it_err,             // 上一帧差分异常计数，必须 = 0
    input wire [31:0] lk_px,              // LK 每帧参与累加的像素数，应 = 0x00038400
    input wire [31:0] lk_err,             // LK 异常计数，必须 = 0
    input wire signed [31:0] lk_u,  // u = 2*nu_hw/det_hw，Q8.8 像素/帧
    input wire signed [31:0] lk_v,  // v = 2*nv_hw/det_hw，Q8.8 像素/帧
    input wire lk_va,              // 1 = 该块通过门限，u/v 有效
    input wire [2:0] lk_bl,        // 最大变化块的块列 0..7
    input wire [2:0] lk_br,        // 最大变化块的块行 0..5
    input wire [31:0] lk_be, // 最大变化块的 acc_en（诊断 LKBE 恒定用）
    input wire [31:0] fxpos, // 纹理固定块: bit[6]=valid, bit[5:3]=row, bit[2:0]=col（共 32 位）
    input wire signed [31:0] fxbx, // 固定块本帧的 bx
    input wire signed [31:0] fxby, // 固定块本帧的 by
    input wire [31:0] fxen, // 固定块本帧的 en
    input wire [31:0] fxtex, // 固定块 Σmin(ix^2, iy^2)：一维纹理接近 0，二维纹理才大
    input wire [31:0] gzhz, // Goertzel 峰值频率*10
    input wire [31:0] gzbn, // Goertzel 峰值频点
    input wire [31:0] gzmg, // Goertzel 峰值 mag^2 >> 8（覆盖到 5.5e11，不回绕）
    input wire [31:0] gzfr, // Goertzel 窗口帧计数
    input wire [31:0] gzwc, // 写流旋转XOR校验
    input wire [31:0] gzrc, // 读流旋转XOR校验
    input wire [31:0] gzok, // 存储自检通过标志
    input wire signed [31:0] gzs1, // 5Hz 频点的 s1
input wire [31:0] gztl, // 音调判决：峰值占全部能量 25% 以上
    input wire [31:0] lk_is, // 与 LKBE 同一拍锁存的 ITSM，用于验证 LKBE <= LKIS
    output wire        tx                   // 串口输出 -> O_uart_tx -> H1
);

    //------------------------------------------------------------------
    // 波特率分频（四舍五入）。这个值会被打印出来，方便核对 CLK_HZ 是否写对。
    //   50_000_000 / 115200 = 434.03 -> 434 = 0x1B2
    //------------------------------------------------------------------
    localparam [31:0] DIV = (CLK_HZ + BAUD/2) / BAUD;

    //------------------------------------------------------------------
    // 一轮消息的长度参数
    //------------------------------------------------------------------
    localparam integer NF        = 28;   // 状态行（字段）个数
    localparam integer FLD_LAST  = 28 - 1;
    localparam integer POS_LAST  = 15 - 1;
    localparam integer BIDX_LAST = 37 - 1;

    //------------------------------------------------------------------
    // 1 秒节拍
    //   tick 复位成 CLK_HZ-1，于是复位后第一个时钟就产生一次节拍，
    //   上电后立刻先打一轮，之后才是每 1 秒一轮。
    //------------------------------------------------------------------
    reg  [31:0] tick;
    wire        tick_1s = (tick == (CLK_HZ - 1));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tick <= (CLK_HZ - 1);
        else        tick <= tick_1s ? 32'd0 : (tick + 32'd1);
    end

    //------------------------------------------------------------------
    // 跨时钟域同步：状态输入全是粘滞标志 / 慢变化电平，打两拍即可
    //------------------------------------------------------------------
    reg  [1:0]  pll_s, ddr_s, cam_s, i2c_s, hs_s, csif_s, raw_s, vid_s, siok_s;
    reg  [15:0] sid_s1, sid_s2;
    reg  [3:0]  mipi_s1, mipi_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pll_s  <= 2'b00; ddr_s  <= 2'b00; cam_s  <= 2'b00; i2c_s  <= 2'b00;
            hs_s   <= 2'b00; csif_s <= 2'b00; raw_s  <= 2'b00; vid_s  <= 2'b00;
            siok_s <= 2'b00;
            sid_s1 <= 16'd0; sid_s2 <= 16'd0;
            mipi_s1 <= 4'd0; mipi_s2 <= 4'd0;
        end
        else begin
            pll_s  <= {pll_s[0],  pll_lock};
            ddr_s  <= {ddr_s[0],  ddr_init_done};
            cam_s  <= {cam_s[0],  cam_cfg_done};
            i2c_s  <= {i2c_s[0],  cam_i2c_error};
            hs_s   <= {hs_s[0],   hs_seen};
            csif_s <= {csif_s[0], csi_frame_seen};
            raw_s  <= {raw_s[0],  raw10_seen};
            vid_s  <= {vid_s[0],  video_nonzero_seen};
            siok_s <= {siok_s[0], sensor_id_ok};
            mipi_s1 <= mipi_diag_status;
            mipi_s2 <= mipi_s1;
            // Sensor ID 在配置完成后才稳定，等配置完成再采样
            if (cam_s[1]) sid_s1 <= sensor_id;
            sid_s2 <= sid_s1;
        end
    end

    wire [3:0] mipi_code = mipi_s2;

    //------------------------------------------------------------------
    // 运行秒数（每打印完一轮 +1）
    //------------------------------------------------------------------
    reg  [31:0] run_sec;

    //------------------------------------------------------------------
    // 4 位十六进制 -> ASCII
    //------------------------------------------------------------------
    function [7:0] hx;
        input [3:0] n;
        begin
            if (n < 4'd10) hx = 8'h30 + {4'd0, n};          // '0'..'9'
            else           hx = 8'h41 + {4'd0, n} - 8'd10;  // 'A'..'F'
        end
    endfunction

    //------------------------------------------------------------------
    // 字段标签：给出第 f 个字段的第 p 个字符（p: 0..3，从左到右）
    //------------------------------------------------------------------
    function [7:0] lbl;
        input [4:0] f;
        input [1:0] p;
        reg  [31:0] s;
        begin
            case (f)
            5'd0 : s = "SEC ";
            5'd1 : s = "VSUM";
            5'd2 : s = "GPIX";
            5'd3 : s = "ITSM";
            5'd4 : s = "ITER";
            5'd5 : s = "LKPX";
            5'd6 : s = "LKER";
            5'd7 : s = "LKU ";
            5'd8 : s = "LKV ";
            5'd9 : s = "LKVA";
            5'd10: s = "LKBL";
            5'd11: s = "LKBR";
            5'd12: s = "LKBE";
            5'd13: s = "FXPS";
            5'd14: s = "FXBX";
            5'd15: s = "FXBY";
            5'd16: s = "FXEN";
            5'd17: s = "FXTX";
            5'd18: s = "GZHZ";
            5'd19: s = "GZBN";
            5'd20: s = "GZMG";
            5'd21: s = "GZFR";
            5'd22: s = "GZWC";
            5'd23: s = "GZRC";
            5'd24: s = "GZOK";
            5'd25: s = "GZS1";
            5'd27: s = "GZTL";
            5'd26: s = "LKIS";
            default: s = "????";
            endcase
            case (p)
            2'd0:    lbl = s[31:24];
            2'd1:    lbl = s[23:16];
            2'd2:    lbl = s[15: 8];
            default: lbl = s[ 7: 0];
            endcase
        end
    endfunction

    //------------------------------------------------------------------
    // 当前字段的 32bit 值（由 fld 组合译码）
    //------------------------------------------------------------------
    reg  [31:0] v;

    always @(*) begin
        case (fld)
        5'd0 : v = run_sec           ; // 运行秒数（每轮 +1）
        5'd1 : v = vsum              ; // 抽头 Σ灰度（摄像头活着的证据）
        5'd2 : v = gpx               ; // 高斯每帧输出像素数（应 230400）
        5'd3 : v = it_sum            ; // 每帧 Σ|It|：静止接近 0，一动就涨
        5'd4 : v = it_err            ; // 上一帧差分异常计数，必须 = 0
        5'd5 : v = lk_px             ; // LK 每帧像素数，应 = 0x00038400
        5'd6 : v = lk_err            ; // LK 异常计数，必须 = 0
        5'd7 : v = lk_u              ; // u 的 Q8.8（像素/帧，有符号）
        5'd8 : v = lk_v              ; // v 的 Q8.8（像素/帧，有符号）
        5'd9 : v = lk_va             ; // 该块通过门限（1=有效）
        5'd10: v = lk_bl             ; // 最大变化块的列 0..7
        5'd11: v = lk_br             ; // 最大变化块的行 0..5
        5'd12: v = lk_be             ; // 最大块 en
        5'd13: v = snap[13]          ; // 固定块 {valid,row,col}
        5'd14: v = snap[14]          ; // 固定块 bx
        5'd15: v = snap[15]          ; // 固定块 by
        5'd16: v = snap[16]          ; // 固定块 en
        5'd17: v = snap[17]          ; // 固定块 Σmin(ix²,iy²)（二维可观测性）
        5'd18: v = snap[18]          ; // Goertzel 峰值频率×10（55=5.5Hz）
        5'd19: v = snap[19]          ; // Goertzel 峰值频点 0..16
        5'd20: v = snap[20]          ; // Goertzel 峰值幅度² >>8（防 32 位回绕）
        5'd21: v = snap[21]          ; // Goertzel 窗口已累计帧数 0..128
        5'd22: v = snap[22]          ; // 阶段0 写流校验（旋转XOR）
        5'd23: v = snap[23]          ; // 阶段0 读流校验，应等于 GZWC
        5'd24: v = snap[24]          ; // 阶段0 存储自检通过（GZWC==GZRC）
        5'd25: v = snap[25]          ; // bin6(5Hz) 的 s1 状态
        5'd27: v = snap[27]          ; // 音调判决
        5'd26: v = snap[26]          ; // 与 LKBE 同拍锁存的 ITSM
        default:  v = 32'd0;
        endcase
    end

    //------------------------------------------------------------------
    // 当前字段的十六进制 nibble（由 pos 组合译码，只见 pos = 5..12）
    //------------------------------------------------------------------
    reg  [3:0] nib;

    always @(*) begin
        case (pos)
        4'd5:    nib = v[31:28];
        4'd6:    nib = v[27:24];
        4'd7:    nib = v[23:20];
        4'd8:    nib = v[19:16];
        4'd9:    nib = v[15:12];
        4'd10:   nib = v[11: 8];
        4'd11:   nib = v[ 7: 4];
        default: nib = v[ 3: 0];
        endcase
    end

    //------------------------------------------------------------------
    // ★ 整轮日志的快照（本轮新增，修一个真实的观测问题）
    //
    //   下面的 v 是**组合译码**：每个字段是"发到它那一刻"才去取值。
    //   而一轮要发 38.4 ms，一帧只有 16.7 ms —— 于是
    //     ITSM(字段25) 与 ITSS(字段29) 相隔 4 字段 = 60 字节 = 5.2 ms，
    //     约 31% 的概率落在相邻两帧上。
    //   实测出现过 |ITSS| > ITSM（= 1.67e7 > 1.78e5），这违反三角不等式
    //   |ΣIt| <= Σ|It|，同帧绝不可能 —— 说明两个字段本来就来自不同帧，
    //   不是算法算错。
    //
    //   修法：每秒开轮的那一拍，把所有"会变的"字段（13 号及之后）
    //         一次性打进快照寄存器，整轮日志都从快照读 -> 同一轮内自洽。
    //   代价：14 个 32bit 寄存器。标志位/常量不必快照。
    //------------------------------------------------------------------
    wire        snap_ld = (st_r == ST_TICK) && tick_1s;   // 开轮那一拍
    reg  [31:0] snap [0:NF-1];

    always @(posedge clk) begin
        if (snap_ld) begin
            snap[13] <= fxpos;
            snap[14] <= fxbx;
            snap[15] <= fxby;
            snap[16] <= fxen;
            snap[17] <= fxtex;
            snap[18] <= gzhz;
            snap[19] <= gzbn;
            snap[20] <= gzmg;
            snap[21] <= gzfr;
            snap[22] <= gzwc;
            snap[23] <= gzrc;
            snap[24] <= gzok;
            snap[25] <= gzs1;
            snap[27] <= gztl;
            snap[26] <= lk_is;
        end
    end

    //------------------------------------------------------------------
    // 横幅：由 bidx 组合译码，共 37 字节
    //------------------------------------------------------------------
    reg  [7:0] ban;

    always @(*) begin
        case (bidx)
        6'd0 : ban = "S"     ; // 'S'
        6'd1 : ban = "C"     ; // 'C'
        6'd2 : ban = "5"     ; // '5'
        6'd3 : ban = "2"     ; // '2'
        6'd4 : ban = "0"     ; // '0'
        6'd5 : ban = " "     ; // ' '
        6'd6 : ban = "M"     ; // 'M'
        6'd7 : ban = "I"     ; // 'I'
        6'd8 : ban = "P"     ; // 'P'
        6'd9 : ban = "I"     ; // 'I'
        6'd10: ban = "-"     ; // '-'
        6'd11: ban = "H"     ; // 'H'
        6'd12: ban = "D"     ; // 'D'
        6'd13: ban = "M"     ; // 'M'
        6'd14: ban = "I"     ; // 'I'
        6'd15: ban = " "     ; // ' '
        6'd16: ban = "U"     ; // 'U'
        6'd17: ban = "A"     ; // 'A'
        6'd18: ban = "R"     ; // 'R'
        6'd19: ban = "T"     ; // 'T'
        6'd20: ban = " "     ; // ' '
        6'd21: ban = "L"     ; // 'L'
        6'd22: ban = "O"     ; // 'O'
        6'd23: ban = "G"     ; // 'G'
        6'd24: ban = " "     ; // ' '
        6'd25: ban = "1"     ; // '1'
        6'd26: ban = "1"     ; // '1'
        6'd27: ban = "5"     ; // '5'
        6'd28: ban = "2"     ; // '2'
        6'd29: ban = "0"     ; // '0'
        6'd30: ban = "0"     ; // '0'
        6'd31: ban = " "     ; // ' '
        6'd32: ban = "8"     ; // '8'
        6'd33: ban = "N"     ; // 'N'
        6'd34: ban = "1"     ; // '1'
        6'd35: ban = 8'h0D   ; // '\r'
        6'd36: ban = 8'h0A   ; // '\n'
        default: ban = 8'h20;               // 空格
        endcase
    end

    //------------------------------------------------------------------
    // 一轮消息的字节指针
    //------------------------------------------------------------------
    reg              in_banner;   // 1 = 正在发横幅
    reg  [5:0] bidx;        // 横幅字节下标
    reg  [4:0] fld;         // 字段号
    reg  [3:0] pos;         // 字段内字节位置

    //------------------------------------------------------------------
    // 当前要发的字节
    //   横幅：全部来自 ban
    //   状态行：label(4) + space(1) + hex 8 位(8) + CR + LF = 15 字节
    //------------------------------------------------------------------
    reg  [7:0] cur;

    always @(*) begin
        if (in_banner)
            cur = ban;
        else if (pos < 4'd4)
            cur = lbl(fld, pos[1:0]);
        else if (pos == 4'd4)
            cur = 8'h20;                    // space
        else if (pos < 4'd13)
            cur = hx(nib);                  // 8 位十六进制，高位在前
        else if (pos == 4'd13)
            cur = 8'h0D;                    // CR
        else
            cur = 8'h0A;                    // LF
    end

    //------------------------------------------------------------------
    // 发送状态机（1 拍脉冲 + busy 等待，见文件头说明）
    //------------------------------------------------------------------
    localparam ST_TICK = 2'd0,   // 等 1 秒节拍
               ST_LOAD = 2'd1,   // 等 uart 空闲 -> 装载一个字节并给 pulse
               ST_BUSY = 2'd2;   // 等这一字节发完

    reg  [1:0] st_r;
    reg        tx_valid;
    reg  [7:0] tx_data;
    wire       tx_ready;
    reg        seen_low;         // 已经观察到 ready 变低（字节被取走）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_r      <= ST_TICK;
            in_banner <= 1'b1;
            bidx      <= 0;
            fld       <= 0;
            pos       <= 0;
            run_sec   <= 32'd0;
            tx_valid  <= 1'b0;
            tx_data   <= 8'd0;
            seen_low  <= 1'b0;
        end
        else case (st_r)
        // ---------------- 等 1 秒节拍 ----------------
        ST_TICK: begin
            tx_valid <= 1'b0;
            if (tick_1s) begin
                in_banner <= 1'b1;
                bidx      <= 0;
                fld       <= 0;
                pos       <= 0;
                st_r      <= ST_LOAD;
            end
        end
        // ---------------- 装载一个字节 ----------------
        // 必须等 tx_ready=1（uart 在 IDLE 且没在收字节）才装载，
        // 这样 uart 只会在下一个 IDLE 拍锁存一次，不会重复发 ✓
        ST_LOAD: begin
            if (tx_ready) begin
                tx_data  <= cur;         // cur 由 in_banner/bidx/fld/pos 组合译码
                tx_valid <= 1'b1;        // 只给 1 拍脉冲
                seen_low <= 1'b0;
                st_r     <= ST_BUSY;
            end
        end
        // ---------------- 等这个字节发完，然后推进指针 ----------------
        ST_BUSY: begin
            tx_valid <= 1'b0;            // 脉冲已经给过了
            if (!tx_ready) begin
                seen_low <= 1'b1;        // 字节被取走
            end
            else if (seen_low) begin     // ready 回来了 = 这一字节发完
                if (in_banner) begin
                    if (bidx == BIDX_LAST) begin
                        in_banner <= 1'b0;   // 横幅发完，转入状态行
                        fld       <= 0;
                        pos       <= 0;
                    end
                    else begin
                        bidx <= bidx + 1'b1;
                    end
                    st_r <= ST_LOAD;
                end
                else if (pos != POS_LAST) begin
                    pos  <= pos + 1'b1;      // 同一行下一个字符
                    st_r <= ST_LOAD;
                end
                else if (fld != FLD_LAST) begin
                    pos  <= 0;               // 下一行
                    fld  <= fld + 1'b1;
                    st_r <= ST_LOAD;
                end
                else begin
                    run_sec <= run_sec + 32'd1;  // 一轮打完，秒数 +1
                    st_r    <= ST_TICK;
                end
            end
        end
        default: st_r <= ST_TICK;
        endcase
    end

    //------------------------------------------------------------------
    // 底层 UART 发送器（官方 uart_tx.v，未修改）
    //   注意：uart_tx 的 CLK_FRE 单位是 MHz，所以传 CLK_HZ/1000000 = 50
    //------------------------------------------------------------------
    uart_tx #(
        .CLK_FRE   (CLK_HZ / 1000000),
        .BAUD_RATE (BAUD)
    ) u_uart_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .tx_data       (tx_data),
        .tx_data_valid (tx_valid),
        .tx_data_ready (tx_ready),
        .tx_pin        (tx)
    );

endmodule
