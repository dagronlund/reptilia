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

module basilisk_memory
    import rv::*;
    import rv32::*;
    import rv32f::*;
    import fpu::*;
    import basilisk::*;
#(
    parameter int OUTPUT_REGISTER_MODE = 1
)(
    input logic clk, rst,

    std_stream_intf.in memory_command, // basilisk_memory_command_t
    std_mem_intf.out memory_request,
    std_stream_intf.out partial_memory_result // basilisk_result_t
);

    std_mem_intf #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) next_memory_request (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) next_partial_memory_result (.clk, .rst);

    logic enable, consume, produce_request, produce_partial_result;

    std_flow_lite #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(2)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({memory_command.valid}),
        .ready_input({memory_command.ready}),

        .valid_output({next_memory_request.valid, next_partial_memory_result.valid}),
        .ready_output({next_memory_request.ready, next_partial_memory_result.ready}),

        .consume, .produce({produce_request, produce_partial_result}), .enable
    );

    std_flow_stage #(
        .T(basilisk_result_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) partial_result_output_stage_inst (
        .clk, .rst,
        .stream_in(next_partial_memory_result), .stream_out(partial_memory_result)
    );

    mem_stage #(
        .MODE(OUTPUT_REGISTER_MODE)
    ) request_output_stage_inst (
        .clk, .rst,
        .mem_in(next_memory_request), .mem_out(memory_request)
    );

    always_comb begin
        consume = 'b1;
        produce_request = 'b1;
        produce_partial_result = 'b0;

        next_partial_memory_result.payload.dest_reg_addr = memory_command.payload.dest_reg_addr;
        next_partial_memory_result.payload.dest_offset_addr = memory_command.payload.dest_offset_addr;

        next_memory_request.read_enable = 'b0;
        next_memory_request.write_enable = 'b0;
        next_memory_request.data = memory_command.payload.a;
        next_memory_request.addr = memory_command.payload.mem_base_addr + memory_command.payload.mem_offset_addr;

        case (memory_command.payload.op)
        BASILISK_MEMORY_OP_LOAD: begin
            produce_partial_result = 'b1;
            next_memory_request.read_enable = 'b1;
        end
        BASILISK_MEMORY_OP_STORE: begin
            next_memory_request.write_enable = 'hf;
        end
        endcase
    end

endmodule
