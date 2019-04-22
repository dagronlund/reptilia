`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/fpu/fpu.svh"
`include "../../lib/fpu/fpu_add.svh"
`include "../../lib/basilisk/basilisk.svh"

`else

`include "std_util.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32f.svh"
`include "basilisk.svh"
`include "fpu.svh"
`include "fpu_add.svh"

`endif

module basilisk_add
    import rv::*;
    import rv32::*;
    import rv32f::*;
    import fpu::*;
    import fpu_add::*;
    import basilisk::*;
#(
    parameter int OUTPUT_REGISTER_MODE = 1
)(
    input logic clk, rst,

    std_stream_intf.in add_command, // basilisk_add_command_t
    std_stream_intf.in mult_add_command, // basilisk_add_command_t
    
    std_stream_intf.out add_result_command // fpu_result_t
);

    std_stream_intf #(.T(fpu_add_exp_result_t)) add_exponent_command (.clk, .rst);
    std_stream_intf #(.T(fpu_add_op_result_t)) add_operation_command (.clk, .rst);

    basilisk_add_exponent #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_add_exponent_inst (
        .clk, .rst,
        .add_command, .mult_add_command, .add_exponent_command
    );

    basilisk_add_operation #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_add_operation_inst (
        .clk, .rst,
        .add_exponent_command, .add_operation_command
    );

    basilisk_add_normalize #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_add_normalize_inst (
        .clk, .rst,
        .add_operation_command, .add_result_command
    );

endmodule
