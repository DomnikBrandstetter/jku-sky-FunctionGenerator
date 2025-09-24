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

`include "FG_Timer.v"
`include "FG_Cordic.v"
`include "FG_WaveformGen.v"
`include "FG_Limiter.v"

module FG_FunctionGenerator #(parameter BITWIDTH = 8, BITWIDTH_TIMER = 10, CONFIG_REG_BITWIDTH = 64, OUT_STROBE_DELAY = 0)(
    input wire clk_i,
    input wire rstn_i,
    input wire outputEnable_i,

    input wire [CONFIG_REG_BITWIDTH-1:0] CR_bus_i,
        // 63      -> constant signal  - BIT (0 = False    | 1 = True) 
        // 62      -> modulated signal - BIT (0 = Waveform | 1 = Sine) 
        // 61      -> Radix            - BIT (0 = Signed   | 1 = Unsigned)
        // 60 - 52 -> Prescaler 
        // 51 - 42 -> Counter Value
        // 41 - 32 -> Initial phase for sine, ON-Counter for waveform generation
        // 31 - 24 -> Rising slope for Waveform generation
        // 23 - 16 -> Falling slope for Waveform generation  
        // 15 - 8  -> Amplitude
        //  7 - 0  -> Offset 

    output wire signed [BITWIDTH-1:0] out_o,
    output wire outValid_STRB_o
);

// ----------------------- CONSTANTS AND CONFIGURATION REGISTERS ----------------------- //

// Config Reg 1
localparam CS_MODE_POS = CONFIG_REG_BITWIDTH;
localparam MS_MODE_POS = CONFIG_REG_BITWIDTH-1;
localparam RADIX_POS   = MS_MODE_POS-1;
localparam TIMER_PRESCALER_BITWIDTH = 9;
localparam TIMER_PRESCALER_POS = 52;

wire CS_Mode, MS_Mode, Radix;
assign CS_Mode = CR_bus_i[CS_MODE_POS-1];
assign MS_Mode = CR_bus_i[MS_MODE_POS-1];
assign Radix   = CR_bus_i[RADIX_POS-1];

wire [TIMER_PRESCALER_BITWIDTH-1:0] timerPrescaler;
assign timerPrescaler = CR_bus_i[TIMER_PRESCALER_POS+TIMER_PRESCALER_BITWIDTH-1:TIMER_PRESCALER_POS];

// Config Reg 2
localparam TIMER_COUNTER_BITWIDTH = BITWIDTH_TIMER;
localparam TIMER_COUNTER_POS = 42;

wire [TIMER_COUNTER_BITWIDTH-1:0] timerCounter;
assign timerCounter = CR_bus_i[TIMER_COUNTER_POS+TIMER_COUNTER_BITWIDTH-1:TIMER_COUNTER_POS];

// Config Reg 3 (initial phase for sine, ON counter for waveform generation)
localparam INIT_PHASE___ON_COUNTER_BITWIDTH = BITWIDTH_TIMER;
localparam INIT_PHASE___ON_COUNTER_POS = 32;

wire [INIT_PHASE___ON_COUNTER_BITWIDTH-1:0] initPhase___ON_counter;
assign initPhase___ON_counter = CR_bus_i[INIT_PHASE___ON_COUNTER_POS+INIT_PHASE___ON_COUNTER_BITWIDTH-1:INIT_PHASE___ON_COUNTER_POS];

// Config Reg 4
localparam SLOPE_BITWIDTH = BITWIDTH;
localparam RISE_SLOPE_POS = 24;
localparam FALL_SLOPE_POS = 16;

wire [SLOPE_BITWIDTH-1:0] k_rise, k_fall;
assign k_rise = CR_bus_i[RISE_SLOPE_POS+SLOPE_BITWIDTH-1:RISE_SLOPE_POS];
assign k_fall = CR_bus_i[FALL_SLOPE_POS+SLOPE_BITWIDTH-1:FALL_SLOPE_POS];

// Config Reg 5
localparam AMPLITUDE_BITWIDTH = BITWIDTH;
localparam AMPLITUDE_POS = 8;
localparam OFFSET_BITWIDTH = BITWIDTH;
localparam OFFSET_POS = 0;

wire [AMPLITUDE_BITWIDTH-1:0] amplitude;
assign amplitude = CR_bus_i[AMPLITUDE_POS+AMPLITUDE_BITWIDTH-1:AMPLITUDE_POS];

wire signed [OFFSET_BITWIDTH-1:0] offset;
assign offset = CR_bus_i[OFFSET_POS+OFFSET_BITWIDTH-1:OFFSET_POS];

wire rst_n;
assign rst_n = rstn_i;
// ----------------------- TIMER ----------------------- //

