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

module FG_WaveformGen #(parameter COUNTER_BITWIDTH = 32, WAVEFORM_BITWIDTH = 16)(
    input wire clk_i,
    input wire clk_en_i,
    input wire rstn_i,

    input wire [COUNTER_BITWIDTH-1:0] counter_i,                       // Periode Counter Value (T)
    input wire [COUNTER_BITWIDTH-1:0] ON_counter_i,                    // ON Counter Value (T)

    input wire [WAVEFORM_BITWIDTH-1:0] k_rise_i, k_fall_i,             // Rise and Fall slope
    input wire [WAVEFORM_BITWIDTH-1:0] amplitude_i,                    // Amplitude
    
    input wire [COUNTER_BITWIDTH-1:0] CR_i, //counter register 
    output wire [WAVEFORM_BITWIDTH:0] out_o 
);

localparam IDLE = 0, RISE = 1, ON = 2, FALL = 3;
reg [1:0] state;

reg [COUNTER_BITWIDTH-1:0] ON_counter, counter;
reg [WAVEFORM_BITWIDTH-1:0] k_rise, k_fall;
reg signed [WAVEFORM_BITWIDTH:0] amplitude, val;

assign out_o = val;

// ----------------------- LOAD REGISTERS ----------------------- //

always @(posedge clk_i) begin
    if (!rstn_i) begin
        counter <= 0;
        ON_counter <= 0;
        k_rise <= 0;
        k_fall <= 0;
        amplitude <= 0;
    end else if(clk_en_i) begin
        if(CR_i == 0) begin
            counter <= counter_i;
            ON_counter <= ON_counter_i;
            k_rise <= k_rise_i;
            k_fall <= k_fall_i;
            amplitude <= {{{WAVEFORM_BITWIDTH-(WAVEFORM_BITWIDTH-1){1'b0}}}, amplitude_i};
        end
    end 
end

// ----------------------- FSM ----------------------- //

always @(posedge clk_i) begin
    if (!rstn_i) begin
        state <= IDLE;

    end else if(clk_en_i) begin
        case(state)
        IDLE: begin
            if(CR_i == 0) begin
                state <= RISE;
            end
        end 
        RISE: begin
            if(CR_i != ON_counter) begin
                if(val == amplitude) begin
                    state <= ON;
                end else if(CR_i == counter) begin
                    state <= IDLE;
                end
            end else if(CR_i == ON_counter) begin
                state <= FALL;
            end
        end
        ON: begin
            if(CR_i != 0) begin
                if(CR_i == ON_counter) begin
                    state <= FALL;
                end
            end else if(CR_i == 0) begin
                state <= RISE;
            end
        end
        FALL: begin
            if(CR_i != 0) begin
                if(val == 0) begin
                    state <= IDLE;
                end
            end else if(CR_i == 0) begin
                state <= RISE;
            end
        end
        default: state <= IDLE;
        endcase
    end
end

// Assumes: clk_i, rstn_i, clk_en_i, state, IDLE/RISE/ON/FALL,
//          val, amplitude, k_rise, k_fall are declared elsewhere.

// used to force the use of only one adder
//wire signed [WAVEFORM_BITWIDTH:0] delta_step;
//assign delta_step = val + 1; //((state == RISE)? {{{(1){k_rise[WAVEFORM_BITWIDTH-1]}}}, k_rise} : -{{{(1){k_fall[WAVEFORM_BITWIDTH-1]}}}, k_fall});

//assign delta_step = val + ((state == RISE)? {{{(1){k_rise[WAVEFORM_BITWIDTH-1]}}}, k_rise} : -{{{(1){k_fall[WAVEFORM_BITWIDTH-1]}}}, k_fall});

always @(posedge clk_i) begin
    if (!rstn_i) begin
        val <= 0;
    end else if(clk_en_i) begin
        if(state == IDLE) begin
            val <= 0; 
        end else if(state == RISE) begin
            if((val + {{{(1){k_rise[WAVEFORM_BITWIDTH-1]}}}, k_rise}) <= amplitude && (val + {{{(1){k_rise[WAVEFORM_BITWIDTH-1]}}}, k_rise}) >= 0) begin
                val <= val + {{{(1){k_rise[WAVEFORM_BITWIDTH-1]}}}, k_rise};
            end else begin
                val <= amplitude;
            end
            //val <= val + {{{(1){k_rise[WAVEFORM_BITWIDTH-1]}}}, k_rise};
        end else if(state == ON) begin
            val <= amplitude;
        end else if(state == FALL) begin
            if((val - {{{(1){k_fall[WAVEFORM_BITWIDTH-1]}}}, k_fall}) >= 0) begin
                val <= val - {{{(1){k_fall[WAVEFORM_BITWIDTH-1]}}}, k_fall};
            end else begin
                val <= 0;
            end
            //val <= val - {{{(1){k_fall[WAVEFORM_BITWIDTH-1]}}}, k_fall};
        end
    end
end
// always @(posedge clk_i) begin
//     if (!rstn_i) begin
//         val <= 0;
//     end else if(clk_en_i) begin
//         case(state)
//             IDLE: begin
//                 val <= 0; 
//             end 
//             RISE: begin
//                 if((val + {{{(1){k_rise[WAVEFORM_BITWIDTH-1]}}}, k_rise}) <= amplitude && (val + {{{(1){k_rise[WAVEFORM_BITWIDTH-1]}}}, k_rise}) >= 0) begin
//                     val <= val + {{{(1){k_rise[WAVEFORM_BITWIDTH-1]}}}, k_rise};
//                 end else begin
//                     val <= amplitude;
//                 end
//             end
//             ON: begin
//                 val <= amplitude;
//             end
//             FALL: begin
//                 if((val - {{{(1){k_fall[WAVEFORM_BITWIDTH-1]}}}, k_fall}) >= 0) begin
//                     val <= val - {{{(1){k_fall[WAVEFORM_BITWIDTH-1]}}}, k_fall};
//                 end else begin
//                     val <= 0;
//                 end
//             end
//             default: state <= IDLE;
//         endcase
//     end
// end

// always @(posedge clk_i) begin
//     if (!rstn_i) begin
//         val <= 0;
//     end else if(clk_en_i) begin
//         case(state)
//             IDLE: begin
//                 val <= 0; 
//             end 
//             RISE: begin
//                 if(delta_step <= amplitude && delta_step >= 0) begin
//                     val <= delta_step;
//                 end else begin
//                     val <= amplitude;
//                 end
//             end
//             ON: begin
//                 val <= amplitude;
//             end
//             FALL: begin
//                 if(delta_step >= 0) begin
//                     val <= delta_step;
//                 end else begin
//                     val <= 0;
//                 end
//             end
//             default: state <= IDLE;
//         endcase
//     end
// end

endmodule


