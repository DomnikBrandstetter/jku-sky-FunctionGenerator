// CordicSlice_lean.v  (pure Verilog-2001)
// Area-lean tweaks:
//  - precompute variable shifts once (x_shr, y_shr)
//  - clamp shift to [0..BITWIDTH-1]
//  - fold add/sub sign selection into a single mux per axis
//  - optional saturation switch

module CordicSlice #(
    parameter integer N_INT              = 0,   // N_INT
    parameter integer N_FRAC             = -7,  // N_FRAC
    parameter integer CORDIC_MODE        = 0,   // 0 = ROTATION, 1 = VECTORING
    parameter integer COORDINATE_SYSTEM  = 0,   // 0 = CIRCULAR, 1 = LINEAR, 2 = HYPERBOLIC
    parameter integer SHIFT_BITWIDTH     = 4,   // keep minimal: ceil(log2(BITWIDTH))
    parameter integer USE_SATURATION     = 1    // 1: signed saturating add, 0: plain add
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
localparam integer MSB      = BITWIDTH - 1;

// ---------------- Direction selection ----------------
// ROTATION : dir_up = (Z_i >= 0)
// VECTORING: dir_up = (Y_i <  0)
wire dir_up;
generate
  if (CORDIC_MODE == 0) begin : gen_rot
    assign dir_up = (Z_i[MSB] == 1'b0);
  end else begin : gen_vec
    assign dir_up = (Y_i[MSB] == 1'b1);
  end
endgenerate

// ---------------- Shift amount clamp ----------------
// Limit dynamic shift to 0..BITWIDTH-1 to avoid building unreachable mux paths.
wire [SHIFT_BITWIDTH-1:0] sh =
  (shift_value_i[SHIFT_BITWIDTH-1:0] > (BITWIDTH-1)) ? (BITWIDTH-1) : shift_value_i;

// Precompute variable arithmetic shifts once.
wire signed [BITWIDTH-1:0] y_shr = (Y_i >>> sh);
wire signed [BITWIDTH-1:0] x_shr = (X_i >>> sh);

// ---------------- Registered state ----------------
reg signed [BITWIDTH-1:0] X_r, Y_r, Z_r;
assign X_o = X_r;
assign Y_o = Y_r;
assign Z_o = Z_r;

// ---------------- X update ----------------
// CIRCULAR:     X_next = X_i ± (Y_i >>> k)  (sign depends on dir_up)
// LINEAR:       X_next = X_i
// HYPERBOLIC:   X_next = X_i ± (Y_i >>> k)  (sign flipped vs circular)
wire signed [BITWIDTH-1:0] dx_circ     = dir_up ? -y_shr :  y_shr;
wire signed [BITWIDTH-1:0] dx_hyper    = dir_up ?  y_shr : -y_shr;
wire signed [BITWIDTH-1:0] dx_selected =
  (COORDINATE_SYSTEM == 2) ? dx_hyper :
  (COORDINATE_SYSTEM == 0) ? dx_circ  :
                              { {BITWIDTH{1'b0}} }; // linear => 0

always @(posedge clk_i) begin
  if (!rstn_i) begin
    X_r <= {BITWIDTH{1'b0}};
  end else begin
    if (COORDINATE_SYSTEM == 1) begin
      // LINEAR: pass-through (saves an adder)
      X_r <= X_i;
    end else if (USE_SATURATION != 0) begin
      X_r <= sat_add_s(X_i, dx_selected);
    end else begin
      X_r <= X_i + dx_selected;
    end
  end
end

// ---------------- Y update ----------------
// Y_next = Y_i ± (X_i >>> k) with sign from dir_up
wire signed [BITWIDTH-1:0] dy = dir_up ?  x_shr : -x_shr;

always @(posedge clk_i) begin
  if (!rstn_i) begin
    Y_r <= {BITWIDTH{1'b0}};
  end else begin
    if (USE_SATURATION != 0) Y_r <= sat_add_s(Y_i, dy);
    else                     Y_r <= Y_i + dy;
  end
end

// ---------------- Z update ----------------
// Z_next = Z_i ∓ current_rotation_angle_i (minus when dir_up)
wire signed [BITWIDTH-1:0] dz = dir_up ? -current_rotation_angle_i
                                       :  current_rotation_angle_i;

always @(posedge clk_i) begin
  if (!rstn_i) begin
    Z_r <= {BITWIDTH{1'b0}};
  end else begin
    if (USE_SATURATION != 0) Z_r <= sat_add_s(Z_i, dz);
    else                     Z_r <= Z_i + dz;
  end
end

// ---------------- Signed saturating add ----------------
// One adder + overflow detect (sign_a == sign_b) && (sign_sum != sign_a)
function [BITWIDTH-1:0] sat_add_s;
  input signed [BITWIDTH-1:0] a;
  input signed [BITWIDTH-1:0] b;
  reg   signed [BITWIDTH-1:0] s;
  reg sign_a, sign_b, sign_s, ov;
begin
  s      = a + b;
  sign_a = a[MSB];
  sign_b = b[MSB];
  sign_s = s[MSB];
  ov     = ((sign_a == sign_b) && (sign_s != sign_a));
  if (!ov) begin
    sat_add_s = s;
  end else if (sign_a) begin
    // negative overflow -> most negative
    sat_add_s = {1'b1, {BITWIDTH-1{1'b0}}};
  end else begin
    // positive overflow -> most positive
    sat_add_s = {1'b0, {BITWIDTH-1{1'b1}}};
  end
end
endfunction

endmodule
