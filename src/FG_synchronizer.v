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

module FG_Synchronizer #(parameter STAGES = 2)(
    input wire clk_i,  
    input wire rstn_i,        
    input wire async_i,      
    output wire sync_o 
);
    reg [STAGES-1:0] sync_regs;
    integer i;
    
    always @(posedge clk_i) begin

        if (!rstn_i) begin
            sync_regs[0] <= 1'b0;
        end else begin
            sync_regs[0] <= async_i; 
        end
    end

    always @(posedge clk_i) begin

        for (i = 1; i < STAGES; i = i + 1) begin
            sync_regs[i] <= sync_regs[i-1];
        end
    end

    assign sync_o = sync_regs[STAGES-1]; 

endmodule