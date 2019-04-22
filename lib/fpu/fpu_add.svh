`ifndef __FPU_ADD__
`define __FPU_ADD__

`include "fpu.svh"
`include "fpu_utils.svh"
`include "fpu_operations.svh"

package fpu_add;

    import fpu::*;
    import fpu_utils::*;
    import fpu_operations::*;

    typedef struct packed {
        logic sign_A, sign_B;
        logic [26:0] sigA, sigB;
        logic [7:0] exponent;
        logic nan, inf, zero, valid;
        fpu_round_mode_t mode;
    } fpu_add_exp_result_t;

    function automatic fpu_add_exp_result_t fpu_float_add_exponent(
        input  fpu_float_fields_t a, b,
        input  fpu_float_conditions_t conditions_A, conditions_B,
        input  logic valid,
        input  fpu_round_mode_t mode);

        logic sticky;
        logic [7:0] exponent_diff, exp1, exp2, expA, expB;
        logic [26:0] A, B, argA, argB;
        fpu_add_exp_result_t result;

        A = {conditions_A.norm, a.mantissa, 3'b0};
        B = {conditions_B.norm, b.mantissa, 3'b0};

        // Align exponents
        exp1 = a.exponent + !conditions_A.norm;
        exp2 = b.exponent + !conditions_B.norm;

        // {A.sign, A.conditions} = {a.sign, conditions_A};
        // {B.sign, B.conditions} = {b.sign, conditions_B};
        
        {argA, expA} = {A, exp1};
        {argB, expB} = {B, exp2};
        result.sign_A = a.sign;
        result.sign_B = b.sign;
        if (exp1 < exp2) begin
            {argA, expA} = {B, exp2};
            {argB, expB} = {A, exp1};
            result.sign_A = b.sign;
            result.sign_B = a.sign;
        end 

        // if (expA > expB) begin
        exponent_diff = expA - expB;// expA - expB;
        if (exponent_diff >= 27) exponent_diff = 26;
        sticky = get_sticky_bit_27(argB, exponent_diff);
        argB = argB >> exponent_diff;
        argB[0] |= sticky;
        result.exponent = expA;

        result.sigA = argA;
        result.sigB = argB;
        result.nan = conditions_A.nan || conditions_B.nan;
        result.inf = conditions_A.nan || conditions_B.inf;
        result.zero = conditions_A.zero || conditions_B.zero;
        result.mode = mode;
        result.valid = valid;

        return result;
    endfunction

    typedef struct packed {
        logic sign, carry;
        logic [26:0] sum;
        logic [7:0] exponent;
        logic nan, inf, zero, valid;
        fpu_round_mode_t mode;
    } fpu_add_op_result_t;

    function automatic fpu_add_op_result_t fpu_float_add_operation(
        input fpu_add_exp_result_t exp_result);
        
        logic [26:0] mant_A, mant_B;
        fpu_add_op_result_t result;

        mant_A = exp_result.sigA;
        mant_B = exp_result.sigB;

        result.carry = 0;
        case({exp_result.sign_A, exp_result.sign_B}) 
            2'b00: begin
                    {result.carry, result.sum} = mant_A + mant_B;
                    result.sign = 1'b0;
                end

            2'b01: begin
                    if(mant_B > mant_A) begin
                        {result.carry, result.sum} = mant_B - mant_A;
                        result.sign = 1'b1;
                    end else begin
                        {result.carry, result.sum} = mant_A - mant_B;
                        result.sign = 1'b0;
                    end
                end

            2'b10: begin
                    if(mant_A > mant_B) begin
                        {result.carry, result.sum} = mant_A - mant_B;
                        result.sign = 1'b1;
                    end else begin
                        {result.carry, result.sum} = mant_B - mant_A;
                        result.sign = 1'b0;
                    end
                end

            2'b11: begin
                    {result.carry, result.sum} = mant_A + mant_B;
                    result.sign = 1'b1;
                end
        endcase

        result.exponent = exp_result.exponent;
        result.nan = exp_result.nan;
        result.inf = exp_result.inf;
        result.zero = exp_result.zero;
        result.mode = exp_result.mode;
        result.valid = exp_result.valid;

        return result;

    endfunction

    function automatic fpu_result_t fpu_float_add_normalize(
        input fpu_add_op_result_t y);
        
        fpu_result_t result;
        logic sticky, overflow;
        logic [4:0] leading_zeros;

        // normalize
        result.exponent = y.exponent;
        overflow = 1'b0;

        if({y.carry, y.sum}==0) result.exponent = 0;
        else if(y.carry) begin
            sticky = get_sticky_bit_27(y.sum, 5'd1);
            y.sum = {y.carry, y.sum[26:1]};
            y.sum[0] = y.sum[0] | sticky;
            result.exponent += 1;
            if(result.exponent==8'd255) overflow = 1;
        end else if (!y.sum[26]) begin
            leading_zeros = get_leading_zeros_27(y.sum);
            y.sum = y.sum << leading_zeros;
            result.exponent -= leading_zeros;
        end
        
        result.sign = y.sign;
        result.mantissa = y.sum[26:3];
        result.guard = y.sum[2:0];
        result.nan = y.nan;
        result.inf = y.inf;
        result.zero = y.zero;
        result.mode = y.mode;
        result.valid = y.valid;

        return result;
    endfunction

endpackage

`endif
