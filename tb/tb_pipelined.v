`timescale 1ns/10ps
// Feeds 14 different samples into the pipelined cordic_top, back to back.

module testbench;

reg signed [15:0] xin, yin, zin;
reg modein, clk, reset;
wire signed [15:0] x, y, z;

cordic_top top(.clk(clk), .xin(xin), .yin(yin), .zin(zin), .modein(modein), .reset(reset),
                .x(x), .y(y), .z(z));

always #5 clk = ~clk;

// stimulus: xin, yin, zin, mode
reg signed [15:0] xin_arr[0:13];
reg signed [15:0] yin_arr[0:13];
reg signed [15:0] zin_arr[0:13];
reg               mode_arr[0:13];

// expected: exp1 checked against x; exp2 checked against y (mode=0) or z (mode=1)
reg signed [15:0] exp1[0:13];
reg signed [15:0] exp2[0:13];
reg [127:0] name[0:13];

// captured output, one snapshot per post-load cycle
reg signed [15:0] cap_x[0:13];
reg signed [15:0] cap_y[0:13];
reg signed [15:0] cap_z[0:13];

integer idx;
integer TOL;
integer errors;

initial begin
    // rotation cases (mode=0): xin=1.0 fixed, yin=0, zin=angle
    xin_arr[0]=16384; yin_arr[0]=0; zin_arr[0]=1430;   mode_arr[0]=0; exp1[0]=16134;  exp2[0]=2847;   name[0]="rotate 10deg";
    xin_arr[1]=16384; yin_arr[1]=0; zin_arr[1]=7864;   mode_arr[1]=0; exp1[1]=9395;   exp2[1]=13422;  name[1]="rotate 55deg";
    xin_arr[2]=16384; yin_arr[2]=0; zin_arr[2]=11438;  mode_arr[2]=0; exp1[2]=2847;   exp2[2]=16134;  name[2]="rotate 80deg";
    xin_arr[3]=16384; yin_arr[3]=0; zin_arr[3]=14298;  mode_arr[3]=0; exp1[3]=-2844;  exp2[3]=16134;  name[3]="rotate 100deg";
    xin_arr[4]=16384; yin_arr[4]=0; zin_arr[4]=-1430;  mode_arr[4]=0; exp1[4]=16137;  exp2[4]=-2847;  name[4]="rotate -10deg";
    xin_arr[5]=16384; yin_arr[5]=0; zin_arr[5]=-7864;  mode_arr[5]=0; exp1[5]=9396;   exp2[5]=-13422; name[5]="rotate -55deg";
    xin_arr[6]=16384; yin_arr[6]=0; zin_arr[6]=-14298; mode_arr[6]=0; exp1[6]=-2847;  exp2[6]=-16134; name[6]="rotate -100deg";
    xin_arr[7]=16384; yin_arr[7]=0; zin_arr[7]=25021;  mode_arr[7]=0; exp1[7]=-16324; exp2[7]=1428;   name[7]="rotate 175deg";

    // vectoring cases (mode=1): xin/yin given directly, zin unused
    xin_arr[8]=3227;   yin_arr[8]=569;    zin_arr[8]=0; mode_arr[8]=1; exp1[8]=3278;   exp2[8]=1432;    name[8]="vectorize mag=0.2 10deg";
    xin_arr[9]=-1707;  yin_arr[9]=9681;   zin_arr[9]=0; mode_arr[9]=1; exp1[9]=9832;   exp2[9]=14298;   name[9]="vectorize mag=0.6 100deg";
    xin_arr[10]=4634;  yin_arr[10]=-4634; zin_arr[10]=0; mode_arr[10]=1; exp1[10]=6555;  exp2[10]=-6436;  name[10]="vectorize mag=0.4 -45deg";
    xin_arr[11]=-2276; yin_arr[11]=-12908; zin_arr[11]=0; mode_arr[11]=1; exp1[11]=13107; exp2[11]=-14298; name[11]="vectorize mag=0.8 -100deg";
    xin_arr[12]=-16135; yin_arr[12]=2845;  zin_arr[12]=0; mode_arr[12]=1; exp1[12]=16384; exp2[12]=24306;  name[12]="vectorize mag=1.0 170deg";
    xin_arr[13]=-8068; yin_arr[13]=-1423; zin_arr[13]=0; mode_arr[13]=1; exp1[13]=8194;  exp2[13]=-24306; name[13]="vectorize mag=0.5 -170deg";

    TOL = 3;
    clk = 0;
    reset = 0;

    // feed all 14 samples back to back, one accepted per cycle -- no checking here
    @(posedge clk); #1;
    reset = 1;
    xin = xin_arr[0]; yin = yin_arr[0]; zin = zin_arr[0]; modein = mode_arr[0];
    for (idx = 1; idx < 14; idx = idx + 1) begin
        @(posedge clk); #1;
        xin = xin_arr[idx]; yin = yin_arr[idx]; zin = zin_arr[idx]; modein = mode_arr[idx];
    end
    @(posedge clk); #1;  // this edge loads case 13
    reset = 0;

    @(posedge clk); #1;  // extra cycle for the top-level input register stage
    @(posedge clk); #1;  // 2 extra cycles for the pipelined output K-scale/mux stages
    @(posedge clk); #1;
    cap_x[0] = x;
    cap_y[0] = y;
    cap_z[0] = z;

    // capture only -- one snapshot per cycle, still no checking
    for (idx = 1; idx < 14; idx = idx + 1) begin
        @(posedge clk); #1;
        cap_x[idx] = x;
        cap_y[idx] = y;
        cap_z[idx] = z;
    end

    // verification pass, after the pipeline has fully drained
    errors = 0;
    for (idx = 0; idx < 14; idx = idx + 1) begin
        if (abs_diff(cap_x[idx], exp1[idx]) <= TOL &&
            abs_diff(mode_arr[idx] ? cap_z[idx] : cap_y[idx], exp2[idx]) <= TOL) begin
            $display("PASS %0s (case %0d): x=%0d %0s=%0d",
                      name[idx], idx, cap_x[idx], mode_arr[idx] ? "z" : "y",
                      mode_arr[idx] ? cap_z[idx] : cap_y[idx]);
        end else begin
            errors = errors + 1;
            $display("FAIL %0s (case %0d): got x=%0d y=%0d z=%0d | expected x=%0d %0s=%0d",
                      name[idx], idx, cap_x[idx], cap_y[idx], cap_z[idx],
                      exp1[idx], mode_arr[idx] ? "z" : "y", exp2[idx]);
        end
    end

    if (errors == 0)
        $display("\nALL 14 CASES PASSED");
    else
        $display("\n%0d CASE(S) FAILED", errors);

    $finish;
end

function integer abs_diff(input signed [15:0] a, input signed [15:0] b);
    abs_diff = (a >= b) ? (a - b) : (b - a);
endfunction

endmodule
