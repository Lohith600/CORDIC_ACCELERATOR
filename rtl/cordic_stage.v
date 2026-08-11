module cordic_stage #(parameter WIDTH=16) (input signed [WIDTH-1:0] x,input signed [WIDTH-1:0] y,input signed[WIDTH-1:0] z,input mode,input [3:0] i,
input signed [WIDTH-1:0] mem_i,output reg signed [WIDTH-1:0] x_next,output reg signed [WIDTH-1:0] y_next,output reg signed [WIDTH-1:0] z_next);

reg alpha;//the factor that determines + or -
reg signed [WIDTH-1:0] x_shift , y_shift,z_op;

always @(*) begin
    alpha = (((y>=0) & mode) || ((z<0) & (!mode)));
end

always @(*) begin

    if(alpha)begin
    x_shift = -(x>>>i);
    y_shift = (y>>>i);
    z_op   = mem_i;
    end

    else begin
    x_shift = (x>>>i);
    y_shift = -(y>>>i);
    z_op = -(mem_i);
    end

end

always @(*) begin
    x_next = x + y_shift;
    y_next = y + x_shift;
    z_next = z + z_op;
end

endmodule




    






