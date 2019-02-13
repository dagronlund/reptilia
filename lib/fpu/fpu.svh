`ifndef __FPU__
`define __FPU__

package fpu;

    typedef logic [31:0] fpu_float_t;
    typedef logic        fpu_float_sign_t;
    typedef logic [7:0]  fpu_float_exponent_t;
    typedef logic [22:0] fpu_float_mantissa_t;

    typedef logic [63:0] fpu_double_t;
    typedef logic        fpu_double_sign_t;
    typedef logic [10:0] fpu_double_exponent_t;
    typedef logic [51:0] fpu_double_mantissa_t;

    typedef struct packed {
        fpu_float_sign_t sign;
        fpu_float_exponent_t exponent;
        fpu_float_mantissa_t mantissa;
    } fpu_float_fields_t;

    typedef struct packed {
        fpu_double_sign_t sign;
        fpu_double_exponent_t exponent;
        fpu_double_mantissa_t mantissa;
    } fpu_double_fields_t;

    function automatic fpu_float_fields_t fpu_decode_float(
        input fpu_float_t raw
    );
        return '{
            sign: raw[31], 
            exponent: raw[30:23], 
            mantissa: raw[22:0]
        };
    endfunction

    function automatic fpu_float_t fpu_encode_float(
        input fpu_float_fields_t decoded
    );
        return {decoded.sign, decoded.exponent, decoded.mantissa};
    endfunction

    function automatic fpu_double_fields_t fpu_decode_double(
        input fpu_float_t raw
    );
        return '{
            sign: raw[63], 
            exponent: raw[62:52], 
            mantissa: raw[51:0]
        };
    endfunction

    function automatic fpu_double_t fpu_encode_double(
        input fpu_double_fields_t decoded
    );
        return {decoded.sign, decoded.exponent, decoded.mantissa};
    endfunction

endpackage

`endif
