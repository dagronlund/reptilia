//!import fpu/fpu_pkg

package fpu_mult_pkg;

    import fpu_pkg::*;

    typedef struct packed {
        fpu_float_fields_t a, b;
        logic nan, inf, zero;
        logic [8:0] exponent;
        fpu_round_mode_t mode;
        // logic valid;
    } fpu_mult_exp_result_t;

    function automatic fpu_mult_exp_result_t fpu_float_mult_exponent(
        input fpu_float_fields_t a, b,
        input fpu_float_conditions_t conditions_A, conditions_B,
        // input logic valid, 
        input fpu_round_mode_t mode);

        // result.sign = a.sign ^ b.sign;

        logic exp0, overflow, underflow;
        logic [8:0] expY_ex, expY_ex_neg;
        fpu_mult_exp_result_t result;

        result.a = a;
        result.b = b;
        exp0 = ((a.exponent == 8'h7f) || (b.exponent == 8'h7f));


        /* ----------------------------------------------------- */
        // Preprocess two operands

        //result.sigA = {conditions_A.norm, a.mantissa};
        // result.sigB = {conditions_B.norm, b.mantissa};
        if (!conditions_A.norm) begin 
            conditions_A.zero = 1'b1;
        end
        if (!conditions_B.norm) begin 
            conditions_B.zero = 1'b1;
        end


        /* ----------------------------------------------------- */
        // Determine underflow, overflow and demornalized result

        expY_ex = a.exponent + b.exponent - 8'h7f;  // equal to -8'h7f

        overflow = 0;
        underflow = 0;


        if (~exp0) begin
          overflow = a.exponent[7] && b.exponent[7] && expY_ex[8];
          expY_ex_neg = ~expY_ex;
          underflow = ~a.exponent[7] && ~b.exponent[7] && expY_ex[8] && (expY_ex_neg >= 25);  // 26 or 27
        end

        result.zero = conditions_A.zero || conditions_B.zero || underflow;
        result.nan = conditions_A.nan || conditions_B.nan;
        result.inf = conditions_A.inf || conditions_B.inf || overflow;
        result.exponent = expY_ex;
        // result.valid = valid;
        result.mode = mode;
        
        return result;

    endfunction

    typedef struct packed {
        logic sign;
        logic [47:0] product;
        logic nan, inf, zero;
        logic [8:0] exponent;
        fpu_round_mode_t mode;
        // logic valid;
    } fpu_mult_op_result_t;

    function automatic logic [47:0] fpu_float_mult_multiply(
        input logic [23:0] a, b
    );
        return a*b;
    endfunction

    function automatic fpu_mult_op_result_t fpu_float_mult_operation(
        input fpu_mult_exp_result_t exp_result);

        logic [23:0] sigA, sigB;
        fpu_mult_op_result_t result;

        result.sign = exp_result.a.sign ^ exp_result.b.sign;
        sigA = {1'b1, exp_result.a.mantissa};
        sigB = {1'b1, exp_result.b.mantissa};
        result.product = fpu_float_mult_multiply(sigA, sigB);
        
        result.exponent = exp_result.exponent;
        result.mode = exp_result.mode;
        // result.valid = exp_result.valid;
        result.zero = exp_result.zero;
        result.inf = exp_result.inf;
        result.nan = exp_result.nan;

        return result;
    endfunction

    function automatic fpu_result_t fpu_float_mult_normalize(
        input fpu_mult_op_result_t y);
        
        logic [47:0] sig_product;
        logic [8:0] expY_ex, expY_ex_neg;
        logic [5:0] leading_mzs;
        logic overflow;
        fpu_result_t result;

        overflow = 'b0;
        sig_product = y.product;
        expY_ex = y.exponent;
        if (sig_product[47]) begin
          if (~expY_ex[8] && expY_ex[7:0] >= 254) begin
              overflow = 1;
          end
          sig_product = sig_product >> 1;
          expY_ex = expY_ex + 1;
        end

        leading_mzs = get_leading_zeros_47(sig_product[46:0]);

        if (leading_mzs < 47 && ~expY_ex[8] && expY_ex[7:0] > leading_mzs) begin
          sig_product = sig_product << leading_mzs;
          expY_ex = expY_ex - leading_mzs;
        end
        else if (leading_mzs < 47 && ~expY_ex[8] && expY_ex <= leading_mzs) begin
          sig_product = sig_product << expY_ex; 
          expY_ex = 0;
        end
        else if (leading_mzs < 47 && expY_ex[8]) begin
          expY_ex_neg = ~expY_ex+1;
          sig_product = sig_product >> expY_ex_neg;
          expY_ex = 0;
        end


        /* ----------------------------------------------------- */
        // Adjustment denormal number to exp=-126
        if (expY_ex == 0) begin
          sig_product = 0;
        end

        if (sig_product[19:0]!=0) sig_product[20] = 1'd1;
        
        result.sign = y.sign;
        result.mantissa = sig_product[46:23];
        result.exponent = expY_ex[7:0];
        result.guard = sig_product[22:20];
        result.nan = y.nan;
        result.inf = y.inf || overflow;
        result.zero = y.zero;
        result.mode = y.mode;
        // result.valid = y.valid;

        return result;

    endfunction

endpackage
