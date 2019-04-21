`include "fpu.svh"
`include "fpu_utils.svh"
`include "fpu_ultrascale_native.svh"
`include "fpu_operations.svh"
`include "fpu_divide.svh"
`include "fpu_mult.svh"
`include "fpu_add.svh"
`include "fpu_sqrt.svh"

import fpu::*;
import fpu_operations::*;
import fpu_divide::*;
import fpu_mult::*;
import fpu_add::*;
import fpu_sqrt::*;

module FPU_sqrt(
    input  fpu_float_fields_t a,
    input  fpu_round_mode_t mode,
    input  logic clk, rst, valid,
    output logic [31:0] y,
    output logic ready);
    

    fpu_float_conditions_t conditions_A, conditions_B;
    fpu_sqrt_result_t exp_result, next_exp_result, op_result, next_op_result;
    fpu_result_t next_result, result;
    logic [31:0] i, next_i;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            exp_result <= '{default: 'd0};
            op_result <= '{default: 'd0};
            result <= '{default: 'd0};
            i <= 'd0;
        end else if (next_i!=0) begin
            exp_result <= next_op_result;
            op_result <= '{default: 'b0};
            result <= '{default: 'b0};
            i <= next_i;
        end else begin
            exp_result <= next_exp_result;
            op_result = next_op_result;
            result <= next_result;
            i <= next_i;
        end
    end

    always_comb begin
        next_i = i;
        conditions_A = fpu_ref_get_conditions(a);
        next_exp_result = fpu_float_sqrt_exponent(a, conditions_A, valid, mode);
        next_op_result = fpu_float_sqrt_operation(exp_result);
        // if(div_en and we)
        if(next_op_result.valid) next_i++;
        if(next_i==27)
            next_i = 0;
        next_result = fpu_float_sqrt_normalize(op_result);

        // if(result.valid) $display("is_valid: (%h %h %h)", result.sign, result.exponent, result.mantissa[22:0]);
        y = FPU_round(result.mantissa, result.exponent, result.guard, result.sign, result.mode);
        ready = result.valid;
    end

endmodule

module FPU_divide(
    input  fpu_float_fields_t a, b,
    input  fpu_round_mode_t mode,
    input  logic clk, rst, valid,
    output logic [31:0] y,
    output logic ready);
    

    fpu_float_conditions_t conditions_A, conditions_B;
    fpu_div_result_t exp_result, next_exp_result, op_result, next_op_result;
    fpu_result_t next_result, result;
    logic [31:0] i, next_i;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            exp_result <= '{default: 'd0};
            op_result <= '{default: 'd0};
            result <= '{default: 'd0};
            i <= 'd0;
        end else if (next_i!=0) begin
            exp_result <= next_op_result;
            op_result <= '{default: 'b0};
            result <= '{default: 'b0};
            i <= next_i;
        end else begin
            exp_result <= next_exp_result;
            op_result = next_op_result;
            result <= next_result;
            i <= next_i;
        end
    end

    always_comb begin
        next_i = i;
        conditions_A = fpu_ref_get_conditions(a);
        conditions_B = fpu_ref_get_conditions(b);
        next_exp_result = fpu_float_div_exponent(a, b, conditions_A, conditions_B, valid, mode);
        next_op_result = fpu_float_div_operation(exp_result, i);
        // if(div_en and we)
        if(next_op_result.valid) next_i++;
        if(next_i==27)
            next_i = 0;
        next_result = fpu_float_div_normalize(op_result);

        // if(result.valid) $display("is_valid: (%h %h %h)", result.sign, result.exponent, result.mantissa[22:0]);
        y = FPU_round(result.mantissa, result.exponent, result.guard, result.sign, result.mode);
        ready = result.valid;
    end

endmodule

module FPU_multiply(
    input  fpu_float_fields_t a, b,
    input  fpu_round_mode_t mode,
    input  logic clk, rst, valid,
    output logic [31:0] y,
    output logic ready);

    fpu_mult_exp_result_t exp_result, next_exp_result;
    fpu_mult_op_result_t op_result, next_op_result;
    fpu_result_t result, next_result;
    fpu_float_conditions_t conditions_A, conditions_B;


    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            exp_result <= '{default: 'd0};
            op_result <= '{default: 'd0};
            result <= '{default: 'd0};
        end else begin
            exp_result <= next_exp_result;
            op_result = next_op_result;
            result <= next_result;
        end
    end

    always_comb begin
        conditions_A = fpu_ref_get_conditions(a);
        conditions_B = fpu_ref_get_conditions(b);
        next_exp_result = fpu_float_mult_exponent(a, b, conditions_A, conditions_B, valid, mode);
        next_op_result = fpu_float_mult_operation(exp_result);
        next_result = fpu_float_mult_normalize(op_result);

        y = FPU_round(result.mantissa, result.exponent, result.guard, result.sign, result.mode);
        ready = result.valid;
    end 

