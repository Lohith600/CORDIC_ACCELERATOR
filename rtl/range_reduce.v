module range_reduce #(parameter WIDTH=16) (input modein,input signed [WIDTH-1:0] xin,input signed [WIDTH-1:0] yin,input signed [WIDTH-1:0] zin,
output reg  signed [WIDTH-1:0] xout, output reg signed [WIDTH-1:0] yout, output reg  signed [WIDTH-1:0] zout,output flip);

reg flip;

// HALF_PI/PI are pinned to the default WIDTH=16, Q3.13 angle format --
// regenerate these (e.g. via the Python golden model) if WIDTH changes.
localparam signed [15:0] HALF_PI = 16'sd12868;  // pi/2 in Q3.13
localparam signed [15:0] PI      = 16'sd25736;  // pi   in Q3.13

always @(*)begin


    if((zin > HALF_PI) && (!modein))begin
      zout = zin - PI;
      flip = 1'b1;
      xout = xin;
      yout = yin;
    end 
    else if((zin < -HALF_PI) && (!modein))begin
        zout = zin + PI;
        flip = 1'b1;
        xout = xin;
        yout = yin;
    end
    else if((xin<0) && (modein))begin
        xout = -xin;
        yout = -yin;
        flip = 1'b1;
        zout = zin;
    end
    else begin
        xout = xin;
        yout = yin;
        zout = zin;
        flip = 1'b0;
    end


end

endmodule