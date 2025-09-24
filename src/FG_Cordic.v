// Copyright 2024 Dominik Brandstetter
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

//CORDIC implementation

module FG_Cordic #(parameter BITWIDTH = 8, BITWIDTH_PHASE = 10)(
    input wire clk_i,
    input wire clk_en_i,
    input wire rstn_i,

    // Interface
    input wire signed [BITWIDTH_PHASE-1:0] phase_i,
    input wire signed [BITWIDTH-1:0] x_initial_i, y_initial_i,
    
    output wire signed [BITWIDTH:0] cosine_o, sine_o 
);

genvar i;
localparam BITWIDTH_MAX = 8;

// look up table of atan values
wire signed [BITWIDTH_PHASE-1:0] atan_table [0:BITWIDTH_MAX-2];

// ----------------------- ATAN NOT SUPPORTED IN SYNTHESIS ----------------------- //

// //generate the atan look up table for up to 16 Bit Bitwidth -> ((atan(2^i) / 45°) * 2^x) 
// localparam real PI = 3.141592653589793;
// localparam real DEG_45 = 45.0 * (PI / 180.0);

// generate
//     for (i = 0; i < (BITWIDTH-1); i = i + 1)
//         begin: atan
//             assign atan_table[i] = ($atan(2.0**(-i)) / DEG_45) * (2.0**(BITWIDTH_PHASE-3));
//         end
// endgenerate

// ----------------------- LOOK UP TABLE ----------------------- //
// generated with python script -> needs to recomputed when changing parameters

assign atan_table[0] = 10'd128;
assign atan_table[1] = 10'd76;
assign atan_table[2] = 10'd40;
assign atan_table[3] = 10'd20;
assign atan_table[4] = 10'd10;
assign atan_table[5] = 10'd5;
assign atan_table[6] = 10'd3;

reg signed [BITWIDTH:0] x [0:BITWIDTH-1];
reg signed [BITWIDTH:0] y [0:BITWIDTH-1];
reg signed [BITWIDTH_PHASE-1:0] phase [0:BITWIDTH-1];

//get phase quadrant
wire [1:0] quadrant;
assign quadrant = phase_i[BITWIDTH_PHASE-1:BITWIDTH_PHASE-2];

// assign output
assign cosine_o = x[BITWIDTH-1];
assign sine_o = y[BITWIDTH-1];

// Assumptions:
// - SystemVerilog/Verilog-2001
// - x[], y[] are signed [BITWIDTH:0]; phase[] is [BITWIDTH_PHASE-1:0]
// - atan_table[i] matches phase width
// - clk_en_i is a clock-enable (optional gating)

integer k;
reg        sign;
reg signed [BITWIDTH:0] x_ssr, y_ssr;

always @(posedge clk_i) begin
  // synchronous reset (use negedge in sensitivity if you need async)
  if (!rstn_i) begin
    for (k = 0; k < BITWIDTH; k = k + 1) begin
      x[k]     <= '0;
      y[k]     <= '0;
      phase[k] <= '0;
    end
  end else if (clk_en_i) begin
    // ---------------- Stage 0 load (quadrant handling) ----------------
    case (quadrant)
      2'b00, 2'b11: begin
        // sign-extend 8->9 (example) – adjust if BITWIDTH differs
        x[0]     <= {{1{x_initial_i[BITWIDTH-1]}}, x_initial_i};
        y[0]     <= {{1{y_initial_i[BITWIDTH-1]}}, y_initial_i};
        phase[0] <= phase_i;
      end

      2'b01: begin // subtract pi/2
        x[0]     <= -{{1{y_initial_i[BITWIDTH-1]}}, y_initial_i};
        y[0]     <=  {{1{x_initial_i[BITWIDTH-1]}}, x_initial_i};
        phase[0] <= {2'b00, phase_i[BITWIDTH_PHASE-3:0]};
      end

      2'b10: begin // add pi/2
        x[0]     <=  {{1{y_initial_i[BITWIDTH-1]}}, y_initial_i};
        y[0]     <= -{{1{x_initial_i[BITWIDTH-1]}}, x_initial_i};
        phase[0] <= {2'b11, phase_i[BITWIDTH_PHASE-3:0]};
      end
      default: begin
        x[0]     <= {{1{x_initial_i[BITWIDTH-1]}}, x_initial_i};
        y[0]     <= {{1{y_initial_i[BITWIDTH-1]}}, y_initial_i};
        phase[0] <= phase_i;
      end
    endcase

    // ---------------- Iterative CORDIC pipeline ----------------
    for (k = 0; k < BITWIDTH-1; k = k + 1) begin
      // derive sign and arithmetic right shifts from current stage values
      sign = phase[k][BITWIDTH_PHASE-1];
      x_ssr = $signed(x[k]) >>> k;
      y_ssr = $signed(y[k]) >>> k;

      if (sign) begin
        x[k+1]     <= x[k] + y_ssr;
        y[k+1]     <= y[k] - x_ssr;
        phase[k+1] <= phase[k] + atan_table[k];
      end else begin
        x[k+1]     <= x[k] - y_ssr;
        y[k+1]     <= y[k] + x_ssr;
        phase[k+1] <= phase[k] - atan_table[k];
      end
    end
  end
end



endmodule
