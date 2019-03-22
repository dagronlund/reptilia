`include "fpu.svh"
`include "fpu_utils.svh"
`include "fpu_ultrascale_native.svh"
`include "fpu_operations.svh"
`include "fpu_reference.svh"

module FPU(
  input  logic [31:0] a, b,
  input  logic [2:0] op,
  input  logic [1:0] mode,
  output logic [31:0] y);

  import fpu::*;
  import fpu_reference::*;

  fpu_float_fields_t fpu_a, fpu_b;

  always_comb begin
    case(op)
      3'd0: begin
            fpu_a = fpu_encode_float(a);
            fpu_b = fpu_encode_float(b);
            y = fpu_reference_float_add(fpu_a, fpu_b, mode);
            end
      3'd1: begin
            fpu_a = fpu_encode_float(a);
            fpu_b = fpu_encode_float({~b[31], b[30:0]});
            y = fpu_reference_float_add(fpu_a, fpu_b, mode);
            end
      3'd2: begin
            fpu_a = fpu_encode_float(a);
            fpu_b = fpu_encode_float(b);
            y = fpu_reference_float_mult(fpu_a, fpu_b, mode);
            end
      3'd3: begin
            fpu_a = fpu_encode_float(a);
            fpu_b = fpu_encode_float(b);
            y = fpu_reference_float_div(fpu_a, fpu_b, mode);
            end
      3'd4: begin
            fpu_a = fpu_encode_float(a);
            fpu_b = fpu_encode_float(b);
            y = fpu_reference_float_sqrt(fpu_a, mode);
            end
    endcase
  end

endmodule

module fpu_test;

  import fpu::*;
  logic [31:0] a, b, i, y, result, score;
  logic [2:0] op;
  fpu_round_mode_t mode;

  logic r;

  FPU fp(.*);

  parameter NUM_VECTORS=500;
  logic [104:0] vectors [NUM_VECTORS-1:0];
  logic [104:0] args;

  initial begin
    $readmemh("random_floats.vm", vectors);
    score = 0;
    for(i=0;i<NUM_VECTORS;i++) begin
      args = vectors[i];
      a = args[95:64];
      b = args[63:32];
      op = args[98:96];
      mode = args[103:100];
      result = args[31:0];
      #100
      r = (result==y);
      if(!r) begin
        $display($time,, "%h %d %h = %h (%h) Mode: %s\n", a, op, b, y, result, mode);
        $display("result: %h %h %h", y[31], y[30:23], y[22:0]);
        $display("answer: %h %h %h", result[31], result[30:23], result[22:0]);
      end else
        score += 1;
    end
    $display("\n\nSCORE: %d/%d", score, NUM_VECTORS);
    $finish;
  end

endmodule