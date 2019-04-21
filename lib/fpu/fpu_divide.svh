package fpu_divide;
    import fpu::*;
    import fpu_utils::*;

    typedef struct packed {
        logic sign;
        logic [23:0] b;
        logic [50:0] A;
        logic [26:0] y;
        logic nan, inf, zero;
        logic [8:0] exponent;
        logic exp_neg, valid;
        fpu_round_mode_t mode;
    } fpu_div_result_t;

    function automatic fpu_float_conditions_t fpu_ref_get_conditions(
        input fpu_float_fields_t a);

        fpu_float_conditions_t c;

        c.zero = (a.exponent == 0 && a.mantissa==0);
        c.norm = (a.exponent!=0);
        c.nan = (a==FPU_FLOAT_NAN);
        c.inf = (a==FPU_FLOAT_POS_INF || a==FPU_FLOAT_NEG_INF);

        return c;
    endfunction 

    function automatic fpu_div_result_t fpu_float_div_exponent(
        fpu_float_fields_t a, b,
        fpu_float_conditions_t conditions_A, conditions_B,
        logic valid,
        fpu_round_mode_t mode
        );

        fpu_div_result_t result;

        logic zero, exp_neg, sign, overflow, underflow, sticky; 
        logic [8:0] exponent;
        // Divide exponents
        zero = 0;
        result.exponent = a.exponent - b.exponent;
        if (!conditions_A.norm || !conditions_B.norm) 
            zero = 1'b1;

        result.exp_neg = 0;
        if (a.exponent < b.exponent) begin
            result.exponent = ~(result.exponent) + 1;
            result.exp_neg = 1;
        end

        // check for over/underflow
        overflow = 0;
        underflow = 0;
        // $display("DIVIDE: %h - %h = %h", a.exponent, b.exponent, exponent);
        if(result.exponent > 127) begin
            if(result.exp_neg) underflow = 1;
            else overflow = 1;
        end

        result.inf = overflow || conditions_A.inf;
        result.nan = conditions_B.inf || conditions_B.nan || conditions_A.nan || conditions_B.zero;
        result.zero = underflow || conditions_A.zero || zero;
        result.A = {1'b1, a.mantissa} << 26;
        result.b = {1'b1, b.mantissa};
        result.sign = a.sign ^ b.sign;
        result.valid = valid;
        result.mode = mode;

        return result;

    endfunction


    // typedef struct packed {
    //     logic sign;
    //     logic [23:0] b;
    //     logic [50:0] A;
    //     logic [26:0] y;
    //     logic nan, inf, zero;
    //     logic [8:0] exponent;
    //     logic exp_neg;
    // } fpu_div_result_t;

    function automatic fpu_div_result_t fpu_float_div_operation(
            input fpu_div_result_t result, i);
        //A = a<<27;
            logic [50:0] x;

            x = result.b<<(26-i);
            if (x<=result.A) begin
                result.A = result.A - x;
                result.y[26-i] = 1;
            end else begin
                result.y[26-i] = 0;
            end;

            result.exponent = result.exponent;
        // end

        return result;
    endfunction

    function automatic fpu_result_t fpu_float_div_normalize(
        input fpu_div_result_t y);
        // normalize 
        logic exp_neg, underflow;
        logic [4:0] leading_zeros;
        logic [26:0] div_result;
        logic [8:0] exponent;

        fpu_result_t result;

        div_result = y.y;
        exponent = y.exponent;
        exp_neg = y.exp_neg;

        if(y.A !=0) div_result[0] = 1'b1;

        leading_zeros = get_leading_zeros_27(div_result);
       
        if (leading_zeros) begin
            div_result = div_result << leading_zeros;
            if (leading_zeros > exponent && exp_neg) underflow = 1;
            else begin
                if (exp_neg) exponent += leading_zeros;
                else exponent -= leading_zeros;
            end
        end
        // diff = 23 - leading_zeros;
        // if (leading_zeros < 24) begin
        //     sticky = get_sticky_bit_27(div_result[26:0], diff);
        //     div_result = div_result >> diff;
        //     div_result[0] |= sticky;
        //   if (diff >= 255-result.exponent && !exp_neg) overflow = 1;
        //   else begin
        //     if (exp_neg) result.exponent -= diff - 1; 
        //     else result.exponent += diff - 1;
        //   end
        // end else begin
        //   diff = ~(diff) + 1;
        //   div_result = div_result << diff;
        //   if (diff > result.exponent && exp_neg) underflow = 1;
        //   else begin
        //     if (exp_neg) result.exponent += diff - 1;
        //     else result.exponent -= diff - 1;
        //   end
        // end

        result.sign = y.sign;
        result.exponent = (exp_neg) ? 127-exponent : exponent + 127; 
        result.mantissa = div_result[26:3];
        result.guard = div_result[2:0];
        result.nan = y.nan;
        result.zero = y.zero || underflow || result.exponent =='d0;
        result.inf = y.inf;
        result.valid = y.valid;
        result.mode = y.mode;

        return result;
    endfunction

endpackage : fpu_divide