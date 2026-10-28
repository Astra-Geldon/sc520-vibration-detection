// Four spatial reference blocks: rows1/4, columns1/6, before spectral ranking.
// Included by the top; do not register this file a second time in the project.
// i_pair[159:0] is left, [319:160] right. Each is {by,bx,axy,ayy,axx}.
// Raw bx is NOT velocity. Solve -A^-1*b independently at each reference.
// All five signed inputs share arithmetic scaling until they fit16 bits.
// Six products share one16-cycle shift/add unit; no '*' or '/' datapath.
// Q8 velocities omit the common factor2 from the undivided image gradient.
// Thus magnitude16 means1/16 model unit (1/8 original pixel/frame).
// Invalid/weak/ill-conditioned references and broken input order fail open.
`ifndef VIB_COMMON_MOTION_V
`define VIB_COMMON_MOTION_V
module vib_common_motion (
    input wire clk, rst_n,
    input wire i_tick,
    input wire [2:0] i_row,
    input wire [319:0] i_pair,
    output reg o_ready,
    output reg o_valid,
    output reg o_motion,
    output wire o_busy
);
    localparam [3:0] IDLE=0, NORMALIZE=1, MUL_LOAD=2, MUL_RUN=3,
                     QUALITY=4, WAIT_U=5, WAIT_V=6, SAVE=7,
                     AVERAGE=8, COMPARE=9;
    reg [3:0] state;
    assign o_busy=(state!=IDLE);
    reg [2:0] expected_row;
    reg frame_ok, top_done;
    reg [1:0] point;
    reg [159:0] right_snapshot;
    reg signed [31:0] axx,ayy,axy,bx,by;
    reg source_ok, point_ok;
    reg [3:0] point_valid;
    reg signed [12:0] vx[0:3],vy[0:3];
    reg signed [12:0] work_u,work_v;

    function fits16;
        input signed [31:0] value;
        begin fits16=(value>=-32'sd32768)&&(value<=32'sd32767); end
    endfunction
    function close_component;
        input signed [12:0] component;
        input signed [15:0] reference;
        input [15:0] limit;
        reg signed [16:0] delta;
        reg [16:0] distance;
        begin
            delta={{4{component[12]}},component}-{reference[15],reference};
            distance=delta[16] ? (~delta+17'd1) : delta;
            close_component=(distance<={1'b0,limit});
        end
    endfunction
    function same_main_sign;
        input signed [12:0] sign_component;
        input signed [15:0] sign_reference;
        begin
            // Every point needs at least16 in the common dominant component.
            same_main_sign=((sign_reference>=16'sd16)&&(sign_component>=13'sd16))||
                           ((sign_reference<=-16'sd16)&&(sign_component<=-13'sd16));
        end
    endfunction
    wire scaled_ok=fits16(axx)&&fits16(ayy)&&fits16(axy)&&fits16(bx)&&fits16(by);

    reg [2:0] product_step;
    reg signed [15:0] operand_a,operand_b;
    always @(*) begin
        case(product_step)
        0: begin operand_a=axx[15:0]; operand_b=ayy[15:0]; end
        1: begin operand_a=axy[15:0]; operand_b=axy[15:0]; end
        2: begin operand_a=axy[15:0]; operand_b=by[15:0]; end
        3: begin operand_a=bx[15:0];  operand_b=ayy[15:0]; end
        4: begin operand_a=axy[15:0]; operand_b=bx[15:0]; end
        default: begin operand_a=axx[15:0]; operand_b=by[15:0]; end
        endcase
    end
    wire [15:0] abs_a=operand_a[15] ? (~operand_a+16'd1) : operand_a;
    wire [15:0] abs_b=operand_b[15] ? (~operand_b+16'd1) : operand_b;
    reg [31:0] mul_acc,mul_shift;
    reg [15:0] mul_bits;
    reg mul_negative;
    reg [3:0] mul_count;
    wire [31:0] mul_added=mul_acc+(mul_bits[0]?mul_shift:32'd0);
    wire signed [31:0] signed_product=mul_negative ? -$signed(mul_added) : $signed(mul_added);
    wire signed [32:0] product_extended={signed_product[31],signed_product};
    reg [31:0] axx_ayy;
    reg signed [32:0] determinant,num_u,num_v;
    wire [32:0] abs_num_u=num_u[32] ? (~num_u+33'd1) : num_u;
    wire [32:0] abs_num_v=num_v[32] ? (~num_v+33'd1) : num_v;

    reg div_start;
    reg [40:0] div_num;
    reg [31:0] div_den;
    wire [40:0] div_quot;
    wire div_done;
    vib_div_serial #(.W(41),.DW(32)) u_div (
        .clk(clk),.rst_n(rst_n),.start(div_start),.numer(div_num),.denom(div_den),
        .quot(div_quot),.rem(),.done(div_done)
    );

    reg signed [15:0] average_x,average_y;
    // Name memory words before selecting their sign bits (Verilog-2001).
    wire signed [12:0] vx0=vx[0],vx1=vx[1],vx2=vx[2],vx3=vx[3];
    wire signed [12:0] vy0=vy[0],vy1=vy[1],vy2=vy[2],vy3=vy[3];
    wire signed [15:0] sum_x={{3{vx0[12]}},vx0}+{{3{vx1[12]}},vx1}+
                              {{3{vx2[12]}},vx2}+{{3{vx3[12]}},vx3};
    wire signed [15:0] sum_y={{3{vy0[12]}},vy0}+{{3{vy1[12]}},vy1}+
                              {{3{vy2[12]}},vy2}+{{3{vy3[12]}},vy3};
    wire [15:0] abs_average_x=average_x[15] ? (~average_x+16'd1) : average_x;
    wire [15:0] abs_average_y=average_y[15] ? (~average_y+16'd1) : average_y;
    wire main_x=(abs_average_x>=abs_average_y);
    wire [15:0] main_magnitude=main_x?abs_average_x:abs_average_y;
    wire [15:0] tolerance=(main_magnitude>>1)+16'd8;

    reg agree;
    integer k;
    always @(*) begin
        agree=1'b1;
        for(k=0;k<4;k=k+1) begin
            if(!close_component(vx[k],average_x,tolerance)||
               !close_component(vy[k],average_y,tolerance)||
               !(main_x?same_main_sign(vx[k],average_x):same_main_sign(vy[k],average_y)))
                agree=1'b0;
        end
    end

    integer j;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; expected_row<=0; frame_ok<=0; top_done<=0;
            o_ready<=0; o_valid<=0; o_motion<=0;
            point<=0; right_snapshot<=0;
            axx<=0;ayy<=0;axy<=0;bx<=0;by<=0;source_ok<=0;point_ok<=0;
            point_valid<=0;work_u<=0;work_v<=0;
            product_step<=0;mul_acc<=0;mul_shift<=0;mul_bits<=0;mul_negative<=0;mul_count<=0;
            axx_ayy<=0;determinant<=0;num_u<=0;num_v<=0;
            div_start<=0;div_num<=0;div_den<=0;average_x<=0;average_y<=0;
            for(j=0;j<4;j=j+1) begin vx[j]<=0;vy[j]<=0;end
        end else begin
            div_start<=0;
            if(i_tick&&(i_row==0)) begin
                // A new row0 never inherits any validity/decision. If an old
                // pair is still busy, fail open for this entire incoming frame.
                frame_ok<=!o_busy; expected_row<=3'd1; state<=IDLE;
                top_done<=0;point_valid<=0;o_ready<=0;o_valid<=0;o_motion<=0;
            end else if(i_tick&&((i_row!=expected_row)||(i_row>5)||o_busy)) begin
                // Missing, repeated, early or overlapping rows invalidate the
                // frame; only another row0 may restore normal operation.
                frame_ok<=0;expected_row<=0;state<=IDLE;top_done<=0;point_valid<=0;
                o_ready<=1;o_valid<=0;o_motion<=0;
            end else begin
                if(i_tick) begin
                    expected_row<=(i_row==5)?3'd0:(i_row+3'd1);
                    if(frame_ok&&((i_row==1)||(i_row==4))) begin
                        if((i_row==4)&&!top_done) begin
                            frame_ok<=0;o_ready<=1;o_valid<=0;o_motion<=0;
                        end else begin
                            axx<=$signed(i_pair[31:0]);ayy<=$signed(i_pair[63:32]);
                            axy<=$signed(i_pair[95:64]);bx<=$signed(i_pair[127:96]);
                            by<=$signed(i_pair[159:128]);right_snapshot<=i_pair[319:160];
                            source_ok<=($signed(i_pair[31:0])>=32'sd4096)&&
                                       ($signed(i_pair[63:32])>=32'sd4096);
                            point<=(i_row==1)?2'd0:2'd2;state<=NORMALIZE;
                        end
                    end else if(!frame_ok&&(i_row==4)) begin
                        o_ready<=1;o_valid<=0;o_motion<=0;
                    end
                end
                case(state)
                IDLE: begin end
                NORMALIZE: begin
                    point_ok<=source_ok;work_u<=0;work_v<=0;
                    if(!source_ok) state<=SAVE;
                    else if(!scaled_ok) begin
                        axx<=axx>>>1;ayy<=ayy>>>1;axy<=axy>>>1;bx<=bx>>>1;by<=by>>>1;
                    end else if((axx<=0)||(ayy<=0)) begin point_ok<=0;state<=SAVE;end
                    else begin product_step<=0;state<=MUL_LOAD;end
                end
                MUL_LOAD: begin
                    mul_acc<=0;mul_shift<={16'd0,abs_a};mul_bits<=abs_b;
                    mul_negative<=operand_a[15]^operand_b[15];mul_count<=0;state<=MUL_RUN;
                end
                MUL_RUN: begin
                    mul_acc<=mul_added;mul_shift<=mul_shift<<1;mul_bits<=mul_bits>>1;
                    if(mul_count==15) begin
                        case(product_step)
                        0: axx_ayy<=signed_product;
                        1: determinant<=$signed({1'b0,axx_ayy})-product_extended;
                        2: num_u<=product_extended;
                        3: num_u<=num_u-product_extended;
                        4: num_v<=product_extended;
                        5: num_v<=num_v-product_extended;
                        default: begin end
                        endcase
                        if(product_step==5) state<=QUALITY;
                        else begin product_step<=product_step+3'd1;state<=MUL_LOAD;end
                    end else mul_count<=mul_count+4'd1;
                end
                QUALITY: begin
                    // Strict determinant > Axx*Ayy/16; equal is invalid.
                    if((determinant<=0)||(determinant<=$signed({1'b0,axx_ayy}>>4))) begin
                        point_ok<=0;state<=SAVE;
                    end else begin
                        div_den<=determinant[31:0];div_num<={abs_num_u,8'd0};
                        div_start<=1;state<=WAIT_U;
                    end
                end
                WAIT_U: if(div_done) begin
                    // Inclusive +/-2048 is valid; larger quotients fail open.
                    if(div_quot>41'd2048) point_ok<=0;
                    work_u<=num_u[32] ? -$signed(div_quot[12:0]) : $signed(div_quot[12:0]);
                    div_num<={abs_num_v,8'd0};div_start<=1;state<=WAIT_V;
                end
                WAIT_V: if(div_done) begin
                    if(div_quot>41'd2048) point_ok<=0;
                    work_v<=num_v[32] ? -$signed(div_quot[12:0]) : $signed(div_quot[12:0]);
                    state<=SAVE;
                end
                SAVE: begin
                    point_valid[point]<=point_ok;
                    vx[point]<=point_ok?work_u:13'sd0;vy[point]<=point_ok?work_v:13'sd0;
                    if(!point[0]) begin
                        point<=point+2'd1;
                        axx<=$signed(right_snapshot[31:0]);ayy<=$signed(right_snapshot[63:32]);
                        axy<=$signed(right_snapshot[95:64]);bx<=$signed(right_snapshot[127:96]);
                        by<=$signed(right_snapshot[159:128]);
                        source_ok<=($signed(right_snapshot[31:0])>=32'sd4096)&&
                                   ($signed(right_snapshot[63:32])>=32'sd4096);
                        state<=NORMALIZE;
                    end else if(point==1) begin top_done<=1;state<=IDLE;end
                    else state<=AVERAGE;
                end
                AVERAGE: begin
                    average_x<=sum_x>>>2;average_y<=sum_y>>>2;state<=COMPARE;
                end
                COMPARE: begin
                    o_ready<=1;o_valid<=frame_ok&&top_done&&(&point_valid);
                    o_motion<=frame_ok&&top_done&&(&point_valid)&&agree;
                    state<=IDLE;
                end
                default: begin state<=IDLE;frame_ok<=0;o_ready<=1;o_valid<=0;o_motion<=0;end
                endcase
            end
        end
    end
endmodule
`endif