// is used to perform timer functions -> time base

wire [TIMER_COUNTER_BITWIDTH-1:0] counterValue;
wire clk_en, timerConfigChanged, rstn__configRST;

FG_Timer #(.COUNTER_BITWIDTH (TIMER_COUNTER_BITWIDTH), .PSC_BITWIDTH (TIMER_PRESCALER_BITWIDTH)) Timer (
    .clk_i (clk_i),
    .rstn_i (rst_n),
 
    .enable_i (outputEnable_i), //(!CS_Mode),
    .timerMode_i (MS_Mode),
    .prescaler_i (timerPrescaler),
    .counter_i (timerCounter),
    .preload_i (initPhase___ON_counter),
    
    .CR_o (counterValue),
    .timerConfigChanged_o (timerConfigChanged), 
    .clk_en_o (clk_en)   
);

assign rstn__configRST = (rst_n && !timerConfigChanged)? 1'b1 : 1'b0;

// ----------------------- DATA VALID STRB-GEN ----------------------- //
reg outValid_STRB_shiftreg [OUT_STROBE_DELAY:0];

genvar i;

always @ (posedge clk_i)
begin
    if (!rst_n) begin
        outValid_STRB_shiftreg[0] <= 1'b0;
    end else begin
        outValid_STRB_shiftreg[0] <= clk_en;
    end 
end

generate
    for (i = 0; i < OUT_STROBE_DELAY; i = i + 1)
    begin: shiftreg
        always @ (posedge clk_i)
        begin
            if (!rst_n) begin
                outValid_STRB_shiftreg[i+1] <= 1'b0;
            end else begin
                outValid_STRB_shiftreg[i+1] <= outValid_STRB_shiftreg[i];
            end
        end
    end
endgenerate

assign outValid_STRB_o = outValid_STRB_shiftreg[OUT_STROBE_DELAY]; 

// ----------------------- CORDIC ----------------------- //

localparam [BITWIDTH-1:0] Y_INITIAL = 0;
localparam BITWIDTH_CORDIC_TAN = TIMER_COUNTER_BITWIDTH;
wire signed [BITWIDTH:0] sine, cosine;

// FG_Cordic #(.BITWIDTH (BITWIDTH), .BITWIDTH_PHASE (BITWIDTH_CORDIC_TAN)) Cordic(
//     .clk_i (clk_i),
//     .rstn_i (rstn__configRST),
//     .clk_en_i (clk_en),
   
//     // Interface
//     .phase_i (counterValue),
//     .x_initial_i  (amplitude), 
//     .y_initial_i (Y_INITIAL),
    
//     .cosine_o (cosine),
//     .sine_o  (sine)
// );

assign sine = 0;
assign cosine = 0;

// ----------------------- WAVEFORM ----------------------- //

wire signed [BITWIDTH:0] waveform;

// FG_WaveformGen #(.COUNTER_BITWIDTH (TIMER_COUNTER_BITWIDTH), .WAVEFORM_BITWIDTH(BITWIDTH)) Wave(
//     .clk_i (clk_i),
//     .rstn_i (rstn__configRST),
//     .clk_en_i (clk_en),

//     .counter_i (timerCounter), 
//     .ON_counter_i (initPhase___ON_counter), 
//     .k_rise_i (k_rise),
//     .k_fall_i (k_fall),
//     .amplitude_i (amplitude),

//    .CR_i (counterValue),
//    .out_o (waveform) 
// );

assign waveform = 0;

// ----------------------- LIMITER ----------------------- //

localparam DATA_COUNT = 3;
localparam SIGNED_TO_UNSIGNED = 2 ** (BITWIDTH-1);

wire [(DATA_COUNT*(BITWIDTH+1))-1:0] data;
wire [BITWIDTH-1:0] out, out_signed, out_unsigned;

assign data[(0)*(BITWIDTH+1) +: BITWIDTH+1] = waveform;
assign data[(1)*(BITWIDTH+1) +: BITWIDTH+1] = sine;
assign data[(2)*(BITWIDTH+1) +: BITWIDTH+1] = {{{BITWIDTH-(BITWIDTH-1){amplitude  [BITWIDTH-1]}}}, amplitude};

FG_Limiter #(.BITWIDTH (BITWIDTH), .DATA_COUNT(DATA_COUNT)) Limiter(

    .outputEnable_i (outputEnable_i),
    .select_i ({CS_Mode, MS_Mode}),

    .offset_i (offset), 
    .data_i (data),     
    
    .out_o (out)
);

assign out_signed = out;
assign out_unsigned = out + SIGNED_TO_UNSIGNED[BITWIDTH-1:0];

assign out_o = Radix? out_unsigned : out_signed;

endmodule