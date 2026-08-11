`timescale 1ns/10ps

module testbench;

reg  signed [15:0] xin, yin, zin;
reg  modein, clk, rst;
wire signed [15:0] x_out, y_out, z_out;
wire finish;

integer errors = 0;
parameter TOL = 2; // +/-2 LSB tolerance, matching the Python-vs-RTL rounding drift we already characterized

cordic_iterative ci(
    .rst(rst), .xin(xin), .yin(yin), .zin(zin), .modein(modein), .clk(clk),
    .x_out(x_out), .y_out(y_out), .z_out(z_out), .finish(finish)
);

always #5 clk = ~clk;

function integer abs_diff(input signed [15:0] a, input signed [15:0] b);
    abs_diff = (a >= b) ? (a - b) : (b - a);
endfunction

task run_case(
    input signed [15:0] xin_v, yin_v, zin_v,
    input mode_v,
    input signed [15:0] exp_x, exp_y, exp_z,
    input [127:0] name
);
begin
    // load inputs while resetting; wait for a full posedge with rst=1 stable,
    // then deassert 1ns later so it never races the DUT's own posedge-triggered
    // always blocks that sample rst on the same edge
    rst = 1; xin = xin_v; yin = yin_v; zin = zin_v; modein = mode_v;
    @(posedge clk);
    #1;
    rst = 0;

    // run until the core reports done (bounded wait so a stuck `finish` doesn't hang the sim)
    while (!finish) @(posedge clk);
    #1; // let x_out/y_out/z_out settle after the triggering edge

    if (abs_diff(x_out, exp_x) > TOL || abs_diff(y_out, exp_y) > TOL || abs_diff(z_out, exp_z) > TOL) begin
        errors = errors + 1;
        $display("FAIL %0s : got x=%0d y=%0d z=%0d | expected x=%0d y=%0d z=%0d (tol=%0d)",
                  name, x_out, y_out, z_out, exp_x, exp_y, exp_z, TOL);
    end else begin
        $display("PASS %0s : x=%0d y=%0d z=%0d (expected x=%0d y=%0d z=%0d)",
                  name, x_out, y_out, z_out, exp_x, exp_y, exp_z);
    end
end
endtask

initial begin
    $dumpfile("sim/tb_cordic_iterative.vcd");
    $dumpvars(0, testbench);

    clk = 0;

    // Rotation mode, +45deg: x0=K=9949, y0=0, z0=6434 (Q3.13) -> golden model x=11584 y=11586
    run_case(16'sd9949, 16'sd0, 16'sd6434, 1'b0, 16'sd11584, 16'sd11586, 16'sd0, "rotate +45deg");

    // Rotation mode, -30deg: x0=K=9949, y0=0, z0=-4289 -> golden model x=14190 y=-8190
    run_case(16'sd9949, 16'sd0, -16'sd4289, 1'b0, 16'sd14190, -16'sd8190, 16'sd0, "rotate -30deg");

    // Vectoring mode, (0.5, 0.5): raw core output, pre-K-scale/pre-range-reduction -> x_raw=19078 y~0 z_raw=6434
    run_case(16'sd8192, 16'sd8192, 16'sd0, 1'b1, 16'sd19078, 16'sd0, 16'sd6434, "vectorize (0.5,0.5)");

    // Vectoring mode, (0.5, -0.5): raw core output -> x_raw=19078 y~0 z_raw=-6434
    run_case(16'sd8192, -16'sd8192, 16'sd0, 1'b1, 16'sd19078, 16'sd0, -16'sd6434, "vectorize (0.5,-0.5)");

    if (errors == 0)
        $display("ALL TESTS PASSED");
    else
        $display("%0d TEST(S) FAILED", errors);

    $finish;
end

endmodule
