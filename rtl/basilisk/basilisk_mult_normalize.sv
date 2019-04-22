`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/fpu/fpu.svh"
`include "../../lib/fpu/fpu_mult.svh"
`include "../../lib/basilisk/basilisk.svh"

`else

`include "std_util.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32f.svh"
`include "basilisk.svh"
`include "fpu.svh"
`include "fpu_mult.svh"

`endif

module basilisk_mult_normalize
    import rv::*;
    import rv32::*;
    import rv32f::*;
    import fpu::*;
    import fpu_mult::*;
    import basilisk::*;
#(
    parameter int OUTPUT_REGISTER_MODE = 1
)(
    input logic clk, rst,

    std_stream_intf.in mult_operation_command, // basilisk_mult_operation_command_t
    std_stream_intf.out mult_result_command,  // fpu_result_t
    std_stream_intf.out mult_add_normalize_command // basilisk_mult_add_normalize_command_t
);

    std_stream_intf #(.T(fpu_result_t)) next_mult_result_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_mult_add_normalize_command_t)) next_mult_add_normalize_command (.clk, .rst);

    logic enable, consume, produce_result, produce_macc;

    std_flow_lite #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(2)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({mult_operation_command.valid}),
        .ready_input({mult_operation_command.ready}),

        .valid_output({next_mult_result_command.valid, next_mult_add_normalize_command.valid}),
        .ready_output({next_mult_result_command.ready, next_mult_add_normalize_command.ready}),

        .consume, .produce({produce_result, produce_macc}), .enable
    );

    std_flow_stage #(
        .T(fpu_result_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) output_result_stage_inst (
        .clk, .rst,
        .stream_in(next_mult_result_command), .stream_out(mult_result_command)
    );

    std_flow_stage #(
        .T(basilisk_mult_add_normalize_command_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) output_macc_stage_inst (
        .clk, .rst,
        .stream_in(next_mult_add_normalize_command), .stream_out(mult_add_normalize_command)
    );

    always_comb begin
        consume = 'b1;
        produce_result = (!mult_operation_command.payload.enable_macc);
        produce_macc = (mult_operation_command.payload.enable_macc);

        next_mult_result_command.payload = fpu_float_mult_normalize(
                mult_operation_command.payload.result
        );

        next_mult_add_normalize_command.payload.result = next_mult_result_command.payload;
        next_mult_add_normalize_command.payload.c = mult_operation_command.payload.c;
    end

endmodule
