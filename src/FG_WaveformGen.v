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
        val <= {BITWIDTH-1{1'b0}};
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




// // Copyright 2024 Dominik Brandstetter
// //
// // Licensed under the Apache License, Version 2.0 (the "License");
// // you may not use this file except in compliance with the License.
// // You may obtain a copy of the License at
// //
// // http://www.apache.org/licenses/LICENSE−2.0
// //
// // Unless required by applicable law or agreed to in writing, software
// // distributed under the License is distributed on an "AS IS" BASIS,
// // WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// // See the License for the specific language governing permissions and
// // limitations under the License.

// module FG_WaveformGen #(parameter COUNTER_BITWIDTH = 32, WAVEFORM_BITWIDTH = 16)(
//     input wire clk_i,
//     input wire rstn_i,

//     input wire strb_data_valid_i,
//     input wire [COUNTER_BITWIDTH-1:0] counter_i,                       // Periode Counter Value (T)
//     input wire [COUNTER_BITWIDTH-1:0] ON_counter_i,                    // ON Counter Value (T)

//     input signed wire [WAVEFORM_BITWIDTH-1:0] k_rise_i, k_fall_i,             // Rise and Fall slope
//     input signed wire [WAVEFORM_BITWIDTH-1:0] amplitude_i,                    // Amplitude
    
//     input wire [COUNTER_BITWIDTH-1:0] counterValue_i, //counter register 
//     output signed wire [WAVEFORM_BITWIDTH-1:0] out_o 
//     output wire strb_data_valid_o,
// );

// localparam IDLE = 0, RISE = 1, ON = 2, FALL = 3;
// reg [1:0] state;

// reg signed [WAVEFORM_BITWIDTH-1:0] val;
// assign out_o = val;

// // ----------------------- FSM ----------------------- //

// always @(posedge clk_i) begin
//     if (!rstn_i) begin
//         state <= IDLE;

//     end else if(strb_data_valid_i) begin
//         case(state)
//         IDLE: begin
//             if(counterValue_i == 0) begin
//                 state <= RISE;
//             end
//         end 
//         RISE: begin
//             if(counterValue_i != ON_counter_i) begin
//                 if(val == amplitude_i) begin
//                     state <= ON;
//                 end else if(counterValue_i == counter_i) begin
//                     state <= IDLE;
//                 end
//             end else if(counterValue_i == ON_counter_i) begin
//                 state <= FALL;
//             end
//         end
//         ON: begin
//             if(counterValue_i != 0) begin
//                 if(counterValue_i == ON_counter_i) begin
//                     state <= FALL;
//                 end
//             end else if(counterValue_i == 0) begin
//                 state <= RISE;
//             end
//         end
//         FALL: begin
//             if(counterValue_i != 0) begin
//                 if(val == 0) begin
//                     state <= IDLE;
//                 end
//             end else if(counterValue_i == 0) begin
//                 state <= RISE;
//             end
//         end
//         default: state <= IDLE;
//         endcase
//     end
// end

// // ----------------------- VALUE UPDATE ----------------------- //
// wire signed [WAVEFORM_BITWIDTH-1:0] step, a, b;
// assign a = val;
// assign b = (state == RISE)? {{{(1){k_rise_i[WAVEFORM_BITWIDTH-1]}}}, k_rise_i} : - {{{(1){k_fall_i[WAVEFORM_BITWIDTH-1]}}}, k_fall_i};
// assign step = sat_add(a, b);

// always @(posedge clk_i) begin
//     if (!rstn_i) begin
//         val <= 0;
//     end else if(strb_data_valid_i) begin
//         case(state)
//             IDLE: begin
//                 val <= {1'b1, {BITWIDTH-1{1'b0}}};
//             end 
//             RISE: begin
//                 if(step <= amplitude_i && step >= 0) begin
//                     val <= step;
//                 end else begin
//                     val <= amplitude_i;
//                 end
//             end
//             ON: begin
//                 val <= amplitude_i;
//             end
//             FALL: begin
//                 if(step >= 0) begin
//                     val <= step;
//                 end else begin
//                     val <= 0;
//                 end
//             end
//         endcase
//     end
// end

// // ----------------------- DATA VALID STRB ----------------------- //

// reg strb_data_valid_reg;

// always @(posedge clk_i) begin
//     if (!rstn_i) begin
//         strb_data_valid_reg <= 1'b0;
//     end else if(strb_data_valid_i) begin
//         strb_data_valid_reg <= 1'b1;
//     end
// end

// assign strb_data_valid_o = strb_data_valid_reg;

// // ----------------------- SATURATED ADDITION FUNCTION ----------------------- //
// function [BITWIDTH-1:0] sat_add;
//     input signed [BITWIDTH-1:0] a;
//     input signed [BITWIDTH-1:0] b;
//     reg   signed [BITWIDTH:0]   sum_ext; 
// begin
//     // ADD
//     sum_ext = {a[BITWIDTH-1], a} + {b[BITWIDTH-1], b};

//     // Signed overflow if the two top bits differ after extension
//     if (sum_ext[BITWIDTH] ^ sum_ext[BITWIDTH-1]) begin
//         if (sum_ext[BITWIDTH])
//             sat_add = {1'b1, {BITWIDTH-1{1'b0}}}; // 1000...0 (MIN)
//         else
//             sat_add = {1'b0, {BITWIDTH-1{1'b1}}}; // 0111...1 (MAX)
//     end else begin
//         sat_add = sum_ext[BITWIDTH-1:0];
//     end
// end
// endfunction

// endmodule