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

`include "FG_Timer.v"
`include "CordicIterativ.v"
`include "FG_WaveformGen.v"

module FG_FunctionGenerator #(parameter BITWIDTH = 8, BITWIDTH_PRESCALAR = 6, BITWIDTH_TIMER = 8, CONFIG_REG_BITWIDTH = 56)(
    input wire clk_i,
    input wire rstn_i,
    input wire enable_i,

    input wire [CONFIG_REG_BITWIDTH-1:0] CR_bus_i,
        // 55      -> constant signal  - BIT (0 = False    | 1 = True) 
        // 54      -> modulated signal - BIT (0 = Waveform | 1 = Sine) 
        // 53 - 48 -> Prescaler 
        // 47 - 40 -> Counter Value
        // 39 - 32 -> Initial phase for sine, ON-Counter for waveform generation
        // 31 - 24 -> Rising slope for Waveform generation
        // 23 - 16 -> Falling slope for Waveform generation  
        // 15 - 8  -> Amplitude
        //  7 - 0  -> Offset 

    output wire signed [BITWIDTH-1:0] out_o,
    output wire outValid_STRB_o
);

// ----------------------- CONSTANTS AND CONFIGURATION REGISTERS ----------------------- //

// Config Reg 1 list
localparam CS_MODE_POS                 = 55;
localparam MS_MODE_POS                 = 54;
localparam TIMER_PRESCALER_POS         = 48;
localparam TIMER_COUNTER_POS           = 40;
localparam INIT_PHASE___ON_COUNTER_POS = 32;
localparam RISE_SLOPE_POS              = 24;
localparam FALL_SLOPE_POS              = 16;
localparam AMPLITUDE_POS               = 8;
localparam OFFSET_POS                  = 0;

wire CS_Mode, MS_Mode;
assign CS_Mode = CR_bus_i[CS_MODE_POS];
assign MS_Mode = CR_bus_i[CS_MODE_POS] ^ CR_bus_i[MS_MODE_POS];

wire [BITWIDTH_PRESCALAR-1:0] timerPrescaler;
assign timerPrescaler = CR_bus_i[TIMER_PRESCALER_POS+BITWIDTH_PRESCALAR-1:TIMER_PRESCALER_POS];

wire [BITWIDTH_TIMER-1:0] timerCounter;
assign timerCounter = CR_bus_i[TIMER_COUNTER_POS+BITWIDTH_TIMER-1:TIMER_COUNTER_POS];

wire [BITWIDTH_TIMER-1:0] initPhase___ON_counter;
assign initPhase___ON_counter = CR_bus_i[INIT_PHASE___ON_COUNTER_POS+BITWIDTH_TIMER-1:INIT_PHASE___ON_COUNTER_POS];

wire [BITWIDTH-1:0] k_rise, k_fall;
assign k_rise = CR_bus_i[RISE_SLOPE_POS+BITWIDTH-1:RISE_SLOPE_POS];
assign k_fall = CR_bus_i[FALL_SLOPE_POS+BITWIDTH-1:FALL_SLOPE_POS];

wire [BITWIDTH-1:0] amplitude;
assign amplitude = CR_bus_i[AMPLITUDE_POS+BITWIDTH-1:AMPLITUDE_POS];

wire signed [BITWIDTH-1:0] offset;
assign offset = CR_bus_i[OFFSET_POS+BITWIDTH-1:OFFSET_POS];

// ----------------------- TIMER ----------------------- //
// is used to perform timer functions -> time base for sine wave generation and waveform generation
// generates a clock enable signal with a frequency determined by the prescaler and counter value

wire [BITWIDTH_TIMER-1:0] counterValue;
wire clk_en;

FG_Timer #(.COUNTER_BITWIDTH (BITWIDTH_TIMER), .PSC_BITWIDTH (BITWIDTH_PRESCALAR)) Timer (
    .clk_i (clk_i),
    .rstn_i (rstn_i),
 
    .enable_i (enable_i),
    .timerMode_i (MS_Mode),
    .prescaler_i (timerPrescaler),
    .counter_i (timerCounter),
    .preload_i (initPhase___ON_counter),
    
    .counterVal_o (counterValue),
    .clk_en_o (clk_en)   
);

// ----------------------- CORDIC ----------------------- //
// is used to generate a sine wave with a given amplitude and phase (counterValue)
localparam SIGNED_TO_UNSIGNED = 2 ** (BITWIDTH-1); 

wire signed [7:0] x_initial, y_initial;
wire signed [BITWIDTH-1:0] sine_cordic;
wire [BITWIDTH-1:0] sine;
wire signed [7:0] X_out;
wire signed [7:0] Z_out;
wire strb_data_valid_cordic;

assign y_initial = 8'd0;
assign x_initial = amplitude;

CordicInterativ Cordic (
    .clk_i (clk_i),
    .rstn_i (rstn_i),             
    .strb_data_valid_i(clk_en),
    .X_i (x_initial),
    .Y_i (y_initial),
    .Z_i (counterValue),
    .Y_o (sine_cordic),
    .X_o (X_out),
    .Z_o (Z_out),
    .strb_data_valid_o(strb_data_valid_cordic)
);

assign sine = sine_cordic + SIGNED_TO_UNSIGNED[BITWIDTH-1:0];

// ----------------------- WAVEFORM ----------------------- //
// is used to generate different waveforms (e.g. triangle, sawtooth, rectangle) with a given amplitude and rise/fall slope

wire [BITWIDTH-1:0] waveform;
wire strb_data_valid_waveform;

FG_WaveformGen #(.COUNTER_BITWIDTH (BITWIDTH_TIMER), .WAVEFORM_BITWIDTH(BITWIDTH)) Wave(
    .clk_i (clk_i),
    .rstn_i (rstn_i),
    .enable_i (enable_i),
    .strb_data_valid_i (clk_en),

    .counter_i (timerCounter), 
    .ON_counter_i (initPhase___ON_counter), 
    .k_rise_i (k_rise),
    .k_fall_i (k_fall),
    .amplitude_i (amplitude),

   .counterValue_i (counterValue),
   .out_o (waveform),
   .strb_data_valid_o(strb_data_valid_waveform) 
);

// ----------------------- DATA VALID STRB-GEN AND OUTPUT-REG ----------------------- //

reg outValid_STRB, outValid_STRB_reg;
reg [BITWIDTH-1:0] result, out_reg;

always @(*) begin
    if (CS_Mode) begin
        outValid_STRB = clk_en;
        result = amplitude;
    end else begin
        if(MS_Mode) begin
            outValid_STRB = strb_data_valid_cordic;
            result = sine;
        end else begin
            outValid_STRB = strb_data_valid_waveform;
            result = waveform;
        end
    end
end

always @ (posedge clk_i) begin
    if (!rstn_i) begin
        out_reg <= {BITWIDTH{1'b0}};
        outValid_STRB_reg <= 1'b0;
    end else if(outValid_STRB) begin
        out_reg <= result + offset;
        outValid_STRB_reg <= 1'b1;
    end else begin
        outValid_STRB_reg <= 1'b0;
    end
end

assign outValid_STRB_o = outValid_STRB_reg;
assign out_o = (enable_i)? out_reg : {BITWIDTH{1'b0}};

endmodule