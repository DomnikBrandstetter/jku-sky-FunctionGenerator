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

module FG_WaveformGen #(
    parameter integer COUNTER_BITWIDTH  = 32,
    parameter integer WAVEFORM_BITWIDTH = 16
)(
    input  wire                          clk_i,
    input  wire                          rstn_i,

    input  wire                          strb_data_valid_i,
    input  wire [COUNTER_BITWIDTH-1:0]   counter_i,        // period T
    input  wire [COUNTER_BITWIDTH-1:0]   ON_counter_i,     // ON duration

    input  wire [WAVEFORM_BITWIDTH-1:0]  k_rise_i,         // rise step per tick
    input  wire [WAVEFORM_BITWIDTH-1:0]  k_fall_i,         // fall step per tick
    input  wire [WAVEFORM_BITWIDTH-1:0]  amplitude_i,      

    input  wire [COUNTER_BITWIDTH-1:0]   counterValue_i,   // timebase
    output wire [WAVEFORM_BITWIDTH-1:0]  out_o,
    output wire                          strb_data_valid_o
);

localparam integer BITWIDTH = WAVEFORM_BITWIDTH;

// ----------------------- FSM ----------------------- //
localparam [1:0] IDLE = 2'd0, RISE = 2'd1, ON = 2'd2, FALL = 2'd3;
reg [1:0] state;

reg [BITWIDTH-1:0] val;
assign out_o = val;

always @(posedge clk_i) begin
    if (!rstn_i) begin
        state <= IDLE;

    end else if(strb_data_valid_i) begin
        case(state)
        IDLE: begin
            if(counterValue_i == 0) begin
                state <= RISE;
            end
        end 
        RISE: begin
            if(counterValue_i == ON_counter_i) begin
                state <= FALL;
            end else if(val == amplitude_i) begin
                state <= ON;
            end else if(counterValue_i == counter_i) begin
                state <= IDLE;
            end
        end
        ON: begin
            if(counterValue_i == 0) begin
                state <= RISE;
            end else if(counterValue_i == ON_counter_i) begin
                state <= FALL;
            end
        end
        FALL: begin
            if(counterValue_i == 0) begin
                state <= RISE;
            end else if (val == 0) begin
                state <= IDLE;
            end
        end
        default: state <= IDLE;
        endcase
    end
end

// ----------------------- VALUE UPDATE ----------------------- //
wire [WAVEFORM_BITWIDTH-1:0] step;
assign step = sat_add_cap(val, ((state == RISE)? k_rise_i : k_fall_i), amplitude_i, ((state == RISE)? 1'b0 : 1'b1)); 

always @(posedge clk_i) begin
    if (!rstn_i) begin
        val <= {BITWIDTH{1'b0}};
    end else if(strb_data_valid_i) begin
        val <= (state == IDLE) ? {BITWIDTH{1'b0}} : step;
    end
end

// ----------------------- DATA VALID STROBE ----------------------- //
reg strb_data_valid_reg;
always @(posedge clk_i) begin
    if (!rstn_i) strb_data_valid_reg <= 1'b0;
    else         strb_data_valid_reg <= strb_data_valid_i;
end
assign strb_data_valid_o = strb_data_valid_reg;

// ----------------------- UNSIGNED SATURATION ADD FUNCTION ----------------------- //
function [BITWIDTH-1:0] sat_add_cap;
    input [BITWIDTH-1:0] a;
    input [BITWIDTH-1:0] b;
    input [BITWIDTH-1:0] upper;
    input                is_sub;             // 0 = ADD, 1 = SUB

    reg  [BITWIDTH-1:0] b_eff;               // b after conditional invert
    reg  [BITWIDTH:0]   s;                   // adder with carry-out (single adder)
    reg  [BITWIDTH:0]   cmp;                 // (sum - upper) as add(~upper) + 1
begin
    // Single adder arithmetic: a + (b ^ is_sub) + is_sub
    b_eff = b ^ {BITWIDTH{is_sub}};
    s     = {1'b0, a} + {1'b0, b_eff} + {{BITWIDTH{1'b0}}, is_sub};

    if (!is_sub) begin
        // ADD: if carry-out -> overflow -> clamp to upper
        if (s[BITWIDTH]) begin
            sat_add_cap = upper;
        end else begin
            // Check if sum >= upper using (sum - upper); carry==1 means no borrow
            cmp = {1'b0, s[BITWIDTH-1:0]} + {1'b0, ~upper} + {{BITWIDTH{1'b0}}, 1'b1};
            sat_add_cap = cmp[BITWIDTH] ? upper : s[BITWIDTH-1:0];
        end
    end else begin
        sat_add_cap = s[BITWIDTH] ? s[BITWIDTH-1:0] : {BITWIDTH{1'b0}};
    end
end
endfunction

endmodule