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

`timescale 1ns/1ps

module FG_TOP_Dominik_Brandstetter_tb;

  // ---------------- DUT & TB signals ----------------
  reg         clk_tb  = 1'b0;
  reg         rstn_tb = 1'b0;

  // TB drives:
  reg  [7:0]  ui_in;
  reg  [7:0]  uio_in;

  // DUT outputs:
  wire [7:0]  uo_out;
  wire [7:0]  uio_out;
  wire [7:0]  uio_oe;

  // DUT
  tt_um_FG_TOP_Dominik_Brandstetter #() FG_TOP (
  `ifdef GL_TEST
    .VPWR (1'b1),
    .VGND (1'b0),
  `endif
    .ui_in  (ui_in),
    .uo_out (uo_out),
    .uio_in (uio_in),
    .uio_out(uio_out),
    .uio_oe (uio_oe),
    .ena    (1'b1),
    .clk    (clk_tb),
    .rst_n  (rstn_tb)
  );

  // 20 MHz clock
  always #25 clk_tb = ~clk_tb;

  // ------------- UIO address/control mapping -------------
  localparam [7:0]   UIO_BASE = 8'b1000_0000; // base pattern (addr steps: +0x08)
  localparam integer ADDR_LSB = 3;            // address at bits [5:3]

  // Optional control bits (adjust to your proto)
  localparam integer UIO_EN_BIT = 7; // enable bit position
  localparam integer UIO_WR_BIT = 6; // write strobe bit position

  // ---------------- Write helpers ----------------
  // Write one 8-bit register at 3-bit address (0..6 for 56-bit total)
  task cfg_wr_byte;
    input [2:0] addr;
    input [7:0] data;
  begin
    // address & data setup
    uio_in = UIO_BASE | (addr << ADDR_LSB);
    ui_in  = data;

    // WR pulse
    uio_in[UIO_WR_BIT] = 1'b0;
    #200;
    uio_in[UIO_WR_BIT] = 1'b1;
    #200;
  end
  endtask

  // Write full 56-bit config as 7 bytes (addr 0..6)
  task cfg_wr56;
    input [55:0] cfg;
    integer i;
  begin
    uio_in = UIO_BASE;
    #1000;

    for (i = 0; i < 7; i = i + 1) begin
      cfg_wr_byte(i[2:0], cfg[8*(6-i) +: 8]);
    end

    #1000;
    uio_in[UIO_EN_BIT] = 1'b0;
  end
  endtask

  // ------------- Field packer (new 56-bit map) -------------
  // 55: constant, 54: modulated (0=Wave,1=Sine), 53..48: Prescaler[5:0],
  // 47..40: Counter, 
  // 39..32: Phase/ON, 
  // 31..24: Rise, 
  // 23..16: Fall,
  // 15..8:  Amplitude,
  //  7..0:  Offset

  function [55:0] cfg_pack56;
    input        constant_sig;      // bit 55
    input        modulated_sig;     // bit 54
    input  [5:0] prescaler;         // 53..48
    input  [7:0] counter_val;       // 47..40
    input  [7:0] phase_or_oncnt;    // 39..32
    input  [7:0] slope_rise;        // 31..24
    input  [7:0] slope_fall;        // 23..16
    input  [7:0] amplitude;         // 15..8
    input  [7:0] offset;            // 7..0
    reg   [55:0] w;
  begin
    w          = 56'd0;
    w[55]      = constant_sig;
    w[54]      = modulated_sig;
    w[53:48]   = prescaler[5:0];
    w[47:40]   = counter_val[7:0];
    w[39:32]   = phase_or_oncnt[7:0];
    w[31:24]   = slope_rise[7:0];
    w[23:16]   = slope_fall[7:0];
    w[15:8]    = amplitude[7:0];
    w[7:0]     = offset[7:0];
    cfg_pack56 = w;
  end
  endfunction

  reg [55:0] cfg_constant, cfg_trapez, cfg_rect, cfg_sawtooth, cfg_triangle, cfg_sine;

  // ---------------- Stimulus ----------------
  initial begin
    // Defaults
    ui_in  = 8'h00;
    uio_in = 8'b0100_0000;

    // Reset
    rstn_tb = 1'b0;
    #200;
    rstn_tb = 1'b1;
    #500;

    // Config constant mode
    cfg_constant = cfg_pack56(
      /*constant_sig   */ 1'b1,
      /*modulated_sig  */ 1'b0,
      /*prescaler      */ 6'd20,
      /*counter_val    */ 8'd200,
      /*phase_or_oncnt */ 8'd64,
      /*slope_rise     */ 8'd4,
      /*slope_fall     */ 8'd4,
      /*amplitude      */ 8'd100,
      /*offset         */ -8'sd10
    );

    // Config trapez mode
    cfg_trapez = cfg_pack56(
      /*constant_sig   */ 1'b0,
      /*modulated_sig  */ 1'b0,
      /*prescaler      */ 6'd20,
      /*counter_val    */ 8'd99,
      /*phase_or_oncnt */ 8'd50,
      /*slope_rise     */ 8'd5,
      /*slope_fall     */ 8'd10,
      /*amplitude      */ 8'd100,
      /*offset         */ 8'd10
    );

    // Config rect mode
    cfg_rect = cfg_pack56(
      /*constant_sig   */ 1'b0,
      /*modulated_sig  */ 1'b0,
      /*prescaler      */ 6'd20,
      /*counter_val    */ 8'd99,
      /*phase_or_oncnt */ 8'd50,
      /*slope_rise     */ 8'd254,
      /*slope_fall     */ 8'd254,
      /*amplitude      */ 8'd100,
      /*offset         */ 8'd10
    );

    // Config sawtooth mode
    cfg_sawtooth = cfg_pack56(
      /*constant_sig   */ 1'b0,
      /*modulated_sig  */ 1'b0,
      /*prescaler      */ 6'd20,
      /*counter_val    */ 8'd99,
      /*phase_or_oncnt */ 8'd99,
      /*slope_rise     */ 8'd1,
      /*slope_fall     */ 8'd254,
      /*amplitude      */ 8'd100,
      /*offset         */ 8'd10
    );

    // Config triangle mode
    cfg_triangle = cfg_pack56(
      /*constant_sig   */ 1'b0,
      /*modulated_sig  */ 1'b0,
      /*prescaler      */ 6'd20,
      /*counter_val    */ 8'd99,
      /*phase_or_oncnt */ 8'd50,
      /*slope_rise     */ 8'd1,
      /*slope_fall     */ 8'd1,
      /*amplitude      */ 8'd100,
      /*offset         */ 8'd10
    );

    // Config B: sine mode (11719 Hz @ 20 MHz clk)
    cfg_sine = cfg_pack56(
      /*constant_sig   */ 1'b0,
      /*modulated_sig  */ 1'b1,  
      /*prescaler      */ 6'd40,
      /*counter_val    */ 8'd6,
      /*phase_or_oncnt */ 8'd64,
      /*slope_rise     */ 8'd0,
      /*slope_fall     */ 8'd0,
      /*amplitude      */ 8'd50,
      /*offset         */ 8'd0
    );
    
    cfg_wr56(cfg_constant);
    #1000000;
    cfg_wr56(cfg_trapez);
    #1000000;
    cfg_wr56(cfg_rect);
    #1000000;
    cfg_wr56(cfg_sawtooth);
    #1000000;
    cfg_wr56(cfg_triangle);
    #1000000;
    cfg_wr56(cfg_sine);
    #1000000;

  end

endmodule