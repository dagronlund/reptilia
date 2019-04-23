`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/fpu/fpu.svh"
`include "../../lib/basilisk/basilisk.svh"

`else

`include "std_util.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32f.svh"
`include "basilisk.svh"
`include "fpu.svh"

`endif

module basilisk_mult
    import rv::*;
    import rv32::*;
    import rv32f::*;
    import fpu::*;
    import basilisk::*;
#(
    parameter int OUTPUT_REGISTER_MODE = 1
)(
    input logic clk, rst,

    std_stream_intf.in mult_command, // basilisk_mult_command_t
    std_stream_intf.out mult_result_command, // basilisk_result_t
    std_stream_intf.out mult_add_command  // basilisk_add_command_t
);

    std_stream_intf #(.T(basilisk_mult_exponent_command_t)) mult_exponent_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_mult_operation_command_t)) mult_operation_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_mult_add_normalize_command_t)) mult_add_normalize_command (.clk, .rst);

    basilisk_mult_exponent #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_mult_exponent_inst (
        .clk, .rst,
        .mult_command, .mult_exponent_command
    );

    basilisk_mult_operation #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_mult_operation_inst (
        .clk, .rst,
        .mult_exponent_command, .mult_operation_command
    );

    basilisk_mult_normalize #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_mult_normalize_inst (
        .clk, .rst,
        .mult_operation_command, .mult_result_command, .mult_add_normalize_command
    );

    basilisk_mult_add_round #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_mult_add_round_inst (
        .clk, .rst,
        .mult_add_normalize_command, .mult_add_command
    );

endmodule
