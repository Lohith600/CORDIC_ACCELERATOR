// WIDTH: data width for x/y/z. N: iteration count / pipeline depth (valid
// range 1-14, capped by atan_val's precomputed table depth). CONST_VALUE/
// HALF_PI/PI, atan_val's table, and the K-scale shift-add decomposition
// below are pinned to the default WIDTH=16 Q3.13 (angle) / Q2.14 (x/y)
// format -- regenerate them (e.g. via the Python golden model) if WIDTH
// changes.
module cordic_top #(parameter WIDTH=16, parameter N=14) (
    input clk,
    input signed [WIDTH-1:0] xin, yin, zin,
    input modein,
    input reset,
    output reg signed [WIDTH-1:0] x, y, z
);

localparam signed [15:0] CONST_VALUE = 16'sh26DD;  // K = 1/gain, Q2.14
localparam signed [15:0] HALF_PI     = 16'sd12868; // pi/2 in Q3.13
localparam signed [15:0] PI          = 16'sd25736; // pi   in Q3.13

function signed [WIDTH-1:0] atan_val;
    input [3:0] idx;
    begin
        case (idx)
            4'd0:  atan_val = 16'sh1922;
            4'd1:  atan_val = 16'sh0ed6;
            4'd2:  atan_val = 16'sh07d7;
            4'd3:  atan_val = 16'sh03fb;
            4'd4:  atan_val = 16'sh01ff;
            4'd5:  atan_val = 16'sh0100;
            4'd6:  atan_val = 16'sh0080;
            4'd7:  atan_val = 16'sh0040;
            4'd8:  atan_val = 16'sh0020;
            4'd9:  atan_val = 16'sh0010;
            4'd10: atan_val = 16'sh0008;
            4'd11: atan_val = 16'sh0004;
            4'd12: atan_val = 16'sh0002;
            4'd13: atan_val = 16'sh0001;
            default: atan_val = 16'sd0;
        endcase
    end
endfunction

//  captures raw xin/yin/zin/modein at the clock edge when reset is high, for range reduce to work with stable value nstead of a wire that could change mid-cycle.
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

wire flip;
wire signed [WIDTH-1:0] x_1, y_1, z_1;

range_reduce #(.WIDTH(WIDTH)) rr(.modein(modein_r), .xin(xin_r), .yin(yin_r), .zin(zin_r),
                 .flip(flip), .xout(x_1), .yout(y_1), .zout(z_1));


reg flip_pipe[0:N-1];
integer k;
always @(posedge clk) begin
    flip_pipe[0] <= flip;
    for (k = 1; k < N; k = k + 1)
        flip_pipe[k] <= flip_pipe[k-1];
end

//N pipeline stages
wire signed [WIDTH-1:0] sx[0:N], sy[0:N], sz[0:N];
wire smode[0:N];

assign sx[0] = x_1;
assign sy[0] = y_1;
assign sz[0] = z_1;
assign smode[0] = modein_r;

genvar gi;
generate
    for (gi = 0; gi < N; gi = gi + 1) begin : stage
        cordic_iterative #(.WIDTH(WIDTH)) ci(
            .clk(clk),
            .xin(sx[gi]), .yin(sy[gi]), .zin(sz[gi]), .modein(smode[gi]),
            .mem_i(atan_val(gi[3:0])), .i(gi[3:0]),
            .x_out(sx[gi+1]), .y_out(sy[gi+1]), .z_out(sz[gi+1]), .mode(smode[gi+1])
        );
    end
endgenerate

//same as iterative design split to two stages
// shift amounts (13,11,9,...) and the final >>>14 below are pinned to the
// default WIDTH=16 Q2.14 x/y format -- only valid as-is at WIDTH=16.

wire signed [2*WIDTH-1:0] x_scaled_a = (sx[N] <<< 13) + (sx[N] <<< 11) - (sx[N] <<< 9) + (sx[N] <<< 8);
wire signed [2*WIDTH-1:0] x_scaled_b = -(sx[N] <<< 6) + (sx[N] <<< 5) - (sx[N] <<< 2) + sx[N];
wire signed [2*WIDTH-1:0] y_scaled_a = (sy[N] <<< 13) + (sy[N] <<< 11) - (sy[N] <<< 9) + (sy[N] <<< 8);
wire signed [2*WIDTH-1:0] y_scaled_b = -(sy[N] <<< 6) + (sy[N] <<< 5) - (sy[N] <<< 2) + sy[N];

reg signed [2*WIDTH-1:0] x_scaled_a_r, x_scaled_b_r, y_scaled_a_r, y_scaled_b_r;
reg signed [WIDTH-1:0] z_n_r;
reg flip_stageN, mode_stageN;

always @(posedge clk) begin
    x_scaled_a_r <= x_scaled_a;
    x_scaled_b_r <= x_scaled_b;
    y_scaled_a_r <= y_scaled_a;
    y_scaled_b_r <= y_scaled_b;
    z_n_r        <= sz[N];
    flip_stageN  <= flip_pipe[N-1];
    mode_stageN  <= smode[N];
end

wire signed [WIDTH-1:0] x_k_c = (x_scaled_a_r + x_scaled_b_r) >>> 14;
wire signed [WIDTH-1:0] y_k_c = (y_scaled_a_r + y_scaled_b_r) >>> 14;

always @(posedge clk) begin
    if (mode_stageN && flip_stageN) begin
        x <= x_k_c;
        y <= y_k_c;
        z <= (z_n_r < 0) ? (z_n_r + PI) : (z_n_r - PI);
    end else if (!mode_stageN && flip_stageN) begin
        x <= -x_k_c;
        y <= -y_k_c;
        z <= z_n_r;
    end else begin
        x <= x_k_c;
        y <= y_k_c;
        z <= z_n_r;
    end
end

endmodule
