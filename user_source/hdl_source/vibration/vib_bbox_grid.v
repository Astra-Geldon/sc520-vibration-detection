// Low-cost vibration bounding box helper.
//
// The frequency path supplies four confirmed slots and a qualified 6x8 map.
// One statistics engine visits the valid slots round-robin, with independent
// coordinates and temporal history for each slot. Empty slots are skipped.
// Multi-target visits occasionally repeat the previous slot for one frame,
// shifting later visits away from a fixed vibration phase without blank frames.
// This block counts joint frame-difference/edge evidence only in the seed's
// 3x3 search neighbourhood and only for parent cells admitted by that map.
// The local 6x6 fine grid is a 12x16-equivalent spatial refinement; it never
// enters the Goertzel path. Pixel extrema are intentionally absent from the
// streaming path.
`ifndef VIB_BBOX_GRID_V
`define VIB_BBOX_GRID_V
(* dsp_style = "no" *)
module vib_bbox_grid #(
    parameter [8:0]  DIFF_THR        = 9'd8,
    parameter [8:0]  EDGE_THR        = 9'd20,
    parameter [17:0] MIN_JOINT      = 18'd32,
    parameter [9:0]  MARGIN_X       = 10'd4,
    parameter [9:0]  MARGIN_Y       = 10'd4,
    parameter [12:0] GRID_JOINT_THR = 13'd24,
    parameter [11:0] EDGE_SUB_THR   = 12'd24
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_px_valid,
    input  wire [8:0]  i_px_diff,
    input  wire [8:0]  i_px_edge,
    input  wire [9:0]  i_px_x,
    input  wire [9:0]  i_px_y,
    input  wire [31:0] i_obj_pos,
    // Qualified 6x8 parent-cell map from the frequency stage.
    // Bit n is row*8+col. The map is latched at frame start so the
    // streaming bbox path sees one stable decision for the whole frame.
    input  wire [47:0] i_tonal_map,
    // Five-bit frequency bin for every parent cell.  31 denotes invalid.
    input  wire [239:0] i_tonal_bins,
    // Packed in the same slot order as i_obj_pos (slot 1 in low bits).
    output wire [43:0] o_x0,
    output wire [39:0] o_y0,
    output wire [43:0] o_x1,
    output wire [39:0] o_y1,
    output reg  [3:0]  o_vld,
    output reg         o_tgl
);
    localparam [9:0] LAST_X = 10'd639;
    localparam [9:0] LAST_Y = 10'd359;

    // Only threshold crossings are consumed below; counts need not retain
    // values above their threshold. Keep parameter overrides Verilog-2001 safe.
    function integer count_width;
        input [31:0] threshold;
        reg [31:0] remaining;
        begin
            remaining = threshold;
            count_width = 1;
            while (remaining > 1) begin
                remaining = remaining >> 1;
                count_width = count_width + 1;
            end
        end
    endfunction
    localparam integer GRID_COUNT_W = count_width(GRID_JOINT_THR);
    localparam integer EDGE_COUNT_W = count_width(EDGE_SUB_THR);
    localparam integer HIT_COUNT_W = count_width(MIN_JOINT);

    wire frame_first = i_px_valid && (i_px_x == 10'd0) && (i_px_y == 10'd0);
    wire frame_last  = i_px_valid && (i_px_x == LAST_X) && (i_px_y == LAST_Y);

    function [1:0] next_valid_slot;
        input [31:0] p;
        input [1:0] start_slot;
        reg [1:0] probe;
        reg found;
        integer n;
        begin
            next_valid_slot = start_slot;
            found = 1'b0;
            for (n=0; n<4; n=n+1) begin
                probe = start_slot + n;
                if (!found && p[probe*8+6]) begin
                    next_valid_slot = probe;
                    found = 1'b1;
                end
            end
        end
    endfunction

    function cell_close;
        input [5:0] a, b;
        reg [2:0] dr, dc;
        begin
            dr = (a[5:3] >= b[5:3]) ? a[5:3]-b[5:3] : b[5:3]-a[5:3];
            dc = (a[2:0] >= b[2:0]) ? a[2:0]-b[2:0] : b[2:0]-a[2:0];
            cell_close = (dr <= 3'd1) && (dc <= 3'd1);
        end
    endfunction

    reg [1:0] round_robin_slot, seed_slot;
    reg [2:0] visit_phase;
    reg [7:0] seed_pos;
    reg [4:0] seed_bin;
    reg [47:0] tonal_map_r;
    reg [47:0] same_freq_map_r;

    function freq_bin_close;
        input [4:0] a;
        input [4:0] b;
        reg [4:0] d;
        begin
            if ((a == 5'd31) || (b == 5'd31)) freq_bin_close = 1'b0;
            else begin
                d = (a >= b) ? (a - b) : (b - a);
                freq_bin_close = (d <= 5'd1);
            end
        end
    endfunction

    wire [3:0] published_slots = {i_obj_pos[30], i_obj_pos[22],
                                  i_obj_pos[14], i_obj_pos[6]};
    wire multiple_slots = |(published_slots & (published_slots - 4'd1));
    // Seven normal visits followed by one repeat. With 2/3/4 fixed slots,
    // the repeated slot rotates, service stays balanced and the longest
    // interval grows by at most one frame. A single target is never delayed.
    wire repeat_visit = multiple_slots && (visit_phase == 3'd7) &&
                        published_slots[seed_slot];
    wire [1:0] input_slot = repeat_visit ? seed_slot :
                           next_valid_slot(i_obj_pos, round_robin_slot);
    wire [7:0] input_seed_pos = i_obj_pos[input_slot*8+:8];
    wire [5:0] input_seed_cell = input_seed_pos[5:0];
    wire [4:0] input_seed_bin = i_tonal_bins[(input_seed_cell*5)+:5];
    wire seed_valid = seed_pos[6];
    wire [2:0] seed_row = seed_pos[5:3];
    wire [2:0] seed_col = seed_pos[2:0];

    reg [2:0] cell_col, cell_row;
    always @(*) begin
        if      (i_px_x < 10'd80)  cell_col = 3'd0;
        else if (i_px_x < 10'd160) cell_col = 3'd1;
        else if (i_px_x < 10'd240) cell_col = 3'd2;
        else if (i_px_x < 10'd320) cell_col = 3'd3;
        else if (i_px_x < 10'd400) cell_col = 3'd4;
        else if (i_px_x < 10'd480) cell_col = 3'd5;
        else if (i_px_x < 10'd560) cell_col = 3'd6;
        else                       cell_col = 3'd7;

        if      (i_px_y < 10'd60)  cell_row = 3'd0;
        else if (i_px_y < 10'd120) cell_row = 3'd1;
        else if (i_px_y < 10'd180) cell_row = 3'd2;
        else if (i_px_y < 10'd240) cell_row = 3'd3;
        else if (i_px_y < 10'd300) cell_row = 3'd4;
        else                       cell_row = 3'd5;
    end

    wire [2:0] row_delta = (cell_row >= seed_row) ?
                           (cell_row - seed_row) : (seed_row - cell_row);
    wire [2:0] col_delta = (cell_col >= seed_col) ?
                           (cell_col - seed_col) : (seed_col - cell_col);
    wire seed_cell = (cell_row == seed_row) && (cell_col == seed_col);
    wire tonal_map_present = |tonal_map_r;
    wire parent_freq_ok = seed_cell ||
                          (tonal_map_present && tonal_map_r[{cell_row,cell_col}] &&
                           same_freq_map_r[{cell_row,cell_col}]);
    // The 3x3 area remains a search window, but only parent cells with a
    // qualified frequency (plus the seed itself) can contribute to the box.
    wire roi_ok = seed_valid && parent_freq_ok &&
                  (row_delta <= 3'd1) && (col_delta <= 3'd1);
    wire diff_hit = i_px_diff >= DIFF_THR;
    wire edge_hit = i_px_edge >= EDGE_THR;
    wire joint_hit = i_px_valid && roi_ok && diff_hit && edge_hit;

    // Map signed neighbourhood offsets (-1,0,+1) to safe 0..2 indices.
    wire [1:0] roi_row = (cell_row < seed_row) ? 2'd0 :
                         ((cell_row == seed_row) ? 2'd1 : 2'd2);
    wire [1:0] roi_col = (cell_col < seed_col) ? 2'd0 :
                         ((cell_col == seed_col) ? 2'd1 : 2'd2);
    wire [3:0] roi_idx = {2'b0,roi_row} * 4'd3 + {2'b0,roi_col};

    // The 3x3 locator ROI is split into 6x6 40x30 algorithm-pixel subcells.
    // This is the local equivalent of a 12x16 fine grid: every 6x8 parent
    // cell contributes 2x2 fine cells. The fine grid never enters Goertzel.
    function [9:0] roi_x_base;
        input [2:0] c;
        begin
            case (c)
              3'd0,3'd1: roi_x_base = 10'd0;
              3'd2: roi_x_base = 10'd80;
              3'd3: roi_x_base = 10'd160;
              3'd4: roi_x_base = 10'd240;
              3'd5: roi_x_base = 10'd320;
              3'd6: roi_x_base = 10'd400;
              default: roi_x_base = 10'd480;
            endcase
        end
    endfunction
    function [9:0] roi_y_base;
        input [2:0] r;
        begin
            case (r)
              3'd0,3'd1: roi_y_base = 10'd0;
              3'd2: roi_y_base = 10'd60;
              3'd3: roi_y_base = 10'd120;
              3'd4: roi_y_base = 10'd180;
              default: roi_y_base = 10'd240;
            endcase
        end
    endfunction
    wire [9:0] roi_x0_stream = roi_x_base(seed_col);
    wire [9:0] roi_y0_stream = roi_y_base(seed_row);
    wire [9:0] roi_dx = i_px_x - roi_x0_stream;
    wire [9:0] roi_dy = i_px_y - roi_y0_stream;
    reg [2:0] edge_sub_col, edge_sub_row;
    always @(*) begin
        if      (roi_dx < 10'd40)  edge_sub_col = 3'd0;
        else if (roi_dx < 10'd80)  edge_sub_col = 3'd1;
        else if (roi_dx < 10'd120) edge_sub_col = 3'd2;
        else if (roi_dx < 10'd160) edge_sub_col = 3'd3;
        else if (roi_dx < 10'd200) edge_sub_col = 3'd4;
        else                       edge_sub_col = 3'd5;
        if      (roi_dy < 10'd30)  edge_sub_row = 3'd0;
        else if (roi_dy < 10'd60)  edge_sub_row = 3'd1;
        else if (roi_dy < 10'd90)  edge_sub_row = 3'd2;
        else if (roi_dy < 10'd120) edge_sub_row = 3'd3;
        else if (roi_dy < 10'd150) edge_sub_row = 3'd4;
        else                       edge_sub_row = 3'd5;
    end
    wire [5:0] edge_sub_idx = edge_sub_row * 6 + edge_sub_col;
    // The coarse-cell locator is the spatial gate. This avoids letting a
    // screen edge outside the selected 3x3 neighbourhood size the box.
    // Static screen lines alone are not enough. Fine-cell support must be
    // present at the same pixel as the frame difference and edge response.
    wire edge_sub_hit = joint_hit;

    // Nine parent counters plus 36 fine-cell counters are the only per-pixel
    // grid state. The fine counters are joint diff+edge support, so static
    // screen lines cannot size the box by themselves.
    reg [GRID_COUNT_W-1:0] cell_joint [0:8];
    reg [EDGE_COUNT_W-1:0] edge_sub_count [0:35];
    wire [8:0] support_mask_c = {
        (cell_joint[8] >= GRID_JOINT_THR), (cell_joint[7] >= GRID_JOINT_THR),
        (cell_joint[6] >= GRID_JOINT_THR), (cell_joint[5] >= GRID_JOINT_THR),
        (cell_joint[4] >= GRID_JOINT_THR), (cell_joint[3] >= GRID_JOINT_THR),
        (cell_joint[2] >= GRID_JOINT_THR), (cell_joint[1] >= GRID_JOINT_THR),
        (cell_joint[0] >= GRID_JOINT_THR)
    };
    reg [8:0]  support_mask_r;
    reg [7:0]  support_seed_r;
    reg [1:0]  support_slot_r;
    reg [4:0]  support_bin_r;
    reg        support_ready;
    reg [HIT_COUNT_W-1:0] support_hit_count_r;
    reg [35:0] edge_support_mask_c;
    integer edge_mask_i;
    always @(*) begin
        edge_support_mask_c = 36'd0;
        for (edge_mask_i=0; edge_mask_i<36; edge_mask_i=edge_mask_i+1)
            edge_support_mask_c[edge_mask_i] =
                (edge_sub_count[edge_mask_i] >= EDGE_SUB_THR);
    end
    reg [35:0] edge_support_mask_r;
    reg [7:0] edge_seed_r;

    wire edge_support_found = |edge_support_mask_r;
    wire edge_sup_row0 = |edge_support_mask_r[5:0];
    wire edge_sup_row1 = |edge_support_mask_r[11:6];
    wire edge_sup_row2 = |edge_support_mask_r[17:12];
    wire edge_sup_row3 = |edge_support_mask_r[23:18];
    wire edge_sup_row4 = |edge_support_mask_r[29:24];
    wire edge_sup_row5 = |edge_support_mask_r[35:30];
    wire edge_sup_col0 = edge_support_mask_r[0]  | edge_support_mask_r[6]  |
                         edge_support_mask_r[12] | edge_support_mask_r[18] |
                         edge_support_mask_r[24] | edge_support_mask_r[30];
    wire edge_sup_col1 = edge_support_mask_r[1]  | edge_support_mask_r[7]  |
                         edge_support_mask_r[13] | edge_support_mask_r[19] |
                         edge_support_mask_r[25] | edge_support_mask_r[31];
    wire edge_sup_col2 = edge_support_mask_r[2]  | edge_support_mask_r[8]  |
                         edge_support_mask_r[14] | edge_support_mask_r[20] |
                         edge_support_mask_r[26] | edge_support_mask_r[32];
    wire edge_sup_col3 = edge_support_mask_r[3]  | edge_support_mask_r[9]  |
                         edge_support_mask_r[15] | edge_support_mask_r[21] |
                         edge_support_mask_r[27] | edge_support_mask_r[33];
    wire edge_sup_col4 = edge_support_mask_r[4]  | edge_support_mask_r[10] |
                         edge_support_mask_r[16] | edge_support_mask_r[22] |
                         edge_support_mask_r[28] | edge_support_mask_r[34];
    wire edge_sup_col5 = edge_support_mask_r[5]  | edge_support_mask_r[11] |
                         edge_support_mask_r[17] | edge_support_mask_r[23] |
                         edge_support_mask_r[29] | edge_support_mask_r[35];
    reg [2:0] edge_min_row, edge_max_row, edge_min_col, edge_max_col;
    always @(*) begin
        if      (edge_sup_row0) edge_min_row = 3'd0;
        else if (edge_sup_row1) edge_min_row = 3'd1;
        else if (edge_sup_row2) edge_min_row = 3'd2;
        else if (edge_sup_row3) edge_min_row = 3'd3;
        else if (edge_sup_row4) edge_min_row = 3'd4;
        else                    edge_min_row = 3'd5;
        if      (edge_sup_row5) edge_max_row = 3'd5;
        else if (edge_sup_row4) edge_max_row = 3'd4;
        else if (edge_sup_row3) edge_max_row = 3'd3;
        else if (edge_sup_row2) edge_max_row = 3'd2;
        else if (edge_sup_row1) edge_max_row = 3'd1;
        else                    edge_max_row = 3'd0;
        if      (edge_sup_col0) edge_min_col = 3'd0;
        else if (edge_sup_col1) edge_min_col = 3'd1;
        else if (edge_sup_col2) edge_min_col = 3'd2;
        else if (edge_sup_col3) edge_min_col = 3'd3;
        else if (edge_sup_col4) edge_min_col = 3'd4;
        else                    edge_min_col = 3'd5;
        if      (edge_sup_col5) edge_max_col = 3'd5;
        else if (edge_sup_col4) edge_max_col = 3'd4;
        else if (edge_sup_col3) edge_max_col = 3'd3;
        else if (edge_sup_col2) edge_max_col = 3'd2;
        else if (edge_sup_col1) edge_max_col = 3'd1;
        else                    edge_max_col = 3'd0;
    end

    function [9:0] edge_sub_x_offset;
        input [2:0] sub;
        begin
            case (sub)
              0: edge_sub_x_offset = 10'd0;
              1: edge_sub_x_offset = 10'd40;
              2: edge_sub_x_offset = 10'd80;
              3: edge_sub_x_offset = 10'd120;
              4: edge_sub_x_offset = 10'd160;
              default: edge_sub_x_offset = 10'd200;
            endcase
        end
    endfunction
    function [9:0] edge_sub_y_offset;
        input [2:0] sub;
        begin
            case (sub)
              0: edge_sub_y_offset = 10'd0;
              1: edge_sub_y_offset = 10'd30;
              2: edge_sub_y_offset = 10'd60;
              3: edge_sub_y_offset = 10'd90;
              4: edge_sub_y_offset = 10'd120;
              default: edge_sub_y_offset = 10'd150;
            endcase
        end
    endfunction
    wire [9:0] edge_roi_x0 = roi_x_base(edge_seed_r[2:0]);
    wire [9:0] edge_roi_y0 = roi_y_base(edge_seed_r[5:3]);
    wire [10:0] edge_min_x_ext = {1'b0,edge_roi_x0} +
                                  {1'b0,edge_sub_x_offset(edge_min_col)};
    wire [10:0] edge_max_x_ext = {1'b0,edge_roi_x0} +
                                  {1'b0,edge_sub_x_offset(edge_max_col)} + 11'd39;
    wire [10:0] edge_min_y_ext = {1'b0,edge_roi_y0} +
                                  {1'b0,edge_sub_y_offset(edge_min_row)};
    wire [10:0] edge_max_y_ext = {1'b0,edge_roi_y0} +
                                  {1'b0,edge_sub_y_offset(edge_max_row)} + 11'd29;
    wire [9:0] edge_bbox_min_x = (edge_min_x_ext > 11'd639) ? 10'd639 : edge_min_x_ext[9:0];
    wire [9:0] edge_bbox_max_x = (edge_max_x_ext > 11'd639) ? 10'd639 : edge_max_x_ext[9:0];
    wire [9:0] edge_bbox_min_y = (edge_min_y_ext > 11'd359) ? 10'd359 : edge_min_y_ext[9:0];
    wire [9:0] edge_bbox_max_y = (edge_max_y_ext > 11'd359) ? 10'd359 : edge_max_y_ext[9:0];

    wire support_found = |support_mask_r;

    function [9:0] cell_x_start;
        input [2:0] c;
        begin
            case (c)
              0:cell_x_start=0; 1:cell_x_start=80; 2:cell_x_start=160;
              3:cell_x_start=240; 4:cell_x_start=320; 5:cell_x_start=400;
              6:cell_x_start=480; default:cell_x_start=560;
            endcase
        end
    endfunction
    function [9:0] cell_x_end;
        input [2:0] c;
        begin
            case (c)
              0:cell_x_end=79; 1:cell_x_end=159; 2:cell_x_end=239;
              3:cell_x_end=319; 4:cell_x_end=399; 5:cell_x_end=479;
              6:cell_x_end=559; default:cell_x_end=639;
            endcase
        end
    endfunction
    function [9:0] cell_y_start;
        input [2:0] r;
        begin
            case (r)
              0:cell_y_start=0; 1:cell_y_start=60; 2:cell_y_start=120;
              3:cell_y_start=180; 4:cell_y_start=240; default:cell_y_start=300;
            endcase
        end
    endfunction
    function [9:0] cell_y_end;
        input [2:0] r;
        begin
            case (r)
              0:cell_y_end=59; 1:cell_y_end=119; 2:cell_y_end=179;
              3:cell_y_end=239; 4:cell_y_end=299; default:cell_y_end=359;
            endcase
        end
    endfunction

    // A coarse fallback is deliberately limited to the seed parent cell.
    // The 3x3 neighbourhood is a search window only; it must not turn a
    // small target into a fixed 3x3-cell box when fine evidence is missing.
    wire [9:0] coarse_bbox_min_x = cell_x_start(support_seed_r[2:0]);
    wire [9:0] coarse_bbox_max_x = cell_x_end(support_seed_r[2:0]);
    wire [9:0] coarse_bbox_min_y = cell_y_start(support_seed_r[5:3]);
    wire [9:0] coarse_bbox_max_y = cell_y_end(support_seed_r[5:3]);
    // Edge subcells determine the size whenever enough joint evidence exists;
    // the seed-cell box is the safe fallback for a broken contour.
    wire [9:0] bbox_min_x = edge_support_found ? edge_bbox_min_x : coarse_bbox_min_x;
    wire [9:0] bbox_max_x = edge_support_found ? edge_bbox_max_x : coarse_bbox_max_x;
    wire [9:0] bbox_min_y = edge_support_found ? edge_bbox_min_y : coarse_bbox_min_y;
    wire [9:0] bbox_max_y = edge_support_found ? edge_bbox_max_y : coarse_bbox_max_y;
    wire [9:0] bx0_lr = (bbox_min_x > MARGIN_X) ? bbox_min_x - MARGIN_X : 0;
    wire [9:0] by0_lr = (bbox_min_y > MARGIN_Y) ? bbox_min_y - MARGIN_Y : 0;
    wire [10:0] bx1_lr_ext = {1'b0,bbox_max_x} + {1'b0,MARGIN_X};
    wire [10:0] by1_lr_ext = {1'b0,bbox_max_y} + {1'b0,MARGIN_Y};
    wire [9:0] bx1_lr = (bx1_lr_ext > 639) ? 639 : bx1_lr_ext[9:0];
    wire [9:0] by1_lr = (by1_lr_ext > 359) ? 359 : by1_lr_ext[9:0];
    wire [10:0] cand_x0 = {bx0_lr,1'b0};
    wire [9:0]  cand_y0 = {by0_lr,1'b0};
    wire [10:0] cand_x1 = {bx1_lr,1'b0} | 1;
    wire [9:0]  cand_y1 = {by1_lr,1'b0} | 1;
    wire frame_bbox_valid = support_found &&
                            (support_hit_count_r >= MIN_JOINT) &&
                            support_seed_r[6];

    function [10:0] move_x_edge;
        input [10:0] old_v; input [10:0] new_v;
        reg [12:0] delta; reg [12:0] step;
        begin
            if (new_v > old_v) begin
                delta=new_v-old_v; step=delta>>2; if(step==0)step=1;
                if(step>32)step=32; if(step>delta)step=delta;
                move_x_edge=old_v+step[10:0];
            end else if (old_v > new_v) begin
                delta=old_v-new_v; step=delta>>2; if(step==0)step=1;
                if(step>32)step=32; if(step>delta)step=delta;
                move_x_edge=old_v-step[10:0];
            end else move_x_edge=old_v;
        end
    endfunction
    function [9:0] move_y_edge;
        input [9:0] old_v; input [9:0] new_v;
        reg [11:0] delta; reg [11:0] step;
        begin
            if (new_v > old_v) begin
                delta=new_v-old_v; step=delta>>2; if(step==0)step=1;
                if(step>24)step=24; if(step>delta)step=delta;
                move_y_edge=old_v+step[9:0];
            end else if (old_v > new_v) begin
                delta=old_v-new_v; step=delta>>2; if(step==0)step=1;
                if(step>24)step=24; if(step>delta)step=delta;
                move_y_edge=old_v-step[9:0];
            end else move_y_edge=old_v;
        end
    endfunction

    reg [HIT_COUNT_W-1:0] hit_count;
    wire [HIT_COUNT_W-1:0] hit_count_n = joint_hit && (hit_count < MIN_JOINT) ?
                                       hit_count + 1'b1 : hit_count;
    reg [10:0] track_x0 [0:3], track_x1 [0:3];
    reg [9:0] track_y0 [0:3], track_y1 [0:3];
    reg [5:0] track_cell [0:3];
    reg [4:0] track_bin [0:3];
    reg [3:0] track_valid;
    reg [1:0] x0_grow_cnt [0:3], x0_shrink_cnt [0:3];
    reg [1:0] x1_grow_cnt [0:3], x1_shrink_cnt [0:3];
    reg [1:0] y0_grow_cnt [0:3], y0_shrink_cnt [0:3];
    reg [1:0] y1_grow_cnt [0:3], y1_shrink_cnt [0:3];
    // Evidence misses count visits to this slot, never visits to other slots.
    // A missing frequency slot ages once per video frame and is hidden at once.
    reg [1:0] bbox_miss_cnt [0:3], slot_miss_cnt [0:3];
    genvar output_slot;
    generate for (output_slot=0; output_slot<4; output_slot=output_slot+1) begin:g_track_outputs
        assign o_x0[output_slot*11+:11] = track_x0[output_slot];
        assign o_x1[output_slot*11+:11] = track_x1[output_slot];
        assign o_y0[output_slot*10+:10] = track_y0[output_slot];
        assign o_y1[output_slot*10+:10] = track_y1[output_slot];
    end endgenerate

    // Recheck delayed evidence against the CURRENT published slot. A completed
    // measurement cannot resurrect a vanished, pending or reused identity.
    wire [7:0] live_support_pos = i_obj_pos[support_slot_r*8+:8];
    wire [4:0] live_support_bin = i_tonal_bins[live_support_pos[5:0]*5+:5];
    wire candidate_current = support_ready && live_support_pos[6] &&
                             cell_close(support_seed_r[5:0], live_support_pos[5:0]) &&
                             freq_bin_close(support_bin_r, live_support_bin);
    wire history_continues = track_valid[support_slot_r] &&
                             cell_close(track_cell[support_slot_r], support_seed_r[5:0]) &&
                             freq_bin_close(track_bin[support_slot_r], support_bin_r);
    wire [3:0] slot_live_valid, slot_identity_current;
    genvar live_slot;
    generate for (live_slot=0; live_slot<4; live_slot=live_slot+1) begin:g_live_slots
        wire [5:0] live_cell = i_obj_pos[live_slot*8+:6];
        wire [4:0] live_bin = i_tonal_bins[live_cell*5+:5];
        assign slot_live_valid[live_slot] = i_obj_pos[live_slot*8+6];
        assign slot_identity_current[live_slot] =
            cell_close(track_cell[live_slot], live_cell) &&
            freq_bin_close(track_bin[live_slot], live_bin);
    end endgenerate

    // Select history BEFORE the arithmetic: all slots share four smoothers.
    wire [10:0] old_x0 = track_x0[support_slot_r];
    wire [10:0] old_x1 = track_x1[support_slot_r];
    wire [9:0] old_y0 = track_y0[support_slot_r];
    wire [9:0] old_y1 = track_y1[support_slot_r];
    wire [10:0] moved_x0 = move_x_edge(old_x0, cand_x0);
    wire [10:0] moved_x1 = move_x_edge(old_x1, cand_x1);
    wire [9:0] moved_y0 = move_y_edge(old_y0, cand_y0);
    wire [9:0] moved_y1 = move_y_edge(old_y1, cand_y1);
    integer reset_i, track_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            round_robin_slot<=0; seed_slot<=0; seed_bin<=5'd31; visit_phase<=0;
            seed_pos<=0; tonal_map_r<=0; same_freq_map_r<=0; hit_count<=0; support_mask_r<=0; support_seed_r<=0;
            support_hit_count_r<=0; support_slot_r<=0; support_bin_r<=5'd31; support_ready<=0;
            track_valid<=0;
            for (track_i=0; track_i<4; track_i=track_i+1) begin
                track_x0[track_i]<=0; track_x1[track_i]<=0;
                track_y0[track_i]<=0; track_y1[track_i]<=0;
                track_cell[track_i]<=0; track_bin[track_i]<=5'd31;
                bbox_miss_cnt[track_i]<=0; slot_miss_cnt[track_i]<=0;
                x0_grow_cnt[track_i]<=0; x0_shrink_cnt[track_i]<=0;
                x1_grow_cnt[track_i]<=0; x1_shrink_cnt[track_i]<=0;
                y0_grow_cnt[track_i]<=0; y0_shrink_cnt[track_i]<=0;
                y1_grow_cnt[track_i]<=0; y1_shrink_cnt[track_i]<=0;
            end
            for (reset_i=0; reset_i<9; reset_i=reset_i+1) cell_joint[reset_i]<=0;
            for (reset_i=0; reset_i<36; reset_i=reset_i+1) edge_sub_count[reset_i]<=0;
            edge_support_mask_r <= 36'd0;
            edge_seed_r <= 8'd0;
            o_vld<=0; o_tgl<=0;
        end else if (i_px_valid) begin
            if (frame_first) begin
                if (!repeat_visit) round_robin_slot <= input_slot + 2'd1;
                visit_phase <= multiple_slots ? visit_phase + 3'd1 : 3'd0;
                seed_slot <= input_slot;
                seed_pos <= input_seed_pos;
                seed_bin <= input_seed_bin;
                tonal_map_r <= i_tonal_map;
                for (reset_i=0; reset_i<48; reset_i=reset_i+1)
                    same_freq_map_r[reset_i] <= i_tonal_map[reset_i] &&
                                                freq_bin_close(i_tonal_bins[(reset_i*5)+:5],
                                                               input_seed_bin);
                hit_count <= 0;
                for (reset_i=0; reset_i<9; reset_i=reset_i+1) cell_joint[reset_i]<=0;
                for (reset_i=0; reset_i<36; reset_i=reset_i+1) edge_sub_count[reset_i]<=0;
            end else begin
                hit_count <= hit_count_n;
                if (joint_hit) begin
                    case (roi_idx)
                      0: if(cell_joint[0]<GRID_JOINT_THR) cell_joint[0]<=cell_joint[0]+1'b1;
                      1: if(cell_joint[1]<GRID_JOINT_THR) cell_joint[1]<=cell_joint[1]+1'b1;
                      2: if(cell_joint[2]<GRID_JOINT_THR) cell_joint[2]<=cell_joint[2]+1'b1;
                      3: if(cell_joint[3]<GRID_JOINT_THR) cell_joint[3]<=cell_joint[3]+1'b1;
                      4: if(cell_joint[4]<GRID_JOINT_THR) cell_joint[4]<=cell_joint[4]+1'b1;
                      5: if(cell_joint[5]<GRID_JOINT_THR) cell_joint[5]<=cell_joint[5]+1'b1;
                      6: if(cell_joint[6]<GRID_JOINT_THR) cell_joint[6]<=cell_joint[6]+1'b1;
                      7: if(cell_joint[7]<GRID_JOINT_THR) cell_joint[7]<=cell_joint[7]+1'b1;
                      default: if(cell_joint[8]<GRID_JOINT_THR) cell_joint[8]<=cell_joint[8]+1'b1;
                    endcase
                end
                if (edge_sub_hit) begin
                    case (edge_sub_idx)
                      6'd0:  if(edge_sub_count[0]  < EDGE_SUB_THR) edge_sub_count[0]  <= edge_sub_count[0]  + 1'b1;
                      6'd1:  if(edge_sub_count[1]  < EDGE_SUB_THR) edge_sub_count[1]  <= edge_sub_count[1]  + 1'b1;
                      6'd2:  if(edge_sub_count[2]  < EDGE_SUB_THR) edge_sub_count[2]  <= edge_sub_count[2]  + 1'b1;
                      6'd3:  if(edge_sub_count[3]  < EDGE_SUB_THR) edge_sub_count[3]  <= edge_sub_count[3]  + 1'b1;
                      6'd4:  if(edge_sub_count[4]  < EDGE_SUB_THR) edge_sub_count[4]  <= edge_sub_count[4]  + 1'b1;
                      6'd5:  if(edge_sub_count[5]  < EDGE_SUB_THR) edge_sub_count[5]  <= edge_sub_count[5]  + 1'b1;
                      6'd6:  if(edge_sub_count[6]  < EDGE_SUB_THR) edge_sub_count[6]  <= edge_sub_count[6]  + 1'b1;
                      6'd7:  if(edge_sub_count[7]  < EDGE_SUB_THR) edge_sub_count[7]  <= edge_sub_count[7]  + 1'b1;
                      6'd8:  if(edge_sub_count[8]  < EDGE_SUB_THR) edge_sub_count[8]  <= edge_sub_count[8]  + 1'b1;
                      6'd9:  if(edge_sub_count[9]  < EDGE_SUB_THR) edge_sub_count[9]  <= edge_sub_count[9]  + 1'b1;
                      6'd10: if(edge_sub_count[10] < EDGE_SUB_THR) edge_sub_count[10] <= edge_sub_count[10] + 1'b1;
                      6'd11: if(edge_sub_count[11] < EDGE_SUB_THR) edge_sub_count[11] <= edge_sub_count[11] + 1'b1;
                      6'd12: if(edge_sub_count[12] < EDGE_SUB_THR) edge_sub_count[12] <= edge_sub_count[12] + 1'b1;
                      6'd13: if(edge_sub_count[13] < EDGE_SUB_THR) edge_sub_count[13] <= edge_sub_count[13] + 1'b1;
                      6'd14: if(edge_sub_count[14] < EDGE_SUB_THR) edge_sub_count[14] <= edge_sub_count[14] + 1'b1;
                      6'd15: if(edge_sub_count[15] < EDGE_SUB_THR) edge_sub_count[15] <= edge_sub_count[15] + 1'b1;
                      6'd16: if(edge_sub_count[16] < EDGE_SUB_THR) edge_sub_count[16] <= edge_sub_count[16] + 1'b1;
                      6'd17: if(edge_sub_count[17] < EDGE_SUB_THR) edge_sub_count[17] <= edge_sub_count[17] + 1'b1;
                      6'd18: if(edge_sub_count[18] < EDGE_SUB_THR) edge_sub_count[18] <= edge_sub_count[18] + 1'b1;
                      6'd19: if(edge_sub_count[19] < EDGE_SUB_THR) edge_sub_count[19] <= edge_sub_count[19] + 1'b1;
                      6'd20: if(edge_sub_count[20] < EDGE_SUB_THR) edge_sub_count[20] <= edge_sub_count[20] + 1'b1;
                      6'd21: if(edge_sub_count[21] < EDGE_SUB_THR) edge_sub_count[21] <= edge_sub_count[21] + 1'b1;
                      6'd22: if(edge_sub_count[22] < EDGE_SUB_THR) edge_sub_count[22] <= edge_sub_count[22] + 1'b1;
                      6'd23: if(edge_sub_count[23] < EDGE_SUB_THR) edge_sub_count[23] <= edge_sub_count[23] + 1'b1;
                      6'd24: if(edge_sub_count[24] < EDGE_SUB_THR) edge_sub_count[24] <= edge_sub_count[24] + 1'b1;
                      6'd25: if(edge_sub_count[25] < EDGE_SUB_THR) edge_sub_count[25] <= edge_sub_count[25] + 1'b1;
                      6'd26: if(edge_sub_count[26] < EDGE_SUB_THR) edge_sub_count[26] <= edge_sub_count[26] + 1'b1;
                      6'd27: if(edge_sub_count[27] < EDGE_SUB_THR) edge_sub_count[27] <= edge_sub_count[27] + 1'b1;
                      6'd28: if(edge_sub_count[28] < EDGE_SUB_THR) edge_sub_count[28] <= edge_sub_count[28] + 1'b1;
                      6'd29: if(edge_sub_count[29] < EDGE_SUB_THR) edge_sub_count[29] <= edge_sub_count[29] + 1'b1;
                      6'd30: if(edge_sub_count[30] < EDGE_SUB_THR) edge_sub_count[30] <= edge_sub_count[30] + 1'b1;
                      6'd31: if(edge_sub_count[31] < EDGE_SUB_THR) edge_sub_count[31] <= edge_sub_count[31] + 1'b1;
                      6'd32: if(edge_sub_count[32] < EDGE_SUB_THR) edge_sub_count[32] <= edge_sub_count[32] + 1'b1;
                      6'd33: if(edge_sub_count[33] < EDGE_SUB_THR) edge_sub_count[33] <= edge_sub_count[33] + 1'b1;
                      6'd34: if(edge_sub_count[34] < EDGE_SUB_THR) edge_sub_count[34] <= edge_sub_count[34] + 1'b1;
                      default: if(edge_sub_count[35] < EDGE_SUB_THR) edge_sub_count[35] <= edge_sub_count[35] + 1'b1;
                    endcase
                end
            end

            if (frame_last) begin
                // These registers decouple the stream from the overlay by
                // one frame. The last pixel is intentionally not needed for
                // a 24-hit support decision.
                support_mask_r <= support_mask_c;
                support_seed_r <= seed_pos;
                support_slot_r <= seed_slot;
                support_bin_r <= seed_bin;
                support_ready <= seed_valid;
                support_hit_count_r <= hit_count_n;
                edge_support_mask_r <= edge_support_mask_c;
                edge_seed_r <= seed_pos;

                for (track_i=0; track_i<4; track_i=track_i+1) begin
                    if (frame_bbox_valid && candidate_current && (support_slot_r==track_i)) begin
                        bbox_miss_cnt[track_i]<=0; slot_miss_cnt[track_i]<=0;
                        track_cell[track_i]<=support_seed_r[5:0];
                        track_bin[track_i]<=support_bin_r;
                        track_valid[track_i]<=1'b1; o_vld[track_i]<=1'b1;
                        if (!history_continues) begin
                            // New identity: initialize at its own measurement,
                            // never drag an unrelated old box across the image.
                            track_x0[track_i]<=cand_x0; track_x1[track_i]<=cand_x1;
                            track_y0[track_i]<=cand_y0; track_y1[track_i]<=cand_y1;
                            x0_grow_cnt[track_i]<=0; x0_shrink_cnt[track_i]<=0;
                            x1_grow_cnt[track_i]<=0; x1_shrink_cnt[track_i]<=0;
                            y0_grow_cnt[track_i]<=0; y0_shrink_cnt[track_i]<=0;
                            y1_grow_cnt[track_i]<=0; y1_shrink_cnt[track_i]<=0;
                        end else begin
                            if(cand_x0<old_x0) begin
                                x0_shrink_cnt[track_i]<=0;
                                if(x0_grow_cnt[track_i]<2) x0_grow_cnt[track_i]<=x0_grow_cnt[track_i]+1'b1;
                                if(x0_grow_cnt[track_i]>=1) track_x0[track_i]<=moved_x0;
                            end else if(cand_x0>old_x0) begin
                                x0_grow_cnt[track_i]<=0;
                                if(x0_shrink_cnt[track_i]<3) x0_shrink_cnt[track_i]<=x0_shrink_cnt[track_i]+1'b1;
                                if(x0_shrink_cnt[track_i]>=2) track_x0[track_i]<=moved_x0;
                            end else begin x0_grow_cnt[track_i]<=0; x0_shrink_cnt[track_i]<=0; end
                            if(cand_x1>old_x1) begin
                                x1_shrink_cnt[track_i]<=0;
                                if(x1_grow_cnt[track_i]<2) x1_grow_cnt[track_i]<=x1_grow_cnt[track_i]+1'b1;
                                if(x1_grow_cnt[track_i]>=1) track_x1[track_i]<=moved_x1;
                            end else if(cand_x1<old_x1) begin
                                x1_grow_cnt[track_i]<=0;
                                if(x1_shrink_cnt[track_i]<3) x1_shrink_cnt[track_i]<=x1_shrink_cnt[track_i]+1'b1;
                                if(x1_shrink_cnt[track_i]>=2) track_x1[track_i]<=moved_x1;
                            end else begin x1_grow_cnt[track_i]<=0; x1_shrink_cnt[track_i]<=0; end
                            if(cand_y0<old_y0) begin
                                y0_shrink_cnt[track_i]<=0;
                                if(y0_grow_cnt[track_i]<2) y0_grow_cnt[track_i]<=y0_grow_cnt[track_i]+1'b1;
                                if(y0_grow_cnt[track_i]>=1) track_y0[track_i]<=moved_y0;
                            end else if(cand_y0>old_y0) begin
                                y0_grow_cnt[track_i]<=0;
                                if(y0_shrink_cnt[track_i]<3) y0_shrink_cnt[track_i]<=y0_shrink_cnt[track_i]+1'b1;
                                if(y0_shrink_cnt[track_i]>=2) track_y0[track_i]<=moved_y0;
                            end else begin y0_grow_cnt[track_i]<=0; y0_shrink_cnt[track_i]<=0; end
                            if(cand_y1>old_y1) begin
                                y1_shrink_cnt[track_i]<=0;
                                if(y1_grow_cnt[track_i]<2) y1_grow_cnt[track_i]<=y1_grow_cnt[track_i]+1'b1;
                                if(y1_grow_cnt[track_i]>=1) track_y1[track_i]<=moved_y1;
                            end else if(cand_y1<old_y1) begin
                                y1_grow_cnt[track_i]<=0;
                                if(y1_shrink_cnt[track_i]<3) y1_shrink_cnt[track_i]<=y1_shrink_cnt[track_i]+1'b1;
                                if(y1_shrink_cnt[track_i]>=2) track_y1[track_i]<=moved_y1;
                            end else begin y1_grow_cnt[track_i]<=0; y1_shrink_cnt[track_i]<=0; end
                        end
                    end else begin
                        // Pending/lost frequency slots are hidden immediately.
                        // History is private and expires after three frames.
                        o_vld[track_i]<=track_valid[track_i] && slot_live_valid[track_i] &&
                                         slot_identity_current[track_i];
                        if (!slot_live_valid[track_i]) begin
                            if(slot_miss_cnt[track_i]<3) slot_miss_cnt[track_i]<=slot_miss_cnt[track_i]+1'b1;
                            if(slot_miss_cnt[track_i]>=2) track_valid[track_i]<=0;
                        end else begin
                            slot_miss_cnt[track_i]<=0;
                            if (track_valid[track_i] && !slot_identity_current[track_i]) begin
                                track_valid[track_i]<=0;
                            end else if (support_ready && (support_slot_r==track_i)) begin
                                if(bbox_miss_cnt[track_i]<3) bbox_miss_cnt[track_i]<=bbox_miss_cnt[track_i]+1'b1;
                                if(bbox_miss_cnt[track_i]>=2) begin
                                    track_valid[track_i]<=0; o_vld[track_i]<=0;
                                end
                            end
                        end
                        // Unvisited slots keep their temporal evidence. Only
                        // a miss for THIS slot breaks consecutive edge support.
                        if (!slot_live_valid[track_i] || !slot_identity_current[track_i] ||
                            (support_ready && (support_slot_r==track_i))) begin
                            x0_grow_cnt[track_i]<=0; x0_shrink_cnt[track_i]<=0;
                            x1_grow_cnt[track_i]<=0; x1_shrink_cnt[track_i]<=0;
                            y0_grow_cnt[track_i]<=0; y0_shrink_cnt[track_i]<=0;
                            y1_grow_cnt[track_i]<=0; y1_shrink_cnt[track_i]<=0;
                        end
                    end
                end
                o_tgl<=~o_tgl;
            end
        end
    end
endmodule
`endif
