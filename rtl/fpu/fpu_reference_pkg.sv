//!import fpu/fpu_pkg

package fpu_reference_pkg;

    import fpu_pkg::*;

    function automatic fpu_float_fields_t fpu_reference_float_add(
        input fpu_float_fields_t a, b,
        input fpu_round_mode_t mode
    );

        logic [26:0] a_mant, b_mant, sum;
        logic [7:0] exponent_diff, exponent;
        logic [4:0] leading_zeros;
        logic diff_sign, sticky, overflow, carry, sign;

        fpu_float_conditions_t conditions_A, conditions_B;
        fpu_float_fields_t y;

        conditions_A = fpu_ref_get_conditions(a);
        conditions_B = fpu_ref_get_conditions(b);

        a_mant = {conditions_A.norm, a.mantissa, 3'b0};
        b_mant = {conditions_B.norm, b.mantissa, 3'b0};

        // Align exponents
        exponent = a.exponent;
        if (a.exponent > b.exponent) begin
            exponent_diff = a.exponent - b.exponent;
            sticky = get_sticky_bit_27(b_mant, exponent_diff);
            b_mant = b_mant >> exponent_diff;
            b_mant[0] |= sticky;
            exponent = a.exponent;
        end else if (b.exponent > a.exponent) begin
            exponent_diff = b.exponent - a.exponent;
            sticky = get_sticky_bit_27(a_mant, exponent_diff);
            a_mant = a_mant >> exponent_diff;
            a_mant[0] |= sticky;
            exponent = b.exponent;
        end

        overflow = 0;
        carry = 0;
        case({a.sign, b.sign}) 
            2'b00: begin
                    {carry, sum} = a_mant + b_mant;
                    sign = 1'b0;
                end

            2'b01: begin
                    if(b_mant > a_mant) begin
                        {carry, sum} = b_mant - a_mant;
                        sign = 1'b1;
                    end else begin
                        {carry, sum} = a_mant - b_mant;
                        sign = 1'b0;
                    end
                end

            2'b10: begin
                    if(a_mant > b_mant) begin
                        {carry, sum} = a_mant - b_mant;
                        sign = 1'b1;
                    end else begin
                        {carry, sum} = b_mant - a_mant;
                        sign = 1'b0;
                    end
                end

            2'b11: begin
                    {carry, sum} = a_mant + b_mant;
                    sign = 1'b1;
                end
        endcase

        if(carry) begin
            sticky = get_sticky_bit_27(sum, 5'd1);
            sum = {carry, sum[26:1]};
            sum[0] = sum[0] | sticky;
            exponent += 1;
            if(exponent==8'd255) overflow = 1;
        end else if (!sum[26]) begin
            leading_zeros = get_leading_zeros_27(sum);
            sum = sum << leading_zeros;
            exponent -= leading_zeros;
        end
        
        y = FPU_round(sum[26:3], exponent, sum[2:0], sign, mode);
        
        if (conditions_A.inf && !conditions_B.inf)
            y = a;
        else if (conditions_B.inf && !conditions_A.inf)
            y = b;
        else if (conditions_A.nan || conditions_B.nan)
            y = FPU_FLOAT_NAN;
        else if (conditions_A.inf && conditions_B.inf && (a.sign==b.sign))
            y = a;
        else if (conditions_A.inf && conditions_B.inf && (a.sign!=b.sign))
            y = FPU_FLOAT_NAN;
        else if (overflow) begin
            y.exponent = 8'hFF;
            y.mantissa = 23'd0;
        end


        return y;
    endfunction

    function automatic fpu_float_fields_t fpu_reference_float_mult(
        input fpu_float_fields_t a, b,
        input fpu_round_mode_t mode
    );

        logic sign, exp0, overflow, underflow;
        logic [5:0] leading_mzs;
        logic [8:0] expY_ex, expY_ex_neg;
        logic [23:0] sigA, sigB;
        logic [47:0] sig_product;

        fpu_float_conditions_t conditions_A, conditions_B;
        fpu_float_fields_t y;

        conditions_A = fpu_ref_get_conditions(a);
        conditions_B = fpu_ref_get_conditions(b);


        sign = a.sign ^ b.sign;
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
        sig_product = fpu_operations_multiply(sigA, sigB);

        /* ----------------------------------------------------- */
        // Normalize

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
          sig_product = sig_product >> 1;
        end

        if (sig_product[19:0]!=0) sig_product[20] = 1'd1;
        // TODO: make rounding function
        y = FPU_round(sig_product[46:23], expY_ex[7:0], sig_product[22:20], sign, mode);


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
            y = (sign) ? FPU_FLOAT_NEG_INF:FPU_FLOAT_POS_INF;
        else if (underflow)
            y = FPU_FLOAT_ZERO;


        return y;
    endfunction

    function automatic fpu_float_fields_t fpu_reference_float_div(
        input fpu_float_fields_t a, b,
        input fpu_round_mode_t mode
    );

        fpu_float_conditions_t conditions_A, conditions_B;
        //fpu_float_quotient_t div_result;
        fpu_float_fields_t y;

        logic exp_neg, sign, overflow, underflow, sticky;
        logic [5:0] leading_zeros; 
        logic [8:0] exponent, diff;
        logic [50:0] div_result;

        conditions_A = fpu_ref_get_conditions(a);
        conditions_B = fpu_ref_get_conditions(b);

        sign = a.sign ^ b.sign;

        // Divide exponents
        exponent = a.exponent + !conditions_A.norm - b.exponent - !conditions_B.norm;
        exp_neg = 0;
        if (a.exponent < b.exponent) begin
            exponent = ~(exponent) + 1;
            exp_neg = 1;
        end

        // check for over/underflow
        overflow = 0;
        underflow = 0;
        // $display("DIVIDE: %h - %h = %h", a.exponent, b.exponent, exponent);
        if(exponent > 127) begin
            if(exp_neg) underflow = 1;
            else overflow = 1;
        end

        // divide the mantissas 
        div_result = fpu_operations_divide({conditions_A.norm, a.mantissa}, {conditions_B.norm, b.mantissa});
        
        // normalize 
        leading_zeros = get_leading_zeros_47(div_result[50:3]);
        diff = 23 - leading_zeros;
        if (leading_zeros < 24) begin
            sticky = get_sticky_bit_27(div_result[26:0], diff);
            div_result = div_result >> diff;
            div_result[0] |= sticky;
          if (diff >= 255-exponent && !exp_neg) overflow = 1;
          else begin
            if (exp_neg) exponent -= diff - 1; 
            else exponent += diff - 1;
          end
        end else begin
          diff = ~(diff) + 1;
          div_result = div_result << diff;
          if (diff > exponent && exp_neg) underflow = 1;
          else begin
            if (exp_neg) exponent += diff - 1;
            else exponent -= diff - 1;
          end
        end

        exponent = (exp_neg) ? 127-exponent : exponent + 127; 
        //Round
        y = FPU_round(div_result[26:3], exponent[7:0], div_result[2:0], sign, mode);

        if(conditions_A.nan || conditions_B.nan)
            y = FPU_FLOAT_NAN;
        else if (conditions_B.zero || conditions_B.inf)
            y = FPU_FLOAT_NAN;
        else if (overflow || conditions_A.inf)
            y = (y.sign) ? FPU_FLOAT_NEG_INF:FPU_FLOAT_POS_INF;
        else if (underflow || conditions_A.zero)
            y = FPU_FLOAT_ZERO;
        return y;
    endfunction

    typedef struct packed {
        logic mantissa_lsb;
        logic [1:0] mantissa_msb;
        logic [47:0] mantissa_acc;
        logic [47:0] mantissa_temp;
    } fpu_reference_float_sqrt_partial_t;

    function automatic fpu_reference_float_sqrt_partial_t fpu_reference_float_sqrt_partial(
        input fpu_reference_float_sqrt_partial_t args
    );
        logic mantissa_acc_lsb = 'b0;
        logic [47:0] sub_result;
        logic sub_carry;

        // Shift in two mantissa bits
        args.mantissa_temp = {args.mantissa_temp[45:0], args.mantissa_msb};

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
        args.mantissa_acc = {args.mantissa_acc[46:0], 1'b1};
        return args;
    endfunction

    // TODO: Does not implement rounding for performance
    // TODO: Does not handle denormalized
    function automatic fpu_float_fields_t fpu_reference_float_sqrt(
        input fpu_float_fields_t number,
        input fpu_round_mode_t mode
    );
        logic denormalized, mantissa_zero, exponent_negative, number_zero;
        logic [23:0] actual_mantissa;
        logic [26:0] result_mantissa;
        logic [7:0] actual_exponent, result_exponent;
        logic [4:0] zeros;
        logic generates_nan;
        fpu_reference_float_sqrt_partial_t sqrt_partial;
        fpu_float_fields_t y;

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
        result_mantissa = 27'd0;
        sqrt_partial.mantissa_msb = actual_mantissa[23:22];
        sqrt_partial.mantissa_acc = 48'd1;
        sqrt_partial.mantissa_temp = 48'd0;
        for (int i = 0; i < 27; i++) begin
            sqrt_partial = fpu_reference_float_sqrt_partial(sqrt_partial);
            // Update mantissa
            result_mantissa = {result_mantissa[25:0], sqrt_partial.mantissa_lsb};

            // Shift in new digits from original mantissa
            actual_mantissa = actual_mantissa << 2;
            sqrt_partial.mantissa_msb = actual_mantissa[23:22];
        end

        // Normalize
        zeros = get_leading_zeros_27(result_mantissa);
        result_mantissa = result_mantissa << zeros;
        if(exponent_negative) actual_exponent += zeros;
        else actual_exponent -= zeros;

        // Convert the exponent back into excess-127
        if (denormalized) begin
            actual_exponent = 8'h00; // TODO: Handle denormalized numbers
        end else if (exponent_negative) begin
            actual_exponent = 8'd127 - actual_exponent;
        end else begin
            actual_exponent = actual_exponent + 8'd127;
        end

        // round
        y = FPU_round(result_mantissa[26:3], actual_exponent, result_mantissa[2:0], number.sign, mode);

        // Handle special case
        if (generates_nan || denormalized) begin // Imaginary number
            return FPU_FLOAT_NAN;
        end else if (number_zero) begin
            return FPU_FLOAT_ZERO;
        end else begin
            return y;
        end

    endfunction

endpackage
