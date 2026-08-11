`timescale 1ns/10ps
/*  reads "xin yin zin mode" lines fromsim/sweep_in.txt, runs each through cordic_top, and writes the resulting
 "x y z" to sim/sweep_out.txt (one line per input, same order). Used by
model/hw_sweep.py to pull real hardware-simulation results into Python.*/

module tb_sweep;

reg  signed [15:0] xin, yin, zin;
reg  modein, clk, reset;
wire signed [15:0] x, y, z;
wire done;

cordic_top top(
    .clk(clk), .xin(xin), .yin(yin), .zin(zin), .modein(modein), .reset(reset),
    .x(x), .y(y), .z(z), .done(done)
);

always #5 clk = ~clk;

integer infile, outfile;
integer xi, yi, zi, mi;
integer code;

initial begin
    clk = 0;
    reset = 1;

    infile = $fopen("sim/sweep_in.txt", "r");
    outfile = $fopen("sim/sweep_out.txt", "w");
    if (infile == 0) begin
        $display("ERROR: could not open sim/sweep_in.txt");
        $finish;
    end

    code = $fscanf(infile, "%d %d %d %d\n", xi, yi, zi, mi);
    while (code == 4) begin
        xin = xi[15:0]; yin = yi[15:0]; zin = zi[15:0]; modein = mi[0];

        reset = 1;
        @(posedge clk);
        #1;
        reset = 0;

        @(posedge done);
        #1;

        $fdisplay(outfile, "%0d %0d %0d", x, y, z);

        code = $fscanf(infile, "%d %d %d %d\n", xi, yi, zi, mi);
    end

    $fclose(infile);
    $fclose(outfile);
    $finish;
end

endmodule
