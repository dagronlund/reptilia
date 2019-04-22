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

module basilisk_sqrt_exponent
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
    std_stream_intf.out sqrt_exponent_command // basilisk_sqrt_operation_t
);

    std_stream_intf #(.T(basilisk_sqrt_operation_t)) next_sqrt_exponent_command (.clk, .rst);

    logic enable, consume, produce;

    std_flow_lite #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({sqrt_command.valid}),
        .ready_input({sqrt_command.ready}),

        .valid_output({next_sqrt_exponent_command.valid}),
        .ready_output({next_sqrt_exponent_command.ready}),

        .consume, .produce, .enable
    );

    std_flow_stage #(
        .T(basilisk_sqrt_operation_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) output_stage_inst (
        .clk, .rst,
        .stream_in(next_sqrt_exponent_command), .stream_out(sqrt_exponent_command)
    );

    always_comb begin
        consume = 'b1;
        produce = 'b1;

        next_sqrt_exponent_command.payload.result = fpu_float_sqrt_exponent(
                sqrt_command.payload.a,
                sqrt_command.payload.conditions_a,
                sqrt_command.payload.mode
        );
        next_sqrt_exponent_command.payload.dest_reg_addr = sqrt_command.payload.dest_reg_addr;
    end

endmodule
