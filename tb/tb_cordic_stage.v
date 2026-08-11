`timescale 1ns/10ps
module testbench;

reg  signed [15:0] x, y, z, mem_i;
reg  [3:0] i;
reg  mode;
wire signed [15:0] x_next, y_next, z_next;

integer errors = 0;

cordic_stage cs(
    .x(x), .y(y), .z(z), .mode(mode), .i(i), .mem_i(mem_i),
    .x_next(x_next), .y_next(y_next), .z_next(z_next)
);

task check(input signed [15:0] exp_x, input signed [15:0] exp_y, input signed [15:0] exp_z, input [127:0] name);
begin
    #1; // let the combinational logic settle
    if (x_next !== exp_x || y_next !== exp_y || z_next !== exp_z) begin
        errors = errors + 1;
        $display("FAIL %0s : got x=%0d y=%0d z=%0d | expected x=%0d y=%0d z=%0d",
                  name, x_next, y_next, z_next, exp_x, exp_y, exp_z);
    end else begin
        $display("PASS %0s : x=%0d y=%0d z=%0d", name, x_next, y_next, z_next);
    end
end
endtask

initial begin
    // Test 1: i=0, z >= 0 (rotation, alpha=0 branch), K=9950, y=0, z=atan(2^0)
    // matches cordic_rotate()'s first iteration for a 45deg-ish angle
    mode = 0; i = 0; x = 16'sd9950; y = 16'sd0; z = 16'sd6434; mem_i = 16'sd6434;
    check(16'sd9950, 16'sd9950, 16'sd0, "rotate i=0 z>=0");

    // Test 2: i=1, z < 0 (rotation, alpha=1 branch) -- positive x/y, exercises the "else" alpha path
    mode = 0; i = 1; x = 16'sd9950; y = 16'sd9950; z = -16'sd6434; mem_i = 16'sd3798;
    check(16'sd14925, 16'sd4975, -16'sd2636, "rotate i=1 z<0");

    // Test 3: i=2, negative y -- the case that would break under a logical (>>) instead of
    // arithmetic (>>>) shift, since y is negative and must sign-extend, not zero-fill
    mode = 0; i = 2; x = 16'sd0; y = -16'sd9950; z = 16'sd100; mem_i = 16'sd2007;
    check(16'sd2488, -16'sd9950, -16'sd1907, "rotate i=2 negative y (sign-extend check)");

    // Test 4: vectoring mode, y >= 0 (alpha=1 branch) -- same shift/alpha wiring, opposite mode
    mode = 1; i = 0; x = 16'sd16384; y = 16'sd0; z = 16'sd0; mem_i = 16'sd6434;
    check(16'sd16384, -16'sd16384, 16'sd6434, "vectorize i=0 y>=0");

    // Test 5: vectoring mode, y < 0 (alpha=0 branch)
    mode = 1; i = 1; x = 16'sd16384; y = -16'sd8192; z = 16'sd0; mem_i = 16'sd3798;
    check(16'sd20480, 16'sd0, -16'sd3798, "vectorize i=1 y<0");

    #1;
    if (errors == 0)
        $display("ALL TESTS PASSED");
    else
        $display("%0d TEST(S) FAILED", errors);

    $finish;
end

endmodule
