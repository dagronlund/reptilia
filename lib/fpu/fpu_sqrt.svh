package fpu_sqrt;
    import fpu::*;
    import fpu_utils::*;
    import fpu_operations::*;

    typedef struct packed {
        logic mantissa_lsb;
        logic [1:0] mantissa_msb;
        logic [47:0] mantissa_acc;
        logic [47:0] mantissa_temp;
    } fpu_reference_float_sqrt_partial_t;

    typedef struct packed {
        logic sign;
        logic [7:0] exponent;
        logic [26:0] mantissa;
        logic [23:0] actual_mantissa;
        fpu_reference_float_sqrt_partial_t sqrt_partial;
        logic inf, nan, zero, exponent_negative, valid;
        fpu_round_mode_t mode;
    } fpu_sqrt_result_t;

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

    function automatic fpu_sqrt_result_t fpu_float_sqrt_exponent(
        input fpu_float_fields_t number,
        input fpu_float_conditions_t conditions,
        input valid,
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
        fpu_sqrt_result_t result;

        // Find flags for floating point input
        denormalized = !conditions.norm;
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
        result.actual_mantissa = actual_mantissa;
        result.exponent = actual_exponent >> 1;

        // Perform square root on the mantissa
        result.mantissa = 27'd0;
        result.sign = number.sign;
        result.sqrt_partial.mantissa_msb = actual_mantissa[23:22];
        result.sqrt_partial.mantissa_acc = 48'd1;
        result.sqrt_partial.mantissa_temp = 48'd0;


        result.nan = conditions.nan || number.sign; 
        result.inf = conditions.inf;
        result.zero = conditions.zero;
        result.exponent_negative = exponent_negative;
        result.valid = valid;
        result.mode = mode;

        return result;

    endfunction

    function automatic fpu_sqrt_result_t fpu_float_sqrt_operation(
        fpu_sqrt_result_t result
        );

        result.sqrt_partial = fpu_reference_float_sqrt_partial(result.sqrt_partial);
        // Update mantissa
        result.mantissa = {result.mantissa[25:0], result.sqrt_partial.mantissa_lsb};

        // Shift in new digits from original mantissa
        result.actual_mantissa = result.actual_mantissa << 2;
        result.sqrt_partial.mantissa_msb = result.actual_mantissa[23:22];

        return result;
    endfunction

    function automatic fpu_result_t fpu_float_sqrt_normalize(
        input fpu_sqrt_result_t y);

        logic [4:0] zeros;
        logic [26:0] result_mantissa;
 
        fpu_reference_float_sqrt_partial_t sqrt_partial;
        fpu_result_t result;

        sqrt_partial = y.sqrt_partial;
        result_mantissa = y.mantissa;
        result.exponent = y.exponent;

        if (sqrt_partial.mantissa_temp != 'd0) result_mantissa[0] |= 1'b1;


        // Normalize
        zeros = get_leading_zeros_27(result_mantissa);
        result_mantissa = result_mantissa << zeros;
        if(y.exponent_negative) result.exponent += zeros;
        else result.exponent -= zeros;

        // if (sqrt_partial.mantissa_temp != 'd0) result_mantissa[0] |= 1'b1;


        // Convert the exponent back into excess-127
        if (y.exponent_negative) begin
            result.exponent = 8'd127 - result.exponent;
        end else begin
            result.exponent = result.exponent + 8'd127;
        end

        result.sign = y.sign;
        result.mantissa = result_mantissa[26:3];
        result.guard = result_mantissa[2:0];
        result.nan = y.nan;
        result.inf = y.inf;
        result.zero = y.zero;
        result.valid = y.valid;
        result.mode = y.mode;

        // round
        // y = FPU_round(result_mantissa[26:3], actual_exponent, result_mantissa[2:0], number.sign, mode);
        return result;
    endfunction

endpackage : fpu_sqrt