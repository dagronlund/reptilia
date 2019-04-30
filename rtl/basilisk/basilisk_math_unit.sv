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

module basilisk_math_unit
    import rv::*;
    import rv32::*;
    import rv32f::*;
    import fpu::*;
    import basilisk::*;
#(
    parameter int OUTPUT_REGISTER_MODE = 1,
    parameter int ENABLE_MEMORY_CONVERT = 1
)(
    input logic clk, rst,

    std_stream_intf.in add_command, // basilisk_add_command_t
    std_stream_intf.in mult_command, // basilisk_mult_command_t
    std_stream_intf.in divide_command, // basilisk_divide_command_t
    std_stream_intf.in sqrt_command, // basilisk_sqrt_command_t

    std_stream_intf.in memory_result, // basilisk_result_t
    std_stream_intf.in convert_result, // basilisk_result_t

    std_stream_intf.out writeback_result // basilisk_writeback_result_t
);

    localparam int WRITEBACK_PORTS = (ENABLE_MEMORY_CONVERT != 0) ? 6 : 4;

    std_stream_intf #(.T(basilisk_add_command_t)) mult_add_command (.clk, .rst);

    std_stream_intf #(.T(basilisk_result_t)) add_result_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) mult_result_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) divide_result_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) sqrt_result_command (.clk, .rst);

    std_stream_intf #(.T(basilisk_result_t)) writeback_results_in [WRITEBACK_PORTS] (.clk, .rst);

    stream_tie stream_tie_inst0(.stream_in(add_result_command), .stream_out(writeback_results_in[0]));
    stream_tie stream_tie_inst1(.stream_in(mult_result_command), .stream_out(writeback_results_in[1]));
    stream_tie stream_tie_inst2(.stream_in(divide_result_command), .stream_out(writeback_results_in[2]));
    stream_tie stream_tie_inst3(.stream_in(sqrt_result_command), .stream_out(writeback_results_in[3]));

    generate
    if (ENABLE_MEMORY_CONVERT) begin
        stream_tie stream_tie_inst4(.stream_in(memory_result), .stream_out(writeback_results_in[4]));
        stream_tie stream_tie_inst5(.stream_in(convert_result), .stream_out(writeback_results_in[5]));
    end
    endgenerate

    basilisk_add #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_add_inst (
        .clk, .rst,
        .add_command, .mult_add_command,
        .add_result_command
    );

    basilisk_mult #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_mult_inst (
        .clk, .rst,
        .mult_command,
        .mult_add_command, .mult_result_command
    );

    basilisk_divide #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_divide_inst (
        .clk, .rst,
        .divide_command,
        .divide_result_command
    );

    basilisk_sqrt #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE)
    ) basilisk_sqrt_inst (
        .clk, .rst,
        .sqrt_command,
        .sqrt_result_command
    );

    basilisk_writeback #(
        .OUTPUT_REGISTER_MODE(OUTPUT_REGISTER_MODE),
        .PORTS(WRITEBACK_PORTS)
    ) basilisk_writeback_inst (
        .clk, .rst,

        .writeback_results_in,
        .writeback_result
    );

endmodule
