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

module FG_Limiter #(parameter BITWIDTH = 16, DATA_COUNT = 3)(
    input wire outputEnable_i,
    input wire [$clog2(DATA_COUNT)-1:0] select_i,

    input wire signed [BITWIDTH-1:0] offset_i,    
    input wire [(DATA_COUNT*(BITWIDTH+1))-1:0] data_i,
    
    output wire signed [BITWIDTH-1:0] out_o 
);

//Maximum and minimum values output
localparam signed MAX_VALUE =  (2 ** (BITWIDTH-1)) - 1;  
localparam signed MIN_VALUE = -(2 ** (BITWIDTH-1)); 
 
wire signed [BITWIDTH:0] result; 
wire signed [BITWIDTH-1:0] limited_result;

assign result = data_i[(select_i)*(BITWIDTH+1) +: BITWIDTH+1] + {{{(1){offset_i[BITWIDTH-1]}}}, offset_i};

// Limit MAX/MIN result values
assign limited_result  = (result >= MAX_VALUE) ? MAX_VALUE[BITWIDTH-1:0] :
                         (result <= MIN_VALUE) ? MIN_VALUE[BITWIDTH-1:0] :
                         result[BITWIDTH-1:0];

// Enable Out
assign out_o = (outputEnable_i) ? limited_result : {(BITWIDTH){1'b0}};

endmodule