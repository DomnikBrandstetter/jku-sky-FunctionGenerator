// Copyright 2024 Dominik Brandstetter
// Apache 2.0

module FG_WaveformGen #(
    parameter integer COUNTER_BITWIDTH  = 32,
    parameter integer WAVEFORM_BITWIDTH = 16
)(
    input  wire                          clk_i,
    input  wire                          rstn_i,

    input  wire                          strb_data_valid_i,
    input  wire [COUNTER_BITWIDTH-1:0]   counter_i,        // period T
    input  wire [COUNTER_BITWIDTH-1:0]   ON_counter_i,     // ON duration

    // Unsigned slopes and amplitude (magnitude-only)
    input  wire [WAVEFORM_BITWIDTH-1:0]  k_rise_i,         // rise step per tick
    input  wire [WAVEFORM_BITWIDTH-1:0]  k_fall_i,         // fall step per tick
    input  wire [WAVEFORM_BITWIDTH-1:0]  amplitude_i,      // max amplitude (unsigned)

    input  wire [COUNTER_BITWIDTH-1:0]   counterValue_i,   // timebase
    output wire [WAVEFORM_BITWIDTH-1:0]  out_o,
    output wire                          strb_data_valid_o
);

localparam integer W = WAVEFORM_BITWIDTH;

// ----------------------- FSM ----------------------- //
localparam [1:0] IDLE = 2'd0, RISE = 2'd1, ON = 2'd2, FALL = 2'd3;
reg [1:0] state;

reg [W-1:0] val;
assign out_o = val;

// Pre-computed steps (unsigned, saturated)
wire [W-1:0] step_up   = sat_add_u(val, k_rise_i); // clamp to MAX
wire [W-1:0] step_down = sat_sub_u(val, k_fall_i); // floor at 0

always @(posedge clk_i) begin
    if (!rstn_i) begin
        state <= IDLE;
    end else if (strb_data_valid_i) begin
        case (state)
            IDLE: begin
                // start a new cycle at counter wrap (example trigger)
                if (counterValue_i == {COUNTER_BITWIDTH{1'b0}})
                    state <= RISE;
            end
            RISE: begin
                if (counterValue_i == ON_counter_i)
                    state <= FALL;
                else if (val == amplitude_i)
                    state <= ON;
                else if (counterValue_i == counter_i)
                    state <= IDLE;
            end
            ON: begin
                if (counterValue_i == ON_counter_i)
                    state <= FALL;
                else if (counterValue_i == {COUNTER_BITWIDTH{1'b0}})
                    state <= RISE;
            end
            FALL: begin
                if (counterValue_i == {COUNTER_BITWIDTH{1'b0}})
                    state <= RISE;
                else if (val == {W{1'b0}})
                    state <= IDLE;
            end
            default: state <= IDLE;
        endcase
    end
end

// ----------------------- VALUE UPDATE ----------------------- //
always @(posedge clk_i) begin
    if (!rstn_i) begin
        val <= {W{1'b0}};
    end else if (strb_data_valid_i) begin
        case (state)
            IDLE: val <= {W{1'b0}};
            RISE: val <= (step_up <= amplitude_i) ? step_up : amplitude_i;
            ON  : val <= amplitude_i;
            FALL: val <= step_down; // already floored at 0
            default: val <= {W{1'b0}};
        endcase
    end
end

// ----------------------- DATA VALID STROBE ----------------------- //
// Simple 1-cycle registered pass-through of input strobe
reg strb_data_valid_reg;
always @(posedge clk_i) begin
    if (!rstn_i) strb_data_valid_reg <= 1'b0;
    else         strb_data_valid_reg <= strb_data_valid_i;
end
assign strb_data_valid_o = strb_data_valid_reg;

// ----------------------- UNSIGNED SATURATION FUNCS ----------------------- //
// Unsigned saturating add: clamp to MAX on overflow
function [W-1:0] sat_add_u;
    input [W-1:0] a;
    input [W-1:0] b;
    reg   [W:0]   sum; // one extra carry bit
begin
    sum = {1'b0, a} + {1'b0, b};
    if (sum[W]) sat_add_u = {W{1'b1}};      // overflow -> MAX
    else        sat_add_u = sum[W-1:0];
end
endfunction

// Unsigned saturating subtract: floor at 0 on underflow
function [W-1:0] sat_sub_u;
    input [W-1:0] a;
    input [W-1:0] b;
begin
    if (a >= b) sat_sub_u = a - b;
    else        sat_sub_u = {W{1'b0}};
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