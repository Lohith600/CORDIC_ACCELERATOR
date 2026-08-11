`timescale 1ns/10ps
/* reads "xin yin zin mode" lines from sim/sweep_in.txt and feeds them in continuously, one new sample 
accepted per cycle (reset held high the whole time this design is actually meant to run this way, unlike the iterative
version's one-shot reset-per-vector protocol). End-to-end latency is a fixed, known 17 cycles (1 input-register load +
N=14 pipeline stages + 2 output-register stages), so output capture starts once cycle_count exceeds LATENCY=16 (i.e. at
cycle 17) and continues 16 more cycles past the last input to drain the pipe. Writes "x y z" to sim/sweep_out.txt,
same order as the input vectors.*/

module tb_pipe_sweep;

reg signed [15:0] xin, yin, zin;
reg modein, clk, reset;
wire signed [15:0] x, y, z;

cordic_top top(.clk(clk), .xin(xin), .yin(yin), .zin(zin), .modein(modein), .reset(reset),
                .x(x), .y(y), .z(z));

always #5 clk = ~clk;

localparam LATENCY = 16;

integer infile, outfile;
integer xi, yi, zi, mi;
integer code;
integer cycle_count;

initial begin
    clk = 0;
    reset = 1;

    infile = $fopen("sim/sweep_in.txt", "r");
    outfile = $fopen("sim/sweep_out.txt", "w");
    if (infile == 0) begin
        $display("ERROR: could not open sim/sweep_in.txt");
        $finish;
    end

    cycle_count = 0;

    code = $fscanf(infile, "%d %d %d %d\n", xi, yi, zi, mi);
    while (code == 4) begin
        xin = xi[15:0]; yin = yi[15:0]; zin = zi[15:0]; modein = mi[0];
        @(posedge clk); #1;
        cycle_count = cycle_count + 1;
        if (cycle_count > LATENCY)
            $fdisplay(outfile, "%0d %0d %0d", x, y, z);
        code = $fscanf(infile, "%d %d %d %d\n", xi, yi, zi, mi);
    end

    reset = 0;
    // drain the last LATENCY results still in flight
    repeat (LATENCY) begin
        @(posedge clk); #1;
        cycle_count = cycle_count + 1;
        if (cycle_count > LATENCY)
            $fdisplay(outfile, "%0d %0d %0d", x, y, z);
    end

    $fclose(infile);
    $fclose(outfile);
    $finish;
end

endmodule
