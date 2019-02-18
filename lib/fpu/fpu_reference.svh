`ifndef __FPU_REFERENCE__
`define __FPU_REFERENCE__

package fpu_reference;

    import fpu::*;

    function automatic fpu_float_fields_t fpu_reference_float_add(
        input fpu_float_fields_t a, b
    );
        return '{default: 'b0};
    endfunction

    function automatic fpu_float_fields_t fpu_reference_float_mult(
        input fpu_float_fields_t a, b
    );
        return '{default: 'b0};
    endfunction

    function automatic fpu_float_fields_t fpu_reference_float_div(
        input fpu_float_fields_t a, b
    );
        return '{default: 'b0};
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

endpackage

`endif
