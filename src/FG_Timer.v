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


module FG_Timer #(parameter COUNTER_BITWIDTH = 10, PSC_BITWIDTH = 9)(
    input wire clk_i,
    input wire rstn_i,

    input wire enable_i,                             // 0 = Disbale | 1 = Enable 
    input wire timerMode_i,                          // 0 = Compare | 1 = Timer Mode
    input wire [PSC_BITWIDTH-1:0] prescaler_i,       // Prescaler 
    input wire [COUNTER_BITWIDTH-1:0] counter_i,     // Counter value
    input wire [COUNTER_BITWIDTH-1:0] preload_i,     // Initial phase of overflow mode
    
    output wire [COUNTER_BITWIDTH-1:0] counterVal_o, // Counter register 
    output wire clk_en_o
);

wire clk_en;

reg [PSC_BITWIDTH-1:0] PSC_Value;
reg [COUNTER_BITWIDTH-1:0] counterValue; 

// ----------------------- PRESCALER ----------------------- //

// CLK-Divider
always @(posedge clk_i) begin

    if (!rstn_i) begin
        PSC_Value <= 0;
    end else if (PSC_Value == prescaler_i) begin
        PSC_Value <= 0;
    end else begin
        PSC_Value <= PSC_Value + 1;
    end
end

assign clk_en = (PSC_Value == prescaler_i)? 1'b1 : 1'b0;

// -------------------------- TIMER ------------------------- //

// timer
always @(posedge clk_i) begin

    if (!rstn_i) begin
        counterValue <= 0;
    
    end else if (!enable_i) begin
        if(timerMode_i) begin  // Timer Mode Overflow
            counterValue <= preload_i;
        end else begin         // Timer Mode Compare
            counterValue <= 0; 
        end
    
    end else if (clk_en && enable_i) begin

        // Timer Mode Overflow
        if(timerMode_i) begin 
            counterValue <= counterValue + counter_i;
        
        // Timer Mode Compare
        end else if (!timerMode_i && counterValue != counter_i) begin
            counterValue <= counterValue + 1;
        end else if (!timerMode_i && counterValue == counter_i) begin
            counterValue <= 0;
        end 
    end
end 

assign counterVal_o = counterValue;
assign clk_en_o = (clk_en)? 1'b1 : 1'b0;

endmodule