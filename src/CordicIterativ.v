// Copyright 2025 Dominik Brandstetter
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE−2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`include "CordicSlice.v"

module CordicInterativ(
    input  wire              clk_i,
    input  wire              rstn_i,
    input  wire              strb_data_valid_i,
    input  wire signed [7:0] X_i,
    input  wire signed [7:0] Y_i,
    input  wire signed [7:0] Z_i,
    output wire signed [7:0] X_o,
    output wire signed [7:0] Y_o,
    output wire signed [7:0] Z_o,
    output wire              strb_data_valid_o
);

// ------------------------- params -------------------------- //

localparam integer N_INT             = 0;
localparam integer N_FRAC            = -7;
localparam integer BITWIDTH          = N_INT - N_FRAC + 1;

// Additional parameters for CORDIC mode and coordinate system: TODO
localparam integer CORDIC_MODE       = 0;  // 0 = ROTATION, 1 = VECTORING
localparam integer COORDINATE_SYSTEM = 0;  // 0 = CIRCULAR, 1 = LINEAR, 2 = HYPERBOLIC

localparam integer N_CORDIC_ITERATIONS   = BITWIDTH;           
localparam integer SHIFT_VALUE_BITWIDTH  = $clog2(N_CORDIC_ITERATIONS + 1);

//generate arctan lookup table from Matlab
localparam signed [BITWIDTH-1:0] PI_HALF = 8'b01000000;
localparam [N_CORDIC_ITERATIONS*BITWIDTH-1:0] ATAN_TABLE = {
    8'b00000000,  // 0.000000 
    8'b00000001,  // 0.007812 
    8'b00000001,  // 0.007812 
    8'b00000011,  // 0.023438 
    8'b00000101,  // 0.039062 
    8'b00001010,  // 0.078125 
    8'b00010011,  // 0.148438 
    8'b00100000}; // 0.250000 

function [BITWIDTH-1:0] atan_value;
    input [SHIFT_VALUE_BITWIDTH-1:0] i;
    begin
        atan_value = ATAN_TABLE[i*BITWIDTH-1 +: BITWIDTH];
    end
endfunction

// ------------------------- signals ------------------------- //

// ROC stage
reg  signed [BITWIDTH-1:0] roc_in_X, roc_in_Y, roc_in_Z;
reg  signed [BITWIDTH-1:0] roc_out_X, roc_out_Y, roc_out_Z;

// CORDIC datapath
reg  signed [BITWIDTH-1:0] cordic_in_X,  cordic_in_Y,  cordic_in_Z;
wire signed [BITWIDTH-1:0] cordic_out_X, cordic_out_Y, cordic_out_Z;

reg  [SHIFT_VALUE_BITWIDTH-1:0] shift_value;
wire signed [BITWIDTH-1:0] current_rotation_angle;

// ------------------------- ROC preprocessing ------------------------- //

always @(posedge clk_i) begin
    if (!rstn_i) begin
        roc_in_X <= {BITWIDTH{1'b0}};
        roc_in_Y <= {BITWIDTH{1'b0}};
        roc_in_Z <= {BITWIDTH{1'b0}};
    end else if (strb_data_valid_i) begin
        roc_in_X <= X_i;
        roc_in_Y <= Y_i;
        roc_in_Z <= Z_i;
    end
end

always @(*) begin
    if (roc_in_Z > PI_HALF) begin
        // Rotate (X,Y) by +90° -> subtract PI/2 from Z
        roc_out_X = -roc_in_Y;
        roc_out_Y =  roc_in_X;
        roc_out_Z =  roc_in_Z - PI_HALF;
    end else if (roc_in_Z < -PI_HALF) begin
        // Rotate (X,Y) by -90° -> add PI/2 to Z
        roc_out_X =  roc_in_Y;
        roc_out_Y = -roc_in_X;
        roc_out_Z =  roc_in_Z + PI_HALF;
    end else begin
        // Pass-through
        roc_out_X = roc_in_X;
        roc_out_Y = roc_in_Y;
        roc_out_Z = roc_in_Z;
    end
end

// ------------------------- CORDIC slice ------------------------- //

CordicSlice #(
    .N_INT(N_INT),
    .N_FRAC(N_FRAC),
    .CORDIC_MODE(CORDIC_MODE),
    .COORDINATE_SYSTEM(COORDINATE_SYSTEM),
    .SHIFT_BITWIDTH(SHIFT_VALUE_BITWIDTH)
) slice (
    .clk_i(clk_i),
    .rstn_i(rstn_i),
    .current_rotation_angle_i(current_rotation_angle),
    .shift_value_i(shift_value),
    .X_i(cordic_in_X),
    .Y_i(cordic_in_Y),
    .Z_i(cordic_in_Z),
    .X_o(cordic_out_X),
    .Y_o(cordic_out_Y),
    .Z_o(cordic_out_Z)
);

// ------------------------- control & muxing ------------------------- //

// Datapath mux
always @(*) begin
    if (shift_value == 0) begin
        cordic_in_X = roc_out_X;
        cordic_in_Y = roc_out_Y;
        cordic_in_Z = roc_out_Z;
    end else begin
        cordic_in_X = cordic_out_X;
        cordic_in_Y = cordic_out_Y;
        cordic_in_Z = cordic_out_Z;
    end
end

// Iteration counter (shift_value)
always @(posedge clk_i) begin
    if (!rstn_i || strb_data_valid_i) begin
        shift_value <= {SHIFT_VALUE_BITWIDTH{1'b0}};
    end else if (shift_value != (N_CORDIC_ITERATIONS[SHIFT_VALUE_BITWIDTH-1:0] + 1)) begin
        shift_value <= shift_value + 1'b1;
    end
end

// Current angle
assign current_rotation_angle = (shift_value < N_CORDIC_ITERATIONS[SHIFT_VALUE_BITWIDTH-1:0]) ? atan_value(shift_value[SHIFT_VALUE_BITWIDTH-1:0]) : {BITWIDTH{1'b0}};

// Output strobe after final iteration
assign strb_data_valid_o = (shift_value == N_CORDIC_ITERATIONS[SHIFT_VALUE_BITWIDTH-1:0]);

assign X_o = cordic_out_X;
assign Y_o = cordic_out_Y;
assign Z_o = cordic_out_Z;

endmodule
