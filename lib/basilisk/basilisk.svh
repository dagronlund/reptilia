`ifndef __BASILISK__
`define __BASILISK__

`ifdef __LINTER__

`include "../isa/rv32.svh"
`include "../isa/rv32f.svh"
`include "../fpu/fpu.svh"
`include "../fpu/fpu_add.svh"
`include "../fpu/fpu_mult.svh"
`include "../fpu/fpu_divide.svh"
`include "../fpu/fpu_sqrt.svh"

`else

`include "rv32.svh"
`include "rv32f.svh"
`include "fpu.svh"
`include "fpu_add.svh"
`include "fpu_mult.svh"
`include "fpu_divide.svh"
`include "fpu_sqrt.svh"

`endif

package basilisk;

    import rv32::*;
    import rv32f::*;
    import fpu::*;
    import fpu_add::*;
    import fpu_mult::*;
    import fpu_divide::*;
    import fpu_sqrt::*;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        fpu_result_t result;
    } basilisk_result_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        fpu_float_fields_t a, b; // a + b
        fpu_float_conditions_t conditions_a, conditions_b;
        fpu_round_mode_t mode;
    } basilisk_add_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        fpu_add_exp_result_t result;
    } basilisk_add_exponent_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        fpu_add_op_result_t result;
    } basilisk_add_operation_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        logic enable_macc;
        fpu_float_fields_t a, b, c; // a * b or (a * b) + c
        fpu_float_conditions_t conditions_a, conditions_b, conditions_c;
        fpu_round_mode_t mode;
    } basilisk_mult_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        logic enable_macc;
        fpu_float_fields_t c;
        fpu_float_conditions_t conditions_c;
        fpu_mult_exp_result_t result;
    } basilisk_mult_exponent_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        logic enable_macc;
        fpu_float_fields_t c;
        fpu_float_conditions_t conditions_c;
        fpu_mult_op_result_t result;
    } basilisk_mult_operation_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        fpu_float_fields_t c;
        fpu_float_conditions_t conditions_c;
        fpu_result_t result;
    } basilisk_mult_add_normalize_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        fpu_float_fields_t a, b; // a / b
        fpu_float_conditions_t conditions_a, conditions_b;
        fpu_round_mode_t mode;
    } basilisk_divide_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        fpu_div_result_t result;
    } basilisk_divide_result_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        fpu_float_fields_t a; // sqrt(a)
        fpu_float_conditions_t conditions_a;
        fpu_round_mode_t mode;
    } basilisk_sqrt_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        fpu_sqrt_result_t result;
    } basilisk_sqrt_operation_t;

endpackage

`endif
