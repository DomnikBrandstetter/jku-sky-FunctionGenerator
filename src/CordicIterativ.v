// CORDIC iterative architecture (Verilog-2001) — optimized for Y_i == 0

`include "CordicSlice.v"

module CordicInterativ(
    input  wire              clk_i,
    input  wire              rstn_i,
    input  wire              strb_data_valid_i,
    input  wire signed [7:0] X_i,
    input  wire signed [7:0] Y_i,  // not used (assumed 0)
    input  wire signed [7:0] Z_i,
    output wire signed [7:0] X_o,
    output wire signed [7:0] Y_o,
    output wire signed [7:0] Z_o,
    output wire              strb_data_valid_o
);

  // ------------------------- params --------------------------
  localparam integer N_INT   = 0;
  localparam integer N_FRAC  = -7;
  localparam integer BITWIDTH= N_INT - N_FRAC + 1; // =10

  localparam integer CORDIC_MODE       = 0;  // 0=ROTATION
  localparam integer COORDINATE_SYSTEM = 0;  // 0=CIRCULAR

  // Verilog-2001 clog2
  function integer clog2;
    input integer value; integer v;
    begin
      v = value - 1; clog2 = 0;
      while (v > 0) begin v = v >> 1; clog2 = clog2 + 1; end
    end
  endfunction

  localparam integer N_CORDIC_ITERATIONS  = BITWIDTH;
  localparam integer SHIFT_VALUE_BITWIDTH = clog2(N_CORDIC_ITERATIONS + 1);

  localparam signed [BITWIDTH-1:0] PI_HALF = 8'sb01000000;
  localparam [N_CORDIC_ITERATIONS*BITWIDTH-1:0] ATAN_TABLE = {
      8'b00000001,  // 7
      8'b00000011,  // 6
      8'b00000101,  // 5
      8'b00001010,  // 4
      8'b00010100,  // 3
      8'b00101000,  // 2
      8'b01001100,  // 1
      8'b10000000   // 0
  };

  function [BITWIDTH-1:0] atan_value;
    input integer i;
    begin
      atan_value = ATAN_TABLE[(i+1)*BITWIDTH-1 -: BITWIDTH];
    end
  endfunction

  // ------------------------- signals -------------------------
  // ROC inputs: only X,Z are latched (Y is known 0)
  reg  signed [BITWIDTH-1:0] roc_in_X, roc_in_Z;

  // First-cycle seeds (combinational)
  reg  signed [BITWIDTH-1:0] seed_X, seed_Y, seed_Z;

  // CORDIC datapath
  reg  signed [BITWIDTH-1:0] cordic_in_X,  cordic_in_Y,  cordic_in_Z;
  wire signed [BITWIDTH-1:0] cordic_out_X, cordic_out_Y, cordic_out_Z;

  reg  [SHIFT_VALUE_BITWIDTH-1:0] shift_value;
  wire signed [BITWIDTH-1:0]      current_rotation_angle;

  // ------------------------- ROC preprocessing -------------------------
  // Latch only on new sample
  always @(posedge clk_i) begin
    if (!rstn_i) begin
      roc_in_X <= {BITWIDTH{1'b0}};
      roc_in_Z <= {BITWIDTH{1'b0}};
    end else if (strb_data_valid_i) begin
      roc_in_X <= X_i;
      roc_in_Z <= Z_i;
    end
  end

  // Since Y_i == 0:
  //  Z >  +PI/2 : X=0,      Y= +X, Z-PI/2
  //  Z <  -PI/2 : X=0,      Y= -X, Z+PI/2
  //  else       : X= +X,    Y=  0, Z
  always @* begin
    if (roc_in_Z > PI_HALF) begin
      seed_X = {BITWIDTH{1'b0}};
      seed_Y =  roc_in_X;
      seed_Z =  roc_in_Z - PI_HALF;
    end else if (roc_in_Z < -PI_HALF) begin
      seed_X = {BITWIDTH{1'b0}};
      seed_Y = -roc_in_X;
      seed_Z =  roc_in_Z + PI_HALF;
    end else begin
      seed_X =  roc_in_X;
      seed_Y = {BITWIDTH{1'b0}};
      seed_Z =  roc_in_Z;
    end
  end

  // ------------------------- CORDIC slice -------------------------
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

  // ------------------------- control & muxing -------------------------
  // First-cycle select: cheaper as reduction NOR than wide equality
  wire first = ~|shift_value;

  always @* begin
    if (first) begin
      cordic_in_X = seed_X;
      cordic_in_Y = seed_Y;  // derived from X only
      cordic_in_Z = seed_Z;
    end else begin
      cordic_in_X = cordic_out_X;
      cordic_in_Y = cordic_out_Y;
      cordic_in_Z = cordic_out_Z;
    end
  end

  // Iteration counter
  always @(posedge clk_i) begin
    if (!rstn_i || strb_data_valid_i) begin
      shift_value <= {SHIFT_VALUE_BITWIDTH{1'b0}};
    end else if (shift_value != (N_CORDIC_ITERATIONS + 1)) begin
      shift_value <= shift_value + 1'b1;
    end
  end

  // Angle lookup and done strobe
  assign current_rotation_angle = (shift_value < N_CORDIC_ITERATIONS)
                                  ? atan_value(shift_value)
                                  : {BITWIDTH{1'b0}};

  assign strb_data_valid_o = (shift_value == N_CORDIC_ITERATIONS);

  assign X_o = cordic_out_X;
  assign Y_o = cordic_out_Y;
  assign Z_o = cordic_out_Z;

endmodule

