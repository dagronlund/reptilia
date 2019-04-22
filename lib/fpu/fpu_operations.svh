`ifndef __FPU_OPERATIONS__
`define __FPU_OPERATIONS__

`include "fpu.svh"
`include "fpu_utils.svh"

package fpu_operations;

    import fpu::*;
    import fpu_utils::*;

    function automatic logic[47:0] fpu_operations_multiply(
        input  logic [23:0] a, b);
            // logic [47:0] result1, result2;

            // result1 = dsp48_mac(a, b[23:18], 48'd0);
            // result2 = dsp48_mac(a, b[17:0], {result1<<18});

        return a*b; //result2;
    endfunction

    function automatic logic [50:0] fpu_operations_divide(
        input  logic [23:0] a, b);
        
        logic [5:0] i;
        logic [71:0] A, A2, x;

        logic [50:0] result;

        A = a<<24;
        for (i=0; i<48; i++) begin
            x = b<<(47-i);
            if (x<=A) begin
            A = A - x;
            result[50-i] = 1;
            end else begin
            result[50-i] = 0;
            end;
        end

        A2 = A<<3;
        for (i=0;i<3;i++) begin
            x = b<<(2-i);
            if (x<=A2) begin
            A2 = A2 - x;
            result[2-i] = 1;
            end else begin
            result[2-i] = 0;
            end
        end 

        if (A2 != 0) result[0] |= 1'b1;
        
        return result;
    endfunction

    function automatic logic [27:0] fpu_operations_add(
        input logic [26:0] a, b);

        logic [47:0] result;

        result = dsp48_mac(a, 18'd0, {21'd0, b});

        return result[27:0];
    endfunction 

    function automatic fpu_float_fields_t FPU_round(
        input logic [23:0] mantissa,
        input logic [7:0] exponent,
        input logic [2:0] guard,
        input logic sign,
        input fpu_round_mode_t round_mode);

        logic [23:0] result;
        logic [7:0] exp;
        logic carry, round, sticky;

        fpu_float_fields_t y;

        exp = exponent;
        carry = 1'b0;
        round = 1'b0;
        case(round_mode)
            FPU_ROUND_MODE_EVEN: round = guard[2] && ((guard[1] || guard[0]) || mantissa[0]);
            FPU_ROUND_MODE_DOWN: round = sign;
              FPU_ROUND_MODE_UP: round = !sign;
            FPU_ROUND_MODE_ZERO: round = 1'b0;
        endcase

        if (guard==3'd0) round = 1'b0;

        {carry, result} = mantissa + round;

        if(carry) begin
            //sticky = get_sticky_bit_27(result, 5'd1);
            result = result >> 1;
            //result[0] |= sticky;
            if(exp >= 254) exp = 255;
            else exp += 1;
        end

        y.sign = sign;
        y.exponent = exp;
        y.mantissa = result[22:0];

        return y;
    endfunction

    function automatic fpu_float_fields_t fpu_operations_round(
            input fpu_result_t result
    );
        return FPU_round(result.mantissa, result.exponent, result.guard, result.sign, result.round_mode);
    endfunction

endpackage

`endif