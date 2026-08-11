`timescale 1ns/10ps

module testbench;

reg  signed [15:0] xin, yin, zin;
reg  modein, clk, reset;
wire signed [15:0] x, y, z;
wire done;

cordic_top top(
    .clk(clk), .xin(xin), .yin(yin), .zin(zin), .modein(modein), .reset(reset),
    .x(x), .y(y), .z(z), .done(done)
);

always #5 clk = ~clk;

initial begin
    $dumpfile("sim/tb_cordic_top.vcd");
    $dumpvars(0, testbench);

    $monitor("time=%0t rst=%b done=%b | xin=%0d yin=%0d zin=%0d mode=%b | x=%0d y=%0d z=%0d",
              $time, reset, done, xin, yin, zin, modein, x, y, z);

    clk = 0;

    //inputs to try different cases 
    modein = 0;         // 0 = rotation, 1 = vectoring
    xin    = 16'sd16384; //Q2.14 (1.0 -- K is now applied at the output, not pre-scaled here)
    yin    = 16'sd0;    // Q2.14
    zin    = 16'h10C1; // Q3.13 (angle for rotation, unused for vectoring)
   

    reset = 1;
    @(posedge clk);
    #1 reset = 0;

    // to run long enough for all N iterations to complete
    #250;

    $finish;
end

endmodule
