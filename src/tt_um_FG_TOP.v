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

module tt_um_FG_TOP (
    input  wire [7:0] ui_in,    // Data inputs
    output wire [7:0] uo_out,   // DAC output data            [7:0]
    input  wire [7:0] uio_in,   // IOs: Enable | Adress input [7:4]
    output wire [7:0] uio_out,  // IOs: DAC control signals   [3:0] dac_clr_o | dac_pd_o | dac_wr_o active LOW | LED
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

localparam BITWIDTH = 8;
localparam BITWIDTH_TIMER = 10;
localparam CONFIG_REG_BITWIDTH = 64;
localparam SYNC_STAGES = 2;
localparam WR_STROBE_DELAY = 1;

// ----------------------- CONFIGURATION REGISTER ----------------------- //

// 8x 8-bit config registers, no array
wire WR_enable;
reg [7:0] CR0, CR1, CR2, CR3, CR4, CR5, CR6, CR7;
wire [63:0] CR_bus;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    // async reset
    CR0 <= 8'h00; CR1 <= 8'h00; CR2 <= 8'h00; CR3 <= 8'h00;
    CR4 <= 8'h00; CR5 <= 8'h00; CR6 <= 8'h00; CR7 <= 8'h00;
  end else if (WR_enable) begin
    // write selected register
    case (uio_in[6:4])            // only 0..7 used
      4'd0: CR0 <= ui_in;
      4'd1: CR1 <= ui_in;
      4'd2: CR2 <= ui_in;
      4'd3: CR3 <= ui_in;
      4'd4: CR4 <= ui_in;
      4'd5: CR5 <= ui_in;
      4'd6: CR6 <= ui_in;
      4'd7: CR7 <= ui_in;
      default: /* no write */;
    endcase
  end
end

assign CR_bus = {CR0, CR1, CR2, CR3, CR4, CR5, CR6, CR7};
assign uio_oe = 8'b00001111; // upper 4 bits input (Adress input), lower 4 bits output (DAC control signals)

// ----------------------- SYNCHRONIZER ----------------------- //
 
wire enable_i;
wire [2:0] select_i;

FG_Synchronizer #(.STAGES (SYNC_STAGES)) SW_Enable(
    .clk_i (clk),
    .rstn_i (rst_n),       
    .async_i (uio_in[7]),      
    .sync_o (WR_enable)
);

// LED
uio_out[0] = 1'd1; // ON LED

// ----------------------- FUNCTION GENERATOR ----------------------- //

FG_FunctionGenerator #(.BITWIDTH (BITWIDTH), .BITWIDTH_TIMER (BITWIDTH_TIMER), .CONFIG_REG_BITWIDTH(CONFIG_REG_BITWIDTH), .OUT_STROBE_DELAY (WR_STROBE_DELAY)) FG(
    .clk_i (clk),
    .rstn_i (rst_n),
    .outputEnable_i (enable_i),

    .CR_1_i (CR_1),
    .CR_2_i (CR_2),
    .CR_3_i (CR_3),
    .CR_4_i (CR_4),
    .CR_5_i (CR_5),
    .out_o (dac_o),
    .outValid_STRB_o(d_Valid_STRB)
);

//DAC
assign dac_clr_o = rst_n;       // clear / resets the DAC
assign dac_pd_o = 1'b1;         // disable power down mode

//WR pulse width > 20 ns -> 2 clock cycles are used (40 ns) -> strobes needs to be extended
wire d_Valid_STRB;
reg d_Valid_STRB_reg;

always @(posedge clk, negedge rst_n) begin

   if (!rst_n) begin
        d_Valid_STRB_reg <= 1'b0;
   end else
        d_Valid_STRB_reg <= d_Valid_STRB;
end

assign dac_wr_o = !(d_Valid_STRB || d_Valid_STRB_reg); //write data

// settling time of DAC > 10 us -> 100 kHz -> Prescaler of 500 (with a 50 MHz clock)
//localparam [15:0] prescaler_100kHz = 499; // 500 - 1
//assign PSC = prescaler_100kHz;

//localparam RADIX_UNSIGNED = 1'b1;
//assign Radix = RADIX_UNSIGNED;

//localparam real VDD = 3.3;
///localparam real voltage__digit =  (2**BITWIDTH - 1) / VDD;
//localparam real CORDIC_GAIN = 1.647;

endmodule