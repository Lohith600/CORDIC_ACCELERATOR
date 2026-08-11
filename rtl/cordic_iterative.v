module cordic_iterative #(parameter WIDTH=16) (
    input rst, clk,
    input signed [WIDTH-1:0] xin, yin, zin,
    input modein,
    input [3:0] counter,
    input signed [WIDTH-1:0] mem_i,
    input finish,
    output reg signed [WIDTH-1:0] x_out, y_out, z_out
);



reg signed [WIDTH-1:0] x, y, z;
wire signed [WIDTH-1:0] x_next, y_next, z_next;
reg mode;

cordic_stage #(.WIDTH(WIDTH)) cs(.x(x), .y(y), .z(z), .mode(mode), .i(counter), .mem_i(mem_i),
                .x_next(x_next), .y_next(y_next), .z_next(z_next));

always @(posedge clk) begin
    if (rst) begin
        x <= xin;
        y <= yin;
        z <= zin;
        mode <= modein;
    end
    else if (!finish) begin
        x <= x_next;
        y <= y_next;
        z <= z_next;
    end
end

always @(*) begin
    x_out = x_next;
    y_out = y_next;
    z_out = z_next;
end

endmodule
