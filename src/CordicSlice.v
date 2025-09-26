// CordicSlice.v  (pure Verilog-2001)

module CordicSlice #(
    parameter integer N_INT            = 0,   // N_INT
    parameter integer N_FRAC           = -7,  // N_FRACT
    parameter integer CORDIC_MODE      = 0,   // 0 = ROTATION, 1 = VECTORING
    parameter integer COORDINATE_SYSTEM= 0,   // 0 = CIRCULAR, 1 = LINEAR, 2 = HYPERBOLIC
    parameter integer SHIFT_BITWIDTH   = 8
) (
    input  wire                             clk_i,
    input  wire                             rstn_i,
    input  wire signed [N_INT - N_FRAC:0]   current_rotation_angle_i,
    input  wire        [SHIFT_BITWIDTH-1:0] shift_value_i,
    input  wire signed [N_INT - N_FRAC:0]   X_i,
    input  wire signed [N_INT - N_FRAC:0]   Y_i,
    input  wire signed [N_INT - N_FRAC:0]   Z_i,
    output wire signed [N_INT - N_FRAC:0]   X_o,
    output wire signed [N_INT - N_FRAC:0]   Y_o,
    output wire signed [N_INT - N_FRAC:0]   Z_o
);

localparam integer BITWIDTH = N_INT - N_FRAC + 1;

// Direction selection:
// ROTATION : dir_up = (Z_i >= 0)
// VECTORING: dir_up = (Y_i <  0)
wire dir_up;

generate
    if (CORDIC_MODE == 0) begin : gen_rot     // ROTATION
        assign dir_up = (Z_i[BITWIDTH-1] == 1'b0);
    end else begin : gen_vec                  // VECTORING
        assign dir_up = (Y_i[BITWIDTH-1] == 1'b1);
    end
endgenerate

// Registered state
reg signed [BITWIDTH-1:0] X_r, Y_r, Z_r;

// Output mapping
assign X_o = X_r;
assign Y_o = Y_r;
assign Z_o = Z_r;

// ------------------------------------ X ------------------------------------ //
always @ (posedge clk_i) begin
    if (!rstn_i) begin
        X_r <= {BITWIDTH{1'b0}};
    end else begin
        case (COORDINATE_SYSTEM)
            0: begin // CIRCULAR (m = +1)
                if (dir_up) X_r <= sat_add(X_i, - (Y_i >>> shift_value_i));
                else        X_r <= sat_add(X_i,   (Y_i >>> shift_value_i));
            end
            1: begin // LINEAR (m = 0)
                X_r <= X_i;
            end
            2: begin // HYPERBOLIC (m = -1)
                if (dir_up) X_r <= sat_add(X_i,   (Y_i >>> shift_value_i));
                else        X_r <= sat_add(X_i, - (Y_i >>> shift_value_i));
            end
            default: begin
                X_r <= X_i;
            end
        endcase
    end
end


// ------------------------------------ Y ------------------------------------ //
always @ (posedge clk_i) begin
    if (!rstn_i) begin
        Y_r <= {BITWIDTH{1'b0}};
    end else begin
        if (dir_up) Y_r <= sat_add(Y_i,   (X_i >>> shift_value_i));
        else        Y_r <= sat_add(Y_i, - (X_i >>> shift_value_i));
    end
end


// ------------------------------------ Z ------------------------------------ //
always @ (posedge clk_i) begin
    if (!rstn_i) begin
        Z_r <= {BITWIDTH{1'b0}};
    end else begin
        if (dir_up) Z_r <= sat_add(Z_i, - current_rotation_angle_i);
        else        Z_r <= sat_add(Z_i,   current_rotation_angle_i);
    end
end


// ----------------------- SATURATED ADDITION FUNCTION ----------------------- //
function [BITWIDTH-1:0] sat_add;
    input signed [BITWIDTH-1:0] a;
    input signed [BITWIDTH-1:0] b;
    reg   signed [BITWIDTH:0]   sum_ext; 
begin
    // ADD
    sum_ext = {a[BITWIDTH-1], a} + {b[BITWIDTH-1], b};

    // Signed overflow if the two top bits differ after extension
    if (sum_ext[BITWIDTH] ^ sum_ext[BITWIDTH-1]) begin
        if (sum_ext[BITWIDTH])
            sat_add = {1'b1, {BITWIDTH-1{1'b0}}}; // 1000...0 (MIN)
        else
            sat_add = {1'b0, {BITWIDTH-1{1'b1}}}; // 0111...1 (MAX)
    end else begin
        sat_add = sum_ext[BITWIDTH-1:0];
    end
end
endfunction

endmodule
