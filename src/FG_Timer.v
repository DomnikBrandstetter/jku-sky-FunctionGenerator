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

module FG_Timer #(parameter COUNTER_BITWIDTH = 32, PSC_BITWIDTH = 16)(
    input wire clk_i,
    input wire rstn_i,

    input wire enable_i,                         // 0 = Disbale / 1 = Enable 
    input wire timerMode_i,                      // Timer Mode 1 = Overflow / 0 = Compare 
    input wire [PSC_BITWIDTH-1:0] prescaler_i,   // Prescaler 
    input wire [COUNTER_BITWIDTH-1:0] counter_i, // counter value
    input wire [COUNTER_BITWIDTH-1:0] preload_i, // initial phase of overflow mode
    
    output wire [COUNTER_BITWIDTH-1:0] CR_o,     //counter register 
    output wire timerConfigChanged_o,
    output wire clk_en_o
);

wire clk_en;

// ----------------------- PRESCALER ----------------------- //

localparam MIN_PSC = 1; //minimal prescaler is 1 -> base clock / 2

reg [PSC_BITWIDTH-1:0] PSC, PSC_Value;
assign clk_en = (PSC_Value == PSC)? 1'b1 : 1'b0;

//set up prescaler
always @(posedge clk_i) begin
    if (!rstn_i) begin
        PSC <= 0;
    end else if (PSC_Value == 0 && prescaler_i > MIN_PSC[PSC_BITWIDTH-1:0]) begin
        PSC <= prescaler_i;
    end else if (PSC_Value == 0 && prescaler_i <= MIN_PSC[PSC_BITWIDTH-1:0]) begin
        PSC <= MIN_PSC[PSC_BITWIDTH-1:0];
    end
end

// CLK-Divider
always @(posedge clk_i) begin

    if (!rstn_i) begin
        PSC_Value <= 0;
    end else if (PSC_Value == PSC) begin
        PSC_Value <= 0;
    end else begin
        PSC_Value <= PSC_Value + 1;
    end
end

// ----------------------- TIMER ----------------------- //

localparam PRELOAD_BITWIDTH = COUNTER_BITWIDTH;

reg [COUNTER_BITWIDTH-1:0] counter, counterValue; 
reg [PRELOAD_BITWIDTH-1:0] preload;
reg timerMode, enable;

reg state;
localparam INIT = 1'b0;
localparam RUN  = 1'b1;

wire configChanged;
wire [COUNTER_BITWIDTH-1:0] counterPreload; 

assign configChanged = (enable != enable_i || timerMode != timerMode_i || 
                            counter != counter_i || (timerMode == 1 && preload != preload_i))? 1'b1 : 1'b0;

assign CR_o = counterValue;
assign clk_en_o = (clk_en && state == RUN)? 1'b1 : 1'b0;
assign timerConfigChanged_o = (configChanged && state == INIT)? 1'b1 : 1'b0;

assign counterPreload = (COUNTER_BITWIDTH > PRELOAD_BITWIDTH)? {{(COUNTER_BITWIDTH-PRELOAD_BITWIDTH){preload[PRELOAD_BITWIDTH-1]}}, preload} : 
                            preload[(PRELOAD_BITWIDTH-COUNTER_BITWIDTH)+COUNTER_BITWIDTH-1:(PRELOAD_BITWIDTH-COUNTER_BITWIDTH)];

// configuration state machine
always @(posedge clk_i) begin
    if (!rstn_i) begin
        state <= INIT;

    end else if(clk_en) begin
        case(state)
        INIT: begin
            if(!configChanged && enable) begin
                state <= RUN;
            end
        end 
        RUN: begin
            if(configChanged || !enable) begin
                state <= INIT;
            end
        end
        default: state <= INIT;
        endcase
    end
end

//set up timer configuration
always @(posedge clk_i) begin
    if (!rstn_i) begin
        enable <= 0;
        timerMode <= 0;
        counter <= 0;
        preload <= 0;
    end else if (clk_en && state == INIT) begin
        enable <= enable_i;
        timerMode <= timerMode_i;
        counter <= counter_i;
        preload <= preload_i;
    end 
end
// timer
always @(posedge clk_i) begin

    if (!rstn_i) begin
        counterValue <= 0;
    
    end else if (clk_en && state == INIT) begin
        if(timerMode_i) begin  // Timer Mode Overflow
            counterValue <= counterPreload;
        end else begin         // Timer Mode Compare
            counterValue <= 0; 
        end
    
    end else if (clk_en && state == RUN) begin

        // Timer Mode Overflow
        if(timerMode) begin 
            counterValue <= counterValue + counter;
        
        // Timer Mode Compare
        end else if (!timerMode && counterValue != counter) begin
            counterValue <= counterValue + 1;
        end else if (!timerMode && counterValue == counter) begin
            counterValue <= 0;
        end 
    end
end 

endmodule