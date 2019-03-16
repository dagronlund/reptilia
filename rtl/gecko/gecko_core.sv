`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

module gecko_core
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#(
    parameter int INST_LATENCY = 1,
    parameter int DATA_LATENCY = 1
)(
    input logic clk, rst,

    std_mem_intf.out inst_request,
    std_mem_intf.in inst_result,

    std_mem_intf.out data_request,
    std_mem_intf.in data_result
);

    `STATIC_ASSERT($size(inst_request.addr) == 32)
    `STATIC_ASSERT($size(inst_result.data) == 32)

    `STATIC_ASSERT($size(data_request.addr) == 32)
    `STATIC_ASSERT($size(data_result.data) == 32)

    // std_mem_intf #(
    //     .DATA_WIDTH(32),
    //     .ADDR_WIDTH($size(gecko_pc_t)),
    //     .ADDR_BYTE_SHIFTED(1)
    // ) fetch_inst_command_inst (.clk, .rst);

    std_stream_intf #(.T(gecko_jump_command_t)) jump_command (.clk, .rst);
    std_stream_intf #(.T(gecko_branch_signal_t)) branch_signal (.clk, .rst);
    std_stream_intf #(.T(gecko_branch_command_t)) branch_command (.clk, .rst);

    std_stream_intf #(.T(gecko_instruction_operation_t)) instruction_command (.clk, .rst);

    std_stream_intf #(.T(gecko_execute_operation_t)) execute_command (.clk, .rst);
    std_stream_intf #(.T(gecko_system_operation_t)) system_command (.clk, .rst);

    std_stream_intf #(.T(gecko_operation_t)) execute_result (.clk, .rst);
    std_stream_intf #(.T(gecko_operation_t)) system_result (.clk, .rst);

    std_stream_intf #(.T(gecko_operation_t)) writeback_result (.clk, .rst);

    std_stream_intf #(.T(gecko_instruction_operation_t)) instruction_command_in (.clk, .rst);
    std_stream_intf #(.T(gecko_instruction_operation_t)) instruction_command_out (.clk, .rst);

    std_stream_intf #(.T(gecko_mem_operation_t)) mem_command_in (.clk, .rst);
    std_stream_intf #(.T(gecko_mem_operation_t)) mem_command_out (.clk, .rst);

    gecko_fetch gecko_fetch_inst
    (
        .clk, .rst,

        .jump_command,
        .branch_command,

        // std_stream_intf.out instruction_command, // gecko_instruction_operation_t
        .instruction_command(instruction_command_in),
        .instruction_request(inst_request)
    );

    std_stream_stage #(
        .LATENCY(INST_LATENCY)
    ) gecko_inst_stage_inst (
        .clk, .rst,
        .data_in(instruction_command_in),
        .data_out(instruction_command_out)
    );

    gecko_decode gecko_decode_inst
    (
        .clk, .rst,

        // std_stream_intf.in instruction_command, // gecko_instruction_operation_t
        .instruction_command(instruction_command_out),
        .instruction_result(inst_result),

        .system_command,
        .execute_command,

        .jump_command,

        .branch_signal,
        .writeback_result
    );

    gecko_execute gecko_execute_inst
    (
        .clk, .rst,

        .execute_command,

        // std_stream_intf.out mem_command, // gecko_mem_operation_t
        .mem_command(mem_command_in),
        .mem_request(data_request),

        .execute_result,

        .branch_command, .branch_signal
    );

    std_stream_stage #(
        .LATENCY(DATA_LATENCY)
    ) gecko_data_stage_inst (
        .clk, .rst,
        .data_in(mem_command_in),
        .data_out(mem_command_out)
    );

    gecko_system gecko_system_inst
    (
        .clk, .rst,

        .instruction_retired(1'b1), // TODO

        .system_command,
        .system_result
    );

    gecko_writeback gecko_writeback_inst
    (
        .clk, .rst,

        .execute_result,

        // std_stream_intf.in mem_command, // gecko_mem_operation_t
        .mem_command(mem_command_out),
        .mem_result(data_result),

        .system_result,

        .writeback_result
    );

endmodule
