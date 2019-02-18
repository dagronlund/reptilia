`ifndef __FPU_REFERENCE__
`define __FPU_REFERENCE__

package fpu_reference;

    import fpu::*;

    function automatic fpu_float_fields_t fpu_reference_float_add(
        input fpu_float_fields_t a, b
    );

        conditions_A = fpu_ref_get_conditions(a);
        conditions_B = fpu_ref_get_conditions(b);

        return '{default: 'b0};
    endfunction

    function automatic fpu_float_conditions_t (
        input fpu_float_fields_t a);

        fpu_float_conditions_t c;

        c.zero = (a.exponent == 0 || a.mantissa==0);
        c.norm = (a.exponent!=0);
        c.nan = (a==FPU_FLOAT_NAN);
        c.inf = (a==FPU_FLOAT_POS_INF || a==FPU_FLOAT_NEG_INF);

        return c;
    endfunction 

    function automatic fpu_float_fields_t fpu_reference_float_mult(
        input fpu_float_fields_t a, b
    );

        logic exp0, overflow, underflow;
        logic [5:0] leading_mzs;
        logic [8:0] expY_ex, expY_ex_neg;
        logic [23:0] sigA, sigB;
        logic [47:0] sig_product;

        fpu_float_conditions_t conditions_A, conditions_B;
        fpu_float_fields_t y;

        conditions_A = fpu_ref_get_conditions(a);
        conditions_B = fpu_ref_get_conditions(b);


        y.sign = a.sign ^ b.sign;
        exp0 = ((a.exponent == 8'h7f) || (b.exponent == 8'h7f));


        /* ----------------------------------------------------- */
        // Preprocess two operands

        sigA = {conditions_A.norm, a.mantissa};
        sigB = {conditions_B.norm, b.mantissa};
        if (!conditions_A.norm)  sigA = sigA << 1;
        if (!conditions_B.norm)  sigB = sigB << 1;


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

        /* ----------------------------------------------------- */
        // Multipliy operation


        // TODO:make function out of mult
        sig_product = fpu_operations_multiply(sigA[26:3], sigB[26:3], sig_product);

        /* ----------------------------------------------------- */
        // Normalize

        if (sig_product[47]) begin
          if (~expY_ex[8] && expY_ex[7:0] >= 254) begin
              overflow = 1;
          end
          sig_product = sig_product >> 1;
          expY_ex = expY_ex + 1;
        end

        leading_mzs = get_leading_zeros_47(sig_product[46:0], leading_mzs);

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
          sig_product = sig_product >> 1;
        end

        // TODO: make rounding function
        // round(sig_product, y.mantissa);

                    // if (sig_product[22:20] == 3'b100) begin
                    //   // Round to even
                    //   if (sig_product[23])  sigY[27:3] = sig_product[47:23] + 1;
                    //   else  sigY[27:3] = sig_product[47:23];
                    // end 
                    // else if (sig_product[22:20] > 3'b100) begin
                    //   // Round up
                    //   sigY[27:3] = sig_product[47:23] + 1;
                    // end 
                    // else if (sig_product[22:20] < 3'b100) begin
                    //   // Round down
                    //   sigY[27:3] = sig_product[47:23];
                    // end


                    //$display ("sigY = %b", sig_product[45:23]);
                    /* ----------------------------------------------------- */
                    // Must check for overflow after round

                    // if (sigY[27]) begin
                    //   if (~expY_ex[8] && expY_ex[7:0] >= 254)
                    //     overflow = 1;
                    //   sigY = sigY >> 1;
                    //   expY_ex = expY_ex + 1;
                    // end
                    // else if (sigY[26] & expY_ex == 0) begin
                    //   expY_ex = expY_ex + 1;
                    // end

                    // if (overflow || expY_ex == 9'h0FF) begin /* Set to infty */
                    //   expY_ex = 9'h0FF;
                    //   sigY = 0;
                    // end
                    // else if (underflow) begin /* Set to Zero */
                    //   expY_ex = 0;
                    //   sigY = 0;
                    // end
                    // /* If Zero happened then make zero */
                    // else if (sigY == 0)
                    //   expY_ex = 0;


        /* ----------------------------------------------------- */
        // Change exponential back
        y.exponent = expY_ex[7:0];
        y.mantissa = sig_product[46:24];




        /* In these special Cases */
        if (a.exponent == 8'hFF || b.exponent == 8'hFF) begin
          if (conditions_A.nan || conditions_B.nan)               // a or b is NAN
            {y.sign, y.exponent, y.mantissa} = FPU_FLOAT_NAN;
          else if (conditions_A.inf && conditions_B.zero)         // infinity times zero
            {y.sign, y.exponent, y.mantissa} = FPU_FLOAT_NAN;
          else if (conditions_B.inf && conditions_A.zero)         
            {y.sign, y.exponent, y.mantissa} = FPU_FLOAT_NAN;
          else if (conditions_A.inf && !(conditions_B.inf))       // infinity times a number
            {y.exponent, y.mantissa} = {a.exponent, a.mantissa};
            else if (conditions_B.inf && !(conditions_A.inf))       
            {y.exponent, y.mantissa} = {b.exponent, b.mantissa};
          else if (conditions_A.inf && conditions_B.inf)          // infinity times infinity
            {y.exponent, y.mantissa} = {a.exponent, a.mantissa};
          else
            {y.sign, y.exponent, y.mantissa} = FPU_FLOAT_NAN;
        end else if (overflow)
            y = (y.sign) ? FPU_FLOAT_NEG_INF:FPU_FLOAT_POS_INF
        else if (underflow)
            y = FPU_FLOAT_ZERO;


        return y;
    endfunction

    function automatic fpu_float_fields_t fpu_reference_float_div(
        input fpu_float_fields_t a, b
    );

        fpu_float_conditions_t conditions_A, conditions_B;
        fpu_float_quotient_t div_result;
        fpu_float_fields_t y;

        conditions_A = fpu_ref_get_conditions(a);
        conditions_B = fpu_ref_get_conditions(b);

        y.sign = a.sign ^ b.sign;

        // Divide exponents
        y.exponent = a.exponent + !conditions_A.norm - b.exponent - conditions_B.norm;
        if (a.exponent < b.exponent) begin
            y.exponent = ~(y.exponent) + 1;
            exp_neg = 1;
        end

        // check for over/underflow
        if(y.exponent > 127) begin
            if(exp_neg) underflow = 1;
            else overflow = 1;
        end

        // divide the mantissas 
        // TODO: make division function
        div_result = fpu_operation_division({conditions_A.norm, a.mantissa}, {conditions_B.norm, b.mantissa});
        
        // normalize result
        leading_zeros = get_leading_zeros_47(div_result.mantissa);
        diff = 24 - leading_zeros;
        if (diff[6]) begin
          div_result = {div_result.mantissa, div_result.guard} >> diff;
          if (diff >= 255-y.exponent && !exp_neg) overflow = 1;
          else begin
            if (exp_neg) y.exponent -= diff; 
            else y.exponent += diff;
          end
        end else begin
          diff = ~(diff) + 1;
          div_result = {div_result.mantissa, div_result.guard} << diff;
          if (diff > y.exponent && exp_neg) underflow = 1;
          else begin
            if (exp_neg) y.exponent += diff;
            else y.exponent -= diff;
          end
        end
        y.exponent = (exp_neg) ? 127-y.exponent : y.exponent + 127; 
        y.mantissa = div_result.mantissa[22:0];
        //TODO: round

        if(conditions_A.nan || conditions_B.nan)
            y = FPU_FLOAT_NAN;
        else if (conditions_B.zero || conditions_B.inf)
            y = FPU_FLOAT_NAN;
        else if (overflow || conditions_A.inf)
            y = (y.sign) ? FPU_FLOAT_NEG_INF:FPU_FLOAT_POS_INF
        else if (underflow || conditions_A.zero)
            y = FPU_FLOAT_ZERO;
        return y;
    endfunction

    typedef struct packed {
        logic mantissa_lsb;
        logic [1:0] mantissa_msb;
        logic [23:0] mantissa_acc;
        logic [47:0] mantissa_temp;
    } fpu_reference_float_sqrt_partial_t;

    function automatic fpu_reference_float_sqrt_partial_t fpu_reference_float_sqrt_partial(
        input fpu_reference_float_sqrt_partial_t args
    );
        logic mantissa_acc_lsb = 'b0;
        logic [47:0] sub_result;
        logic sub_carry;

        // Shift in two mantissa bits
        args.mantissa_temp = {args.mantissa_temp[21:0], args.mantissa_msb};

        {sub_carry, sub_result} = args.mantissa_temp - args.mantissa_acc;

        if (!sub_carry) begin // mantissa_temp >= mantissa_acc
            args.mantissa_temp = sub_result;
            args.mantissa_lsb = 'b1;
            args.mantissa_acc += 'b1;
        end else begin
            args.mantissa_lsb = 'b0;
            args.mantissa_acc[0] = 'b0;
        end

        // Shift in a one in the least signficant bit
        args.mantissa_acc = {args.mantissa_acc[22:0], 1'b1};

        return args;
    endfunction

    // TODO: Does not implement rounding for performance
    // TODO: Does not handle denormalized
    function automatic fpu_float_fields_t fpu_reference_float_sqrt(
        input fpu_float_fields_t number
    );
        logic denormalized, mantissa_zero, exponent_negative, number_zero;
        fpu_float_mantissa_complete_t actual_mantissa, result_mantissa;
        logic [7:0] actual_exponent, result_exponent;
        logic generates_nan;
        fpu_reference_float_sqrt_partial_t sqrt_partial;

        // Find flags for floating point input
        denormalized = (number.exponent == 0);
        mantissa_zero = (number.mantissa == 0);
        number_zero = denormalized && mantissa_zero;
        generates_nan = (number.exponent == 'hFF) || number.sign;
        exponent_negative = (number.exponent < 8'd127);

        // Decode the actual mantissa based on normalization
        actual_mantissa = {(denormalized ? 1'b0 : 1'b1), number.mantissa};

        // Find the absolute value of the exponent based on excess-127
        if (exponent_negative) begin
            actual_exponent = denormalized ? (8'd126) : (8'd127 - number.exponent);
        end else begin
            actual_exponent = number.exponent - 8'd127;
        end
        
        // Modify mantissa if even/odd/or negative
        if (actual_exponent[0]) begin // Odd
            if (exponent_negative) begin
                actual_mantissa = {2'b0, actual_mantissa[23:2]};
            end else begin
                actual_mantissa = {actual_mantissa[23:0]};
            end
        end else begin // Even
            actual_mantissa = {1'b0, actual_mantissa[23:1]};
        end 

        // Halve the exponent
        actual_exponent = actual_exponent >> 1;

        // Perform square root on the mantissa
        result_mantissa = 24'b0;
        sqrt_partial.mantissa_msb = actual_mantissa[23:22];
        sqrt_partial.mantissa_acc = 24'b1;
        sqrt_partial.mantissa_temp = 48'd0;
        for (int i = 0; i < 24; i++) begin
            sqrt_partial = fpu_reference_float_sqrt_partial(sqrt_partial);
            
            // Update mantissa
            result_mantissa = {result_mantissa[22:0], sqrt_partial.mantissa_lsb};

            // Shift in new digits from original mantissa
            sqrt_partial.mantissa_msb = actual_mantissa[23:22];
            actual_mantissa = actual_mantissa << 2;
        end

        // Convert the exponent back into excess-127
        if (denormalized) begin
            actual_exponent = 8'h00; // TODO: Handle denormalized numbers
        end else if (exponent_negative) begin
            actual_exponent = 8'd127 - actual_exponent;
        end else begin
            actual_exponent = actual_exponent + 8'd127;
        end

        // Handle special case
        if (generates_nan || denormalized) begin // Imaginary number
            return FPU_FLOAT_NAN;
        end else if (number_zero) begin
            return FPU_FLOAT_ZERO;
        end else begin
            return '{
                sign: 'b0, 
                exponent: actual_exponent, 
                mantissa: result_mantissa
            };
        end

    endfunction

<<<<<<< HEAD
    function automatic fpu_float_fields_t fpu_reference_float_round(
        input fpu_round_mode_t round_mode,
        input fpu_guard_bits_t guard_bits,
        input fpu_float_fields_t number
    );
        logic enable_rounding, denormalized, rounded_carry;
        fpu_float_mantissa_complete_t full_mantissa, rounded_mantissa;

        // Find normalized/denormalized mantissa and try rounding up
        denormalized = (number.exponent == 8'h00);
        full_mantissa = {~denormalized, number.mantissa};
        {rounded_carry, rounded_mantissa} = full_mantissa + 'b1;

        // Decide to round up based on different rounding modes
        if (guard_bits == 3'b100) begin
            case (round_mode)
            FPU_ROUND_MODE_EVEN: enable_rounding = number.mantissa[0];
            FPU_ROUND_MODE_DOWN: enable_rounding = 'b0;
            FPU_ROUND_MODE_UP:   enable_rounding = 'b1;
            FPU_ROUND_MODE_ZERO: enable_rounding = number.sign;
            endcase
        end else if (guard_bits[2] == 1'b1) begin // Round up
            enable_rounding = 'b1;
        end else begin // Round down
            enable_rounding = 'b0;
        end

        // Modify results if rounding overflowed
        if (enable_rounding) begin
            if (denormalized) begin
                number.mantissa = rounded_mantissa[22:0];
                if (rounded_mantissa[23]) begin // Overflow
                    number.exponent += 1;
                end
            end else begin
                if (rounded_carry) begin // Overflow
                    number.exponent += 1;
                    if (number.exponent == 8'hFF) begin // Overflow into infinity
                        number.mantissa = 23'b0;
                    end else begin
                        number.mantissa = rounded_mantissa[23:1];
                    end
                end else begin
                    number.mantissa = rounded_mantissa[22:0];
                end
            end
        end

        return number;
    endfunction

=======
>>>>>>> 23eeb96fdf2141f096fe48256346e1faf14329b6
endpackage

`endif
