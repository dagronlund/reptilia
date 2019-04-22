`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/fpu/fpu.svh"
`include "../../lib/fpu/fpu_divide.svh"
`include "../../lib/basilisk/basilisk.svh"

`else

`include "std_util.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32f.svh"
`include "basilisk.svh"
`include "fpu.svh"
`include "fpu_divide.svh"

`endif

module basilisk_divide
    import rv::*;
    import rv32::*;
    import rv32f::*;
    import fpu::*;
    import fpu_divide::*;
    import basilisk::*;
#(
    parameter int OUTPUT_REGISTER_MODE = 1
)(
    input logic clk, rst,

    std_stream_intf.in divide_command, // basilisk_divide_command_t
    std_stream_intf.out divide_result_command // fpu_result_t
);

    std_stream_intf #(.T(basilisk_divide_result_t)) divide_exponent_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_divide_result_t)) divide_operation_command (.clk, .rst);

    basilisk_divide_exponent #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_divide_exponent_inst (
        .clk, .rst,
        .divide_command, .divide_exponent_command
    );

    basilisk_divide_operation #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_divide_operation_inst (
        .clk, .rst,
        .divide_exponent_command, .divide_operation_command
    );

    basilisk_divide_normalize #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_divide_normalize_inst (
        .clk, .rst,
        .divide_operation_command, .divide_result_command
    );

endmodule
