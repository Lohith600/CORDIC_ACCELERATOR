// ATAN0..13 are pinned to the default WIDTH=16, Q3.13 angle format --
// should regenerate these (e.g. via the Python golden model) if WIDTH changes.
// Table depth is fixed at 14 entries, so N (iteration count) must stay <=14
// with this table; i beyond 13 returns 0 .
module atan_mem #(parameter WIDTH=16) (input [3:0] i,output reg signed [WIDTH-1:0] value);

localparam signed [15:0] ATAN0  = 16'sh1922;
localparam signed [15:0] ATAN1  = 16'sh0ed6;
localparam signed [15:0] ATAN2  = 16'sh07d7;
localparam signed [15:0] ATAN3  = 16'sh03fb;
localparam signed [15:0] ATAN4  = 16'sh01ff;
localparam signed [15:0] ATAN5  = 16'sh0100;
localparam signed [15:0] ATAN6  = 16'sh0080;
localparam signed [15:0] ATAN7  = 16'sh0040;
localparam signed [15:0] ATAN8  = 16'sh0020;
localparam signed [15:0] ATAN9  = 16'sh0010;
localparam signed [15:0] ATAN10 = 16'sh0008;
localparam signed [15:0] ATAN11 = 16'sh0004;
localparam signed [15:0] ATAN12 = 16'sh0002;
localparam signed [15:0] ATAN13 = 16'sh0001;

always @(*) begin
    case (i)
        4'd0:  value = ATAN0;
        4'd1:  value = ATAN1;
        4'd2:  value = ATAN2;
        4'd3:  value = ATAN3;
        4'd4:  value = ATAN4;
        4'd5:  value = ATAN5;
        4'd6:  value = ATAN6;
        4'd7:  value = ATAN7;
        4'd8:  value = ATAN8;
        4'd9:  value = ATAN9;
        4'd10: value = ATAN10;
        4'd11: value = ATAN11;
        4'd12: value = ATAN12;
        4'd13: value = ATAN13;
        default: value = 16'sd0;
    endcase
end

endmodule
