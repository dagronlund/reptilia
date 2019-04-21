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
        fpu_float_fields_t a, b;
        fpu_float_conditions_t conditions_a, conditions_b;
        fpu_round_mode_t mode;
    } basilisk_add_command_t;

    // typedef struct packed {
    //     fpu_add_exp_result_t a;
    // } basilisk_add_exponent_command_t;

endpackage

`endif
