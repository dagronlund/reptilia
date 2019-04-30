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

module basilisk_add_operation
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

    std_stream_intf.in add_exponent_command, // basilisk_add_exponent_command_t
    std_stream_intf.out add_operation_command // basilisk_add_operation_command_t
);

    std_stream_intf #(.T(basilisk_add_operation_command_t)) next_add_operation_command (.clk, .rst);

    logic enable, consume, produce;

    std_flow_lite #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({add_exponent_command.valid}),
        .ready_input({add_exponent_command.ready}),

        .valid_output({next_add_operation_command.valid}),
        .ready_output({next_add_operation_command.ready}),

        .consume, .produce, .enable
    );

    std_flow_stage #(
        .T(basilisk_add_operation_command_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) output_stage_inst (
        .clk, .rst,
        .stream_in(next_add_operation_command), .stream_out(add_operation_command)
    );

    always_comb begin
        consume = 'b1;
        produce = 'b1;

        next_add_operation_command.payload.dest_reg_addr = add_exponent_command.payload.dest_reg_addr;
        next_add_operation_command.payload.dest_offset_addr = add_exponent_command.payload.dest_offset_addr;
        next_add_operation_command.payload.result = fpu_float_add_operation(add_exponent_command.payload.result);
    end

endmodule
