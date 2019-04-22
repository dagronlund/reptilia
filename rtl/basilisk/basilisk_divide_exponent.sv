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

module basilisk_divide_exponent
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
    std_stream_intf.out divide_exponent_command // basilisk_divide_result_t
);

    std_stream_intf #(.T(basilisk_divide_result_t)) next_divide_exponent_command (.clk, .rst);

    logic enable, consume, produce;

    std_flow_lite #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({divide_command.valid}),
        .ready_input({divide_command.ready}),

        .valid_output({next_divide_exponent_command.valid}),
        .ready_output({next_divide_exponent_command.ready}),

        .consume, .produce, .enable
    );

    std_flow_stage #(
        .T(basilisk_divide_result_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) output_stage_inst (
        .clk, .rst,
        .stream_in(next_divide_exponent_command), .stream_out(divide_exponent_command)
    );

    always_comb begin
        consume = 'b1;
        produce = 'b1;

        next_divide_exponent_command.payload.result = fpu_float_div_exponent(
                divide_command.payload.a, divide_command.payload.b, 
                divide_command.payload.conditions_a, divide_command.payload.conditions_b, 
                divide_command.payload.mode
        );
    end

endmodule
