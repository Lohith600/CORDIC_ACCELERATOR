// WIDTH: data width for x/y/z. N: iteration count (valid range 1-14, capped
// by the atan ROM's precomputed depth). CONST_VALUE/HALF_PI/PI and the
// K-scale shift-add decomposition below are pinned to the default WIDTH=16
// Q3.13 (angle) / Q2.14 (x/y) format -- regenerate them (e.g. via the
// Python golden model) if WIDTH changes.
module cordic_top #(parameter WIDTH=16, parameter N=14) (input clk,input signed [WIDTH-1:0] xin,input signed [WIDTH-1:0] yin,input signed [WIDTH-1:0] zin,input modein,
                    input reset,output reg signed [WIDTH-1:0] x,output reg signed [WIDTH-1:0] y,output reg signed [WIDTH-1:0] z,output reg done);

localparam signed [15:0] CONST_VALUE = 16'sh26DD; // constant factor(K) that should be multiplied at the end
localparam signed [15:0] HALF_PI     = 16'sd12868; // pi/2 in Q3.13
localparam signed [15:0] PI          = 16'sd25736; // pi   in Q3.13


reg signed [WIDTH-1:0] xin_r, yin_r, zin_r;
reg modein_r;

always @(posedge clk) begin
    if (reset) begin
        xin_r <= xin;
        yin_r <= yin;
        zin_r <= zin;
        modein_r <= modein;
    end
end


reg reset_d;
always @(posedge clk) reset_d <= reset;

wire signed [WIDTH-1:0] x_temp,y_temp,z_temp;

wire signed [WIDTH-1:0] x_1,y_1,z_1;
reg  signed [WIDTH-1:0] x_2,y_2,z_2;

wire flip;
reg finish;

range_reduce #(.WIDTH(WIDTH)) rr(.modein(modein_r),.xin(xin_r),.yin(yin_r),.zin(zin_r),.flip(flip),.xout(x_1),.yout(y_1),.zout(z_1));


reg [3:0] counter;
wire signed [WIDTH-1:0] mem_i;

atan_mem #(.WIDTH(WIDTH)) rom(.i(counter),.value(mem_i));

always @(posedge clk) begin
    if (reset_d)
        counter <= 4'h0;
    else if (!finish)
        counter <= counter + 1;
end

always @(*) begin
    finish = (counter == N-1);
end

cordic_iterative #(.WIDTH(WIDTH)) ci(.clk(clk),.rst(reset_d),.xin(x_1),.yin(y_1),.zin(z_1),.modein(modein_r),
.counter(counter),.mem_i(mem_i),.finish(finish),
.x_out(x_temp),.y_out(y_temp),.z_out(z_temp));

/* multiply by the constant factor via shift-add (CONST_VALUE=9949 is a fixed
 compile-time constant, so this needs no multiplier hardware): 9949 = 2^13 + 2^11 - 2^9 + 2^8 - 2^6 + 2^5 - 2^2 + 2^0
 shift amounts (13,11,9,...) and the final >>>14 below are pinned to the
 default WIDTH=16 Q2.14 x/y format -- only valid as-is at WIDTH=16.*/

wire signed [2*WIDTH-1:0] x_shift_a, x_shift_b, y_shift_a, y_shift_b;
assign x_shift_a = (x_temp <<< 13) + (x_temp <<< 11) - (x_temp <<< 9) + (x_temp <<< 8);
assign x_shift_b = -(x_temp <<< 6) + (x_temp <<< 5) - (x_temp <<< 2) + x_temp;
assign y_shift_a = (y_temp <<< 13) + (y_temp <<< 11) - (y_temp <<< 9) + (y_temp <<< 8);
assign y_shift_b = -(y_temp <<< 6) + (y_temp <<< 5) - (y_temp <<< 2) + y_temp;

reg signed [2*WIDTH-1:0] x_shift_a_r, x_shift_b_r, y_shift_a_r, y_shift_b_r;
reg signed [WIDTH-1:0] z_2_pre;
reg finish_d, x2_valid;


//being done in two cycles becuase of complexity of the operation affecting the fmax.
always@(posedge clk)begin
    finish_d <= finish;
    if(finish)begin
        x_shift_a_r <= x_shift_a;
        x_shift_b_r <= x_shift_b;
        y_shift_a_r <= y_shift_a;
        y_shift_b_r <= y_shift_b;
        z_2_pre     <= z_temp;
    end
end

always@(posedge clk)begin
    x2_valid <= finish_d;
    if(finish_d)begin
        x_2 <= (x_shift_a_r + x_shift_b_r) >>> 14;
        y_2 <= (y_shift_a_r + y_shift_b_r) >>> 14;
        z_2 <= z_2_pre;
    end
end


always@(posedge clk)begin
    done <= x2_valid;
end


//final mode-correction stage, now registered (was combinational) so the
//output is clocked, matching the pipelined version's registered final stage.

always@(posedge clk)begin

    if(modein_r && flip)begin
       if(z_2 < 0)begin
        z <= z_2 + PI;
       end
       else begin
        z <= z_2 - PI;
       end
        x <= x_2;
        y <= y_2;
    end

    else if((!modein_r) && flip)begin
        x <= -x_2;
        y <= -y_2;
        z <= z_2;
    end

    else begin
        x <= x_2;
        y <= y_2;
        z <= z_2;
    end

end

endmodule
