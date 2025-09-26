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

`include "FG_FunctionGenerator.v"
`include "FG_synchronizer.v"

module tt_um_FG_TOP (
    input  wire [7:0] ui_in,    // Data inputs                   [7:0]
    output wire [7:0] uo_out,   // DAC output data               [7:0]
    input  wire [7:0] uio_in,   // IOs: Register control signals [7] Enable (AL)   | [6] WR_enable (AL) | [5:3] Adress input
    output wire [7:0] uio_out,  // IOs: DAC control signals      [2] dac_wr_o (AL) | [1] dac_pd_o  (AL) | [0] dac_clr_o (AL) 
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

localparam BITWIDTH            = 8;
localparam BITWIDTH_PRESCALAR  = 9;
localparam BITWIDTH_TIMER      = 10;
localparam CONFIG_REG_BITWIDTH = 64;
localparam SYNC_STAGES         = 2;

// ----------------------- CONFIGURATION REGISTER ----------------------- //

// 8 x 8-bit config registers
wire WR_enable_n;
wire enable, enable_n;
wire d_Valid_STRB;

reg [7:0] CR0, CR1, CR2, CR3, CR4, CR5, CR6, CR7;
wire [63:0] CR_bus;

assign enable = ~enable_n;

always @(posedge clk) begin
  if (!rst_n) begin 
    CR0 <= 8'h61;   
    CR1 <= 8'h40; 
    CR2 <= 8'h68; 
    CR3 <= 8'h00;
    CR4 <= 8'h00; 
    CR5 <= 8'h00; 
    CR6 <= 8'h32; 
    CR7 <= 8'h00;
  end else if (!enable && !WR_enable_n) begin
    // write selected register
    case (uio_in[5:3]) 
      3'd0: CR0 <= ui_in;
      3'd1: CR1 <= ui_in;
      3'd2: CR2 <= ui_in;
      3'd3: CR3 <= ui_in;
      3'd4: CR4 <= ui_in;
      3'd5: CR5 <= ui_in;
      3'd6: CR6 <= ui_in;
      3'd7: CR7 <= ui_in;
      default: /* no write */;
    endcase
  end
end

assign CR_bus = {CR0, CR1, CR2, CR3, CR4, CR5, CR6, CR7};
assign uio_oe = 8'b00000111; // upper 5 bits input (control and address input), lower 3 bits output (DAC control signals)

// ----------------------- SYNCHRONIZER ----------------------- //

FG_Synchronizer #(.STAGES (SYNC_STAGES)) WR_Enable(
    .clk_i (clk),
    .rstn_i (rst_n),       
    .async_i (uio_in[6]),      
    .sync_o (WR_enable_n)
);

FG_Synchronizer #(.STAGES (SYNC_STAGES)) Enable(
    .clk_i (clk),
    .rstn_i (rst_n),       
    .async_i (uio_in[7]),      
    .sync_o (enable_n)
);

// ----------------------- FUNCTION GENERATOR ----------------------- //

FG_FunctionGenerator #(.BITWIDTH (BITWIDTH), .BITWIDTH_PRESCALAR(BITWIDTH_PRESCALAR), .BITWIDTH_TIMER (BITWIDTH_TIMER), .CONFIG_REG_BITWIDTH(CONFIG_REG_BITWIDTH)) FG(
    .clk_i (clk),
    .rstn_i (rst_n),
    .enable_i (enable),

    .CR_bus_i (CR_bus),
    .out_o (uo_out),
    .outValid_STRB_o(d_Valid_STRB)
);

assign uio_out[0] = rst_n;           // dac_clr_o clear (active low)
assign uio_out[1] = enable;          // dac_pd_o        (active low)
assign uio_out[2] = !(d_Valid_STRB); // dac_wr_o        (active low) WR pulse width > 20 ns
assign uio_out[3] = 1'd0; 
assign uio_out[4] = 1'd0;
assign uio_out[5] = 1'd0;
assign uio_out[6] = 1'd0;
assign uio_out[7] = 1'd0;

endmodule