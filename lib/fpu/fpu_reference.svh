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
        logic [1:0] mantissa_msb;
        logic [23:0] mantissa_acc;
        logic [47:0] manitssa_temp;
    } fpu_reference_float_sqrt_partial_arguments_t;

    typedef struct packed {
        logic mantissa_lsb;
        logic [23:0] mantissa_acc;
        logic [47:0] manitssa_temp;
    } fpu_reference_float_sqrt_partial_results_t;

    function automatic fpu_float_mantissa_result_t fpu_reference_float_sqrt_partial(
        input fpu_reference_float_sqrt_partial_arguments_t args
    );
        fpu_reference_float_sqrt_partial_results_t results;
        logic mantissa_acc_lsb = 'b0;

        results.mantissa_temp = {args.mantissa_temp[21:0], args.mantissa_msb};
        results.mantissa_acc = args.mantissa_acc;

        if (results.mantissa_acc <= results.mantissa_temp) begin
            results.mantissa_temp -= results.mantissa_acc;
            results.mantissa_lsb = 'b1;
            results.mantissa_acc += 'b1;
        end else begin
            results.mantissa_lsb = 'b0;
            results.mantissa_acc[0] = 'b0;
        end
        results.mantissa_acc = {results.mantissa_acc[22:0], 1'b1};

        return results;
    endfunction

    // TODO: Does not implement rounding for performance
    function automatic fpu_float_fields_t fpu_reference_float_sqrt(
        input fpu_float_fields_t a
    );
        logic denormalized, mantissa_zero, exponent_negative, number_zero;
        logic [23:0] actual_mantissa, result_mantissa;
        logic [7:0] actual_exponent, result_exponent;
        logic generates_nan;
        fpu_reference_float_sqrt_partial_arguments_t sqrt_args;
        fpu_reference_float_sqrt_partial_results_t sqrt_results;

        // Find flags for floating point input
        denormalized = (a.exponent == 0);
        mantissa_zero = (a.mantissa == 0);
        number_zero = denormalized && mantissa_zero;
        generates_nan = (a.exponent == 'hFF);
        exponent_negative = (a.exponent < 8'd127);

        // Decode the actual mantissa based on normalization
        actual_mantissa = {(denormalized ? 1'b0 : 1'b1), a.mantissa};

        // Find the absolute value of the exponent based on excess-127
        if (exponent_negative) begin
            actual_exponent = denormalized ? (8'd126) : (8'd127 - a.exponent);
        end else begin
            actual_exponent = a.exponent - 8'd127;
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
        sqrt_args.mantissa_msb = actual_mantissa[23:22];
        sqrt_args.mantissa_acc = 24'b1;
        sqrt_args.mantissa_temp = 48'd0;
        for (int i = 0; i < 24; i++) begin
            sqrt_results = fpu_reference_float_sqrt_partial(sqrt_args);
            
            // Update mantissa
            result_mantissa = result_mantissa << 1;
            result_mantissa[0] = sqrt_results.mantissa_lsb;

            // Shift in new digits from original mantissa
            sqrt_args.mantissa_msb = actual_mantissa[23:22];
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
        if (a.sign || generates_nan) begin // Imaginary number
            return FPU_FLOAT_NAN;
        end else if (number_zero) begin
            return FPU_FLOAT_ZERO;
        end else begin
            return '{sign: 'b0, exponent: actual_exponent, mantissa: result_mantissa};
        end

    endfunction

endpackage

`endif
