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

module basilisk_mult_add_round
    import rv::*;
    import rv32::*;
    import rv32f::*;
    import fpu::*;
    import basilisk::*;
#(
    parameter int OUTPUT_REGISTER_MODE = 1
)(
    input logic clk, rst,

    std_stream_intf.in mult_add_normalize_command, // basilisk_mult_add_normalize_command_t
    std_stream_intf.out mult_add_command  // basilisk_add_command_t
);

    std_stream_intf #(.T(basilisk_add_command_t)) next_mult_add_command (.clk, .rst);

    logic enable, consume, produce;

    std_flow_lite #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({mult_add_normalize_command.valid}),
        .ready_input({mult_add_normalize_command.ready}),

        .valid_output({next_mult_add_command.valid}),
        .ready_output({next_mult_add_command.ready}),

        .consume, .produce, .enable
    );

    std_flow_stage #(
        .T(basilisk_add_command_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) output_stage_inst (
        .clk, .rst,
        .stream_in(next_mult_add_command), .stream_out(mult_add_command)
    );

    always_comb begin
        automatic fpu_result_t mult_result = mult_add_normalize_command.payload.result;
        
        consume = 'b1;
        produce = 'b1;

        next_mult_add_command.payload.a = fpu_decode_float(fpu_operations_round(mult_result));
        next_mult_add_command.payload.conditions_a = fpu_get_conditions(next_mult_add_command.payload.a);

        next_mult_add_command.payload.b = mult_add_normalize_command.payload.c;
        next_mult_add_command.payload.conditions_b = fpu_get_conditions(next_mult_add_command.payload.b);

        next_mult_add_command.payload.mode = mult_result.mode;

        next_mult_add_command.payload.dest_reg_addr = mult_add_normalize_command.payload.dest_reg_addr;
        next_mult_add_command.payload.dest_offset_addr = mult_add_normalize_command.payload.dest_offset_addr;
    end

endmodule
