`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/fpu/fpu.svh"
`include "../../lib/fpu/fpu_sqrt.svh"
`include "../../lib/basilisk/basilisk.svh"

`else

`include "std_util.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32f.svh"
`include "basilisk.svh"
`include "fpu.svh"
`include "fpu_sqrt.svh"

`endif

module basilisk_sqrt
    import rv::*;
    import rv32::*;
    import rv32f::*;
    import fpu::*;
    import fpu_sqrt::*;
    import basilisk::*;
#(
    parameter int OUTPUT_REGISTER_MODE = 1
)(
    input logic clk, rst,

    std_stream_intf.in sqrt_command, // basilisk_sqrt_command_t
    std_stream_intf.out sqrt_result_command // fpu_result_t
);

    std_stream_intf #(.T(fpu_sqrt_result_t)) sqrt_exponent_command (.clk, .rst);
    std_stream_intf #(.T(fpu_sqrt_result_t)) sqrt_operation_command (.clk, .rst);

    basilisk_sqrt_exponent #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_sqrt_exponent_inst (
        .clk, .rst,
        .sqrt_command, .sqrt_exponent_command
    );

    basilisk_sqrt_operation #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_sqrt_operation_inst (
        .clk, .rst,
        .sqrt_exponent_command, .sqrt_operation_command
    );

    basilisk_sqrt_normalize #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_sqrt_normalize_inst (
        .clk, .rst,
        .sqrt_operation_command, .sqrt_result_command
    );

endmodule