endmodule

module FPU_add(
    input  fpu_float_fields_t a, b,
    input  fpu_round_mode_t mode,
    input  logic clk, rst, valid,
    output logic [31:0] y,
    output logic ready);
    
    fpu_add_exp_result_t exp_result, next_exp_result;
    fpu_add_op_result_t op_result, next_op_result;
    fpu_result_t result, next_result;
    fpu_float_conditions_t conditions_A, conditions_B;


    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            exp_result <= '{default: 'd0};
            op_result <= '{default: 'd0};
            result <= '{default: 'd0};
        end else begin
            exp_result <= next_exp_result;
            op_result = next_op_result;
            result <= next_result;
        end
    end

    always_comb begin
        conditions_A = fpu_ref_get_conditions(a);
        next_exp_result = fpu_float_add_exponent(a, b, conditions_A, conditions_B, valid, mode);
        next_op_result = fpu_float_add_operation(exp_result);
        next_result = fpu_float_add_normalize(op_result);

        y = FPU_round(result.mantissa, result.exponent, result.guard, result.sign, result.mode);
        ready = result.valid;
    end 

endmodule

module fpu_test;

  import fpu::*;
  // import fpu_reference::*;
  logic [31:0] a, b, i, y, result, score, cscore;
  logic [2:0] op;
  fpu_round_mode_t mode;

  logic rst, clk, ready, valid, close, r;

  // FPU_divide div(.*);
  // FPU_multiply mult(.*);
  // FPU_add add(.*);
  FPU_sqrt sqrt(.*);

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // initial begin
  //   // $monitor("%b %h %h", div.next_op_result)
  //   rst = 1'b1;
  //   valid = 0;
  //   @(posedge clk);
  //   rst = 1'b0;
  //   valid = 1'b1;
  //   a = 32'h41c80000;
  //   b = 32'h40a00000;
  //   @(posedge clk);
  //   valid = 1'b0;
  //   @(posedge ready);
  //   $display("%h", y);
  //   $finish;
  // end


  // FPU fp(.*);

  parameter NUM_VECTORS=10000;
  logic [104:0] vectors [NUM_VECTORS-1:0];
  logic [104:0] args;

  initial begin
    $readmemh("random_floats.vm", vectors);
    score = 0;
    cscore = 0;
    rst = 1;
    valid = 1'b0;
    @(posedge clk);
    rst = 1'b0;
    for(i=0;i<NUM_VECTORS;i++) begin
      args = vectors[i];
      a = args[95:64];
      b = args[63:32];
      op = args[98:96];
      mode = args[103:100];
      result = args[31:0];
      valid = 1'b1;
      @(posedge clk);
      valid = 1'b0;
      @(posedge ready);
      //y = FPU(a, b, op, mode);
      r = (result==y);
      close = 1;
      if (result - y != 32'd1 || y - result != 32'd1 || !r) close = 0; 
      if(!r) begin
        $display($time,, "%h %d %h = %h (%h) Mode: %s  %h  %b\n", a, op, b, y, result, mode, sqrt.result.mantissa, sqrt.result.guard);
        $display("result: %h %h %h", y[31], y[30:23], y[22:0]);
        $display("answer: %h %h %h", result[31], result[30:23], result[22:0]);
      end else begin
        score += 1;
        close = 1;
      end
        cscore += 1;
    end
    $display("\n\n      SCORE: %d/%d", score, NUM_VECTORS);
    $display("\n\nClose SCORE: %d/%d", cscore, NUM_VECTORS);
    $finish;
    
  end

endmodule


// a = 32'd25;
    // result = int2float(a);
    // $display("int: %d --> %h", a, result);
    // a = result;
    // result = float2int(a);
    // $display("float: %h --> %d", a, result);
    // a = 32'd3000;

    // result = int2float(a);
    // $display("int: %d --> %h",a, result);
    // a = result;
    // result = float2int(a);
    // $display("float: %h --> %d", a, result);
    // $finish;