`ifndef __BASILISK__
`define __BASILISK__

`ifdef __LINTER__

`include "../isa/rv32.svh"
`include "../isa/rv32f.svh"
`include "../fpu/fpu.svh"

`else

`include "rv32.svh"
`include "rv32f.svh"
`include "fpu.svh"

`endif

package basilisk;

    import rv32::*;
    import rv32f::*;
    import fpu::*;

    typedef struct packed {
        fpu_float_fields_t a, b; // a + b
        fpu_float_conditions_t conditions_a, conditions_b;
        fpu_round_mode_t mode;
    } basilisk_add_command_t;

    typedef struct packed {
        logic enable_macc;
        fpu_float_fields_t a, b, c; // a * b or (a * b) + c
        fpu_float_conditions_t conditions_a, conditions_b, conditions_c;
        fpu_round_mode_t mode;
    } basilisk_mult_command_t;

    typedef struct packed {
        logic enable_macc;
        fpu_float_fields_t c;
        fpu_mult_exp_result_t result;
    } basilisk_mult_exponent_command_t;

    typedef struct packed {
        logic enable_macc;
        fpu_float_fields_t c;
        fpu_mult_op_result_t result;
    } basilisk_mult_operation_command_t;

    typedef struct packed {
        fpu_float_fields_t c;
        fpu_result_t result;
    } basilisk_mult_add_normalize_command_t;

    typedef struct packed {
        fpu_float_fields_t a, b; // a / b
        fpu_float_conditions_t conditions_a, conditions_b;
        fpu_round_mode_t mode;
    } basilisk_divide_command_t;

    typedef struct packed {
        fpu_div_result_t result;
    } basilisk_divide_result_t;

endpackage

`endif
