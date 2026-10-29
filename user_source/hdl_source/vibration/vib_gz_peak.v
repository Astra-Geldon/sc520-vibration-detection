// 48-block spectrum scan and four independent grid targets.
// Basis: the user-verified OLD lab_ex1 project: synchronous state-read waits,
// shared energy multiplier, raw peak threshold and peak*7 > rest*2 admission.
// The failed reference's PN_FLOOR/rank-bound history/stable0 gate are removed.
// Input gain remains the current, coherently captured LK/AGC scale. Thresholds
// use peak>>8. 2026-10-28: raise only the absolute floor 25 -> 64:
// board static false boxes measured31/32; the measured real3Hz track>=924.
// This suppresses marginal peaks, not all disturbances/harmonics. Texture exponents
// are diagnostic only; they cannot truncate a valid peak out of admission.
// 2026-10-28: change confirmation only. Two matched windows both >=512
// confirm at the existing speed; all other qualified tracks need three.
// A single strong window cannot publish or lend strength to another slot.
// 2026-10-29 RVER00020009: widen state addresses to11bits and independently
// confirm a changed frequency in an already published, continuously matched
// slot. First changed-bin window is pending; a second identical bin publishes.
// No stale frequency is held during pending. Original acquisition/selection,
// thresholds and64-frame configuration remain unchanged.
// 2026-10-29 RVER0002000A extends active scan to27 bins,2..15Hz.
// RVER00020007 added read-only candidate diagnostics. Rescan only
// the global raw strongest block with the SAME multiplier to find the best
// non-neighbour bin. No diagnostic value feeds admission, picking or tracking.
// Included by design_top_wrapper.v; do not also register this file in .al.
`ifndef VIB_GZ_PEAK_V
`define VIB_GZ_PEAK_V
module vib_gz_peak #(
    parameter NBIN=27, parameter NB=48, parameter BIN_MIN=0,
    parameter integer TONE_RATIO=0,
    parameter integer COMMON_MOTION_ON=0
)(
    input wire clk, rst_n, trig,
    input wire i_motion_veto, // same completed window; latched only at trig
    input wire [5:0] i_fx_blk, // compatibility; no fixed-block master track
    input wire [39:0] i_axx_exp,
    input wire i_tick,
    input wire [2:0] i_row,
    output reg [10:0] st_addr,
    input wire [63:0] st_data,
    output reg busy, done,
    output reg [5:0] o_ntonal, // raw peak>64, before spectral prominence
    output reg [5:0] o_qact,   // raw peak>64 AND prominence, before confirmation
    output reg [5:0] o_best_blk,
    output reg [31:0] o_best_mag,
    output reg [4:0] o_best_bin,
    output reg [7:0] o_best_hz10,
    output reg [31:0] o_mb_bin0, o_mb_b12,
    output reg [31:0] o_fb2, o_fb4, o_fb8, o_fb12,
    output reg [31:0] o_tn, o_raw_hz, o_trk_pos,
    output reg [10:0] o_bb_x0, o_bb_y0, o_bb_x1, o_bb_y1,
    output reg o_bb_vld,
    output reg [31:0] o_obj_pos, o_obj_hz10,
    output reg [47:0] o_tonal_map,
    output reg [127:0] o_obj_pn, // compatibility name; RAW peak>>8, not normalized
    output reg [31:0] o_fx_pn,  // compatibility name; same RAW scale as PKMG
    output reg [31:0] o_scan_cnt,
    output reg [7:0] o_win_cnt,
    output reg [5:0] o_dbg_fx_sel, o_dbg_chal_blk,
    output reg [11:0] o_dbg_streak,
    output reg [4:0] o_dbg_aexp,
    output reg [2:0] o_confirmed,
    output reg [7:0] o_dbg_qual_hz10,
    output reg [31:0] o_dbg_qual_mag, o_dbg_qual_status,
    output reg [7:0] o_dbg_second_hz10,
    output reg [31:0] o_dbg_second_mag
);
    localparam integer MAG_SH=8;
    localparam [31:0] TONE_MIN=32'd64;
    localparam [31:0] STRONG_MIN=32'd512; // provisional RAW peak>>8 tier boundary
    function signed [15:0] coef_of;
        input [4:0] k;
        begin
            case(k)
            0:coef_of=16'sd32040; 1:coef_of=16'sd31633;
            2:coef_of=16'sd31137; 3:coef_of=16'sd30555;
            4:coef_of=16'sd29888; 5:coef_of=16'sd29137;
            6:coef_of=16'sd28306; 7:coef_of=16'sd27395;
            8:coef_of=16'sd26408; 9:coef_of=16'sd25347;
            10:coef_of=16'sd24216; 11:coef_of=16'sd23017;
            12:coef_of=16'sd21754; 13:coef_of=16'sd20431;
            14:coef_of=16'sd19050; 15:coef_of=16'sd17616;
            16:coef_of=16'sd16134; 17:coef_of=16'sd14606;
            18:coef_of=16'sd13038; 19:coef_of=16'sd11433;
            20:coef_of=16'sd9796;
            21:coef_of=16'sd8132; 22:coef_of=16'sd6446;
            23:coef_of=16'sd4741; 24:coef_of=16'sd3023;
            25:coef_of=16'sd1297; 26:coef_of=-16'sd433;
            default:coef_of=16'sd0;
            endcase
        end
    endfunction
    function [31:0] report_mag;
        input [58:0] raw_mag;
        reg [58:0] shifted;
        begin
            shifted=raw_mag>>MAG_SH;
            report_mag=(|shifted[58:32]) ? 32'hffffffff : shifted[31:0];
        end
    endfunction
    function [7:0] hz_of;
        input [4:0] k;
        begin hz_of=8'd20+{1'b0,k,2'b00}+{3'd0,k}; end
    endfunction
    function pos_near;
        input [5:0] a,b;
        reg [2:0] dr,dc;
        begin
            dr=(a[5:3]>=b[5:3]) ? a[5:3]-b[5:3] : b[5:3]-a[5:3];
            dc=(a[2:0]>=b[2:0]) ? a[2:0]-b[2:0] : b[2:0]-a[2:0];
            pos_near=(dr<=3'd1)&&(dc<=3'd1);
        end
    endfunction
    function bin_near;
        input [4:0] a,b;
        reg [4:0] delta;
        begin delta=(a>=b)?a-b:b-a; bin_near=(delta<=5'd1); end
    endfunction

    localparam [4:0] IDLE=0, RD=1, M1=2, M2=3, M3=4, M4=5,
                     ENERGY=6, WRITE=7, NEXT=8, PASS=9, SUM_RD=10,
                     SUM_WAIT=11, SUM_CHECK=12, PICK=13, COMMIT=14,
                     EMIT=15, FIN=16,
                     DIAG_INIT=17, DIAG_RD=18, DIAG_M1=19, DIAG_M2=20,
                     DIAG_M3=21, DIAG_M4=22, DIAG_ENERGY=23, DIAG_NEXT=24;
    reg [4:0] state;
    reg window_veto;
    reg [5:0] blk,scan_blk;
    reg [4:0] bin;
    reg [10:0] base;
    reg [31:0] scan_count;
    reg signed [15:0] coef;
    reg signed [63:0] cs1,cs12,sq1,energy;
    wire signed [31:0] s1=st_data[63:32], s2=st_data[31:0];
    // Same four-cycle multiplier schedule and one-cycle RAM prefetch as OLD.
    // Original scan and diagnostic rescan are mutually exclusive users of
    // this one multiplier and the original energy pipeline registers.
    wire mul_m1=(state==M1)||(state==DIAG_M1);
    wire mul_m2=(state==M2)||(state==DIAG_M2);
    wire mul_m3=(state==M3)||(state==DIAG_M3);
    wire signed [31:0] ma=mul_m1?s1:mul_m2?(cs1>>>14):mul_m3?s1:s2;
    wire signed [31:0] mb=mul_m1?{{16{coef[15]}},coef}:mul_m2?s2:mul_m3?s1:s2;
    wire signed [63:0] product=ma*mb;
    wire [58:0] mag=(energy<0)?59'd0:
        (energy>64'sd288230376151711743)?59'd288230376151711743:energy[58:0];
    wire [31:0] mag32=report_mag(mag);
    reg [58:0] block_peak;
    reg [4:0] block_bin;
    reg [39:0] block_sum;
    wire peak_hit=(bin>=BIN_MIN)&&((bin==BIN_MIN)||(mag>block_peak));
    wire [58:0] final_peak=peak_hit?mag:block_peak;
    wire [4:0] final_bin=peak_hit?bin:block_bin;
    wire [31:0] final_pk32=report_mag(final_peak);
    wire [39:0] final_sum=block_sum+{8'd0,mag32};
    wire [39:0] rest=(final_sum>{8'd0,final_pk32}) ? final_sum-{8'd0,final_pk32} :40'd0;
    wire [43:0] pk7=({12'd0,final_pk32}<<3)-{12'd0,final_pk32};
    wire [43:0] rest2={3'd0,rest,1'b0};
    wire ratio_ok;
    generate
        if(TONE_RATIO==0) begin:g_old_raw_criterion
            assign ratio_ok=(pk7>rest2);
        end else if((NBIN==17)&&(TONE_RATIO==6)) begin:g_ratio6
            wire [43:0] pk8={9'd0,final_pk32,3'd0};
            wire [43:0] rest3={4'd0,rest}+{3'd0,rest,1'b0};
            assign ratio_ok=(pk8>rest3);
        end else begin:g_other_ratio
            wire [63:0] lhs={32'd0,final_pk32}*(NBIN-BIN_MIN-1);
            wire [63:0] rhs={24'd0,rest}*TONE_RATIO;
            assign ratio_ok=(lhs>rhs);
        end
    endgenerate
    wire qualified=(final_pk32>TONE_MIN)&&ratio_ok;
    reg [47:0] qualified_map;
    reg [5:0] raw_count,qual_count;
    reg [58:0] global_peak;
    reg [5:0] global_blk,qual_best_blk;
    reg [4:0] global_bin;
    reg [31:0] qual_best_mag;
    reg [4:0] qual_best_bin;
    // The engine clears s1/s2 only after done. Re-reading one finalized block
    // avoids a full-bin energy register bank and any additional DSP/ERAM.
    reg [58:0] second_peak;
    reg [4:0] second_bin;
    // NBIN is an elaboration-time constant. Unrolled constant shifts/adds
    // support the reserved larger state space without a new DSP multiplier.
    function [10:0] block_base;
        input [5:0] b;
        integer k;
        reg [10:0] b_ext;
        begin
            b_ext={5'd0,b};
            block_base=11'd0;
            for(k=0;k<6;k=k+1)
                if((NBIN & (1<<k))!=0)
                    block_base=block_base+(b_ext<<k);
        end
    endfunction
    wire [10:0] diag_base=block_base(global_blk);
    reg [3:0] qual_selected_mask,qual_confirmed_mask,qual_near_mask,occupied_mask;
    reg global_qualified;
    reg [3:0] frequency_pending_mask;
    reg [31:0] diag0,diag4,diag6,diag8,diag10;
    reg [31:0] global0,global4,global6,global8,global10;
    reg [4:0] aexp[0:47];

    // Store only this window's per-block peak. No history is hidden in RAM.
    reg [63:0] result_in;
    reg [5:0] result_addr;
    wire [63:0] result_out;
    wire result_we=(state==WRITE)&&(bin==NBIN-1);
    vib_eram_dp #(.W_A(64),.AW_A(6),.D_A(64),.W_B(64),.AW_B(6),.D_B(64)) u_result(
        .clk(clk),.rst_n(rst_n),.dia(result_in),.addra(result_addr),
        .wea(result_we),.doa(result_out),.dib(64'd0),.addrb(6'd0),.web(1'b0),.dob());
    wire [58:0] candidate_raw=result_out[63:5];
    wire [31:0] candidate_mag=report_mag(candidate_raw);
    wire [4:0] candidate_bin=result_out[4:0];

    // Match the previous four slots first; then fill empty slots from ALL48
    // qualified blocks. Frequency-aware suppression happens during every pass,
    // before choosing the next slot; a duplicate cannot consume a Top4 place.
    reg [5:0] prev_blk[0:3],next_blk[0:3];
    reg [4:0] prev_bin[0:3],next_bin[0:3];
    reg [2:0] prev_streak[0:3],next_streak[0:3];
    reg prev_strong[0:3]; // strength of this slot's previous matched window
    reg next_matched[0:3]; // selected in the old-slot matching pass
    reg frequency_valid[0:3];
    reg [4:0] accepted_bin[0:3],pending_bin[0:3];
    reg pending_valid[0:3];
    reg [31:0] next_mag[0:3];
    reg match_phase;
    reg [1:0] slot;
    reg [31:0] pick_mag;
    reg [5:0] pick_blk;
    reg [4:0] pick_bin;
    reg pick_exact;
    wire exact_candidate=(scan_blk==prev_blk[slot]);
    wire matches_previous=(prev_streak[slot]!=0)&&
        pos_near(scan_blk,prev_blk[slot])&&bin_near(candidate_bin,prev_bin[slot]);
    // Suppress only the SAME frequency bin. Adjacent 3.0/3.5Hz blocks must
    // remain independent; temporal matching may still tolerate one-bin jitter.
    wire used0=(next_streak[0]!=0)&&pos_near(scan_blk,next_blk[0])&&(candidate_bin==next_bin[0]);
    wire used1=(next_streak[1]!=0)&&pos_near(scan_blk,next_blk[1])&&(candidate_bin==next_bin[1]);
    wire used2=(next_streak[2]!=0)&&pos_near(scan_blk,next_blk[2])&&(candidate_bin==next_bin[2]);
    wire used3=(next_streak[3]!=0)&&pos_near(scan_blk,next_blk[3])&&(candidate_bin==next_bin[3]);
    wire eligible=!window_veto&&qualified_map[scan_blk]&&!(used0||used1||used2||used3)&&
        (!match_phase||matches_previous);
    wire pick_better=(pick_blk==6'd63)||
        (match_phase&&exact_candidate&&!pick_exact)||
        ((!match_phase||(exact_candidate==pick_exact))&&(candidate_mag>pick_mag));
    reg [31:0] emit_pos,emit_hz;
    reg [127:0] emit_mag;
    reg [11:0] emit_streak;
    reg [2:0] confirmed_count;
    reg [5:0] first_blk;
    reg [7:0] first_hz;
    wire current_strong=(next_mag[slot]>=STRONG_MIN);
    wire slot_confirmed=(next_streak[slot]>=3'd3)||
        ((next_streak[slot]>=3'd2)&&prev_strong[slot]&&current_strong);
    // The track streak still belongs to the original position/bin matching.
    // Frequency evidence is independent once a slot has been published.
    wire matched_frequency=next_matched[slot]&&frequency_valid[slot];
    wire accepted_frequency=(next_bin[slot]==accepted_bin[slot]);
    wire repeated_frequency=pending_valid[slot]&&(next_bin[slot]==pending_bin[slot]);
    wire frequency_ready=!matched_frequency||accepted_frequency||repeated_frequency;
    wire publish_confirmed=slot_confirmed&&frequency_ready;
    wire [10:0] grid_x={8'd0,first_blk[2:0]}*11'd160;
    wire [10:0] grid_y={8'd0,first_blk[5:3]}*11'd120;
    integer j;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; busy<=0; done<=0; st_addr<=0;
            window_veto<=0;
            blk<=0; bin<=0; base<=0; scan_blk<=0; scan_count<=0; coef<=0;
            cs1<=0; cs12<=0; sq1<=0; energy<=0;
            block_peak<=0; block_bin<=0; block_sum<=0;
            qualified_map<=0; raw_count<=0; qual_count<=0;
            global_peak<=0; global_blk<=0; global_bin<=0; global_qualified<=0;
            qual_best_mag<=0; qual_best_blk<=63; qual_best_bin<=0;
            second_peak<=0; second_bin<=0;
            qual_selected_mask<=0; qual_confirmed_mask<=0; qual_near_mask<=0; occupied_mask<=0;
            o_dbg_qual_hz10<=0; o_dbg_qual_mag<=0; o_dbg_qual_status<=0;
            o_dbg_second_hz10<=0; o_dbg_second_mag<=0; frequency_pending_mask<=0;
            diag0<=0; diag4<=0; diag6<=0; diag8<=0; diag10<=0;
            global0<=0; global4<=0; global6<=0; global8<=0; global10<=0;
            result_in<=0; result_addr<=0;
            slot<=0; match_phase<=1; pick_mag<=0; pick_blk<=63; pick_bin<=0; pick_exact<=0;
            emit_pos<=0; emit_hz<=0; emit_mag<=0; emit_streak<=0;
            confirmed_count<=0; first_blk<=0; first_hz<=0;
            o_ntonal<=0; o_qact<=0; o_best_blk<=0; o_best_mag<=0; o_best_bin<=0;
            o_best_hz10<=0; o_mb_bin0<=0; o_mb_b12<=0;
            o_fb2<=0; o_fb4<=0; o_fb8<=0; o_fb12<=0;
            o_tn<=0; o_raw_hz<=0; o_trk_pos<=0;
            o_bb_x0<=0; o_bb_y0<=0; o_bb_x1<=0; o_bb_y1<=0; o_bb_vld<=0;
            o_obj_pos<=0; o_obj_hz10<=0; o_tonal_map<=0; o_obj_pn<=0; o_fx_pn<=0;
            o_scan_cnt<=0; o_win_cnt<=0; o_dbg_fx_sel<=0; o_dbg_chal_blk<=63;
            o_dbg_streak<=0; o_dbg_aexp<=0; o_confirmed<=0;
            for(j=0;j<4;j=j+1) begin
                prev_blk[j]<=63; prev_bin[j]<=0; prev_streak[j]<=0;
                prev_strong[j]<=0; next_matched[j]<=0;
                frequency_valid[j]<=0; accepted_bin[j]<=0;
                pending_bin[j]<=0; pending_valid[j]<=0;
                next_blk[j]<=63; next_bin[j]<=0; next_streak[j]<=0; next_mag[j]<=0;
            end
            for(j=0;j<48;j=j+1) aexp[j]<=0;
        end else begin
            done<=0;
            if(i_tick&&(i_row<6)) begin
                aexp[{i_row,3'd0}]<=i_axx_exp[4:0];
                aexp[{i_row,3'd1}]<=i_axx_exp[9:5];
                aexp[{i_row,3'd2}]<=i_axx_exp[14:10];
                aexp[{i_row,3'd3}]<=i_axx_exp[19:15];
                aexp[{i_row,3'd4}]<=i_axx_exp[24:20];
                aexp[{i_row,3'd5}]<=i_axx_exp[29:25];
                aexp[{i_row,3'd6}]<=i_axx_exp[34:30];
                aexp[{i_row,3'd7}]<=i_axx_exp[39:35];
            end
            case(state)
            IDLE: if(trig) begin
                window_veto<=COMMON_MOTION_ON ? i_motion_veto : 1'b0;
                busy<=1; blk<=0; bin<=0; base<=0; st_addr<=0; coef<=coef_of(0);
                scan_count<=0; qualified_map<=0; raw_count<=0; qual_count<=0;
                block_peak<=0; block_bin<=0; block_sum<=0;
                global_peak<=0; global_blk<=0; global_bin<=0; global_qualified<=0;
                qual_best_mag<=0; qual_best_blk<=63; qual_best_bin<=0;
                second_peak<=0; second_bin<=0;
                qual_selected_mask<=0; qual_confirmed_mask<=0; qual_near_mask<=0; occupied_mask<=0;
                global0<=0; global4<=0; global6<=0; global8<=0; global10<=0;
                frequency_pending_mask<=0;
                for(j=0;j<4;j=j+1) begin
                    next_blk[j]<=63; next_bin[j]<=0; next_streak[j]<=0; next_mag[j]<=0;
                    next_matched[j]<=0;
                end
                state<=RD;
            end
            RD: state<=M1; // st_addr stable for a complete synchronous read
            M1: begin cs1<=product; state<=M2; end
            M2: begin cs12<=product; state<=M3; end
            M3: begin sq1<=product; state<=M4; end
            M4: begin energy<=sq1-cs12+product; state<=ENERGY; end
            ENERGY: begin
                if(bin==0) diag0<=mag32;
                if(bin==4) diag4<=mag32;
                if(bin==8) diag6<=mag32;
                if(bin==12) diag8<=mag32;
                if(bin==16) diag10<=mag32;
                if(peak_hit) begin block_peak<=mag; block_bin<=bin; end
                if(bin>=BIN_MIN) block_sum<=(bin==BIN_MIN)?{8'd0,mag32}:final_sum;
                if(bin==NBIN-1) begin
                    result_addr<=blk; result_in<={final_peak,final_bin};
                    if(final_pk32>TONE_MIN) raw_count<=raw_count+6'd1;
                    qualified_map[blk]<=qualified;
                    if(qualified) begin
                        qual_count<=qual_count+6'd1;
                        if(final_pk32>qual_best_mag) begin
                            qual_best_mag<=final_pk32; qual_best_blk<=blk; qual_best_bin<=final_bin;
                        end
                    end
                    if((blk==0)||(final_peak>global_peak)) begin
                        global_peak<=final_peak; global_blk<=blk; global_bin<=final_bin;
                        global_qualified<=qualified;
                        global0<=diag0; global4<=diag4; global6<=diag6;
                        global8<=diag8; global10<=(bin==16)?mag32:diag10;
                    end
                end
                scan_count<=scan_count+32'd1;
                state<=WRITE;
            end
            WRITE: state<=NEXT;
            NEXT: begin
                if(bin<NBIN-1) begin
                    bin<=bin+5'd1; coef<=coef_of(bin+5'd1);
                    st_addr<=base+{6'd0,bin}+11'd1; state<=RD;
                end else if(blk<NB-1) begin
                    blk<=blk+6'd1; bin<=0; base<=base+NBIN; st_addr<=base+NBIN;
                    coef<=coef_of(0); block_peak<=0; block_bin<=0; block_sum<=0; state<=RD;
                end else state<=DIAG_INIT;
            end
            // Read-only rescan of PBLK. These states do not write results,
            // scan_count, qualified_map, global_peak or any target history.
            // abs(bin-global_bin)>1 excludes the main peak and its immediate
            // +/-0.5Hz neighbours. Strict greater-than preserves lower-bin ties.
            DIAG_INIT: begin
                bin<=0; st_addr<=diag_base; coef<=coef_of(0);
                second_peak<=0; second_bin<=0; state<=DIAG_RD;
            end
            DIAG_RD: state<=DIAG_M1;
            DIAG_M1: begin cs1<=product; state<=DIAG_M2; end
            DIAG_M2: begin cs12<=product; state<=DIAG_M3; end
            DIAG_M3: begin sq1<=product; state<=DIAG_M4; end
            DIAG_M4: begin energy<=sq1-cs12+product; state<=DIAG_ENERGY; end
            DIAG_ENERGY: begin
                if((bin>=BIN_MIN)&&!bin_near(bin,global_bin)&&(mag>second_peak)) begin
                    second_peak<=mag; second_bin<=bin;
                end
                state<=DIAG_NEXT;
            end
            DIAG_NEXT: begin
                if(bin<NBIN-1) begin
                    bin<=bin+5'd1; coef<=coef_of(bin+5'd1);
                    st_addr<=diag_base+{6'd0,bin}+11'd1; state<=DIAG_RD;
                end else begin slot<=0; match_phase<=1; state<=PASS; end
            end
            PASS: begin
                pick_mag<=0; pick_blk<=63; pick_bin<=0; pick_exact<=0;
                scan_blk<=0; result_addr<=0;
                if((match_phase&&(prev_streak[slot]==0))||
                   (!match_phase&&(next_streak[slot]!=0))) state<=PICK;
                else state<=SUM_RD;
            end
            SUM_RD: begin result_addr<=scan_blk; state<=SUM_WAIT; end
            SUM_WAIT: state<=SUM_CHECK;
            SUM_CHECK: begin
                if(eligible&&pick_better) begin
                    pick_mag<=candidate_mag; pick_blk<=scan_blk; pick_bin<=candidate_bin;
                    pick_exact<=exact_candidate;
                end
                if(scan_blk<NB-1) begin scan_blk<=scan_blk+6'd1; state<=SUM_RD; end
                else state<=PICK; // include block47 before committing the selection
            end
            PICK: begin
                if(pick_blk!=63) begin
                    next_blk[slot]<=pick_blk; next_bin[slot]<=pick_bin; next_mag[slot]<=pick_mag;
                    next_matched[slot]<=match_phase;
                    next_streak[slot]<=match_phase ?
                        ((prev_streak[slot]==7)?3'd7:prev_streak[slot]+3'd1) :3'd1;
                end
                if(slot!=3) begin slot<=slot+2'd1; state<=PASS; end
                else if(match_phase) begin slot<=0; match_phase<=0; state<=PASS; end
                else begin slot<=0; emit_pos<=0; emit_hz<=0; emit_mag<=0; emit_streak<=0;
                    confirmed_count<=0; first_blk<=0; first_hz<=0; state<=COMMIT; end
            end
            COMMIT: begin
                // Observe exact selection versus same-frequency neighbour
                // representation, including pending tracks. Never change picks.
                if(next_streak[slot]!=0) begin
                    occupied_mask[slot]<=1'b1;
                    if((qual_best_blk!=63)&&(next_bin[slot]==qual_best_bin)) begin
                        if(pos_near(next_blk[slot],qual_best_blk)) qual_near_mask[slot]<=1'b1;
                        if(next_blk[slot]==qual_best_blk) begin
                            qual_selected_mask[slot]<=1'b1;
                            if(publish_confirmed) qual_confirmed_mask[slot]<=1'b1;
                        end
                    end
                end
                // Frequency anchor/evidence belongs only to this continuously
                // matched identity. Empty/vetoed tracks and new fills cannot
                // inherit a prior occupant's accepted frequency or pending bin.
                if(next_streak[slot]==0) begin
                    frequency_valid[slot]<=0; pending_valid[slot]<=0;
                    accepted_bin[slot]<=0; pending_bin[slot]<=0;
                end else if(!matched_frequency) begin
                    frequency_valid[slot]<=slot_confirmed;
                    accepted_bin[slot]<=next_bin[slot];
                    pending_valid[slot]<=0; pending_bin[slot]<=0;
                end else if(accepted_frequency) begin
                    pending_valid[slot]<=0; pending_bin[slot]<=0;
                end else if(repeated_frequency) begin
                    accepted_bin[slot]<=next_bin[slot];
                    pending_valid[slot]<=0; pending_bin[slot]<=0;
                end else begin
                    pending_valid[slot]<=1; pending_bin[slot]<=next_bin[slot];
                    frequency_pending_mask[slot]<=1'b1;
                end
                // Four slots emit independently; no energy-rank master gate.
                prev_blk[slot]<=next_blk[slot]; prev_bin[slot]<=next_bin[slot];
                prev_streak[slot]<=next_streak[slot];
                prev_strong[slot]<=(next_streak[slot]!=0)&&current_strong;
                emit_streak[slot*3+:3]<=next_streak[slot];
                if(publish_confirmed) begin
                    emit_pos[slot*8+:8]<={1'b0,1'b1,next_blk[slot]};
                    emit_hz[slot*8+:8]<=hz_of(next_bin[slot]);
                    emit_mag[slot*32+:32]<=next_mag[slot];
                    confirmed_count<=confirmed_count+3'd1;
                    if(confirmed_count==0) begin first_blk<=next_blk[slot]; first_hz<=hz_of(next_bin[slot]); end
                end
                if(slot!=3) slot<=slot+2'd1; else state<=EMIT;
            end
            EMIT: state<=FIN;
            FIN: begin
                busy<=0; done<=1; o_win_cnt<=o_win_cnt+8'd1; o_scan_cnt<=scan_count;
                o_ntonal<=raw_count; o_qact<=qual_count; o_tonal_map<=qualified_map;
                o_best_blk<=global_blk; o_dbg_fx_sel<=global_blk; o_best_bin<=global_bin;
                o_best_mag<=report_mag(global_peak); o_fx_pn<=report_mag(global_peak);
                o_raw_hz<=(global_peak!=0)?{24'd0,hz_of(global_bin)}:32'd0;
                o_best_hz10<=first_hz; o_dbg_aexp<=aexp[global_blk];
                o_mb_bin0<=global0; o_mb_b12<=global8;
                o_fb2<=global4; o_fb4<=global6; o_fb8<=global10; o_fb12<=global8;
                o_tn<={30'd0,(confirmed_count!=0),global_qualified};
                o_dbg_chal_blk<=qual_best_blk; o_dbg_streak<=emit_streak;
                o_dbg_qual_hz10<=(qual_best_blk!=63)?hz_of(qual_best_bin):8'd0;
                o_dbg_qual_mag<=qual_best_mag;
                // [0]qualified exists; [1]PBLK qualified; [7:4]selected;
                // [11:8]confirmed; [15:12]near same-bin representative;
                // [19:16]occupied; [20]window veto; [24:21]frequency pending.
                // Each four-bit mask uses slot1 as its lowest bit.
                o_dbg_qual_status<={7'd0,frequency_pending_mask,window_veto,occupied_mask,qual_near_mask,
                                   qual_confirmed_mask,qual_selected_mask,2'd0,
                                   global_qualified,(qual_best_blk!=63)};
                o_dbg_second_hz10<=(second_peak!=0)?hz_of(second_bin):8'd0;
                o_dbg_second_mag<=report_mag(second_peak);
                o_confirmed<=confirmed_count; o_obj_pos<=emit_pos; o_obj_hz10<=emit_hz; o_obj_pn<=emit_mag;
                o_trk_pos<=(confirmed_count!=0)?{25'd0,1'b1,first_blk}:32'd0;
                o_bb_x0<=grid_x; o_bb_x1<=grid_x+11'd159;
                o_bb_y0<=grid_y; o_bb_y1<=grid_y+11'd119; o_bb_vld<=(confirmed_count!=0);
                state<=IDLE;
            end
            default: state<=IDLE;
            endcase
        end
    end
endmodule
`endif
