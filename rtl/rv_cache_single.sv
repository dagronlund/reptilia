`timescale 1ns/1ps

`include "../lib/rv_util.svh"
`include "../lib/rv_mem.svh"

/*
 * Implements a single cycle cache using a simple addressing model of
 * tag, index, and block index in that order. This cache is best used
 * as the cache for a small processor or as L1 for a mid-size processor.
 * Block and row are used as interchangable terms in this module.
 */
module rv_cache_single #(
    parameter WRITE_PROPAGATE = 0, // Writes generate a result as well
    parameter CACHE_WRITE_PROPAGATE = 0, // Cache writes expect a result
    parameter ASSOCIATIVITY = 1, // Direct Associative
    parameter BLOCK_BITS = 6, // 64 byte cache block/row
    parameter INDEX_BITS = 4 // 
)(
    input logic clk, rst,
    rv_mem_intf.in command, // Inbound Commands
    rv_mem_intf.out result, // Outbound Results
    
    rv_mem_intf.out cache_command, // Outbound Cache Commands
    rv_mem_intf.in cache_result // Inbound Cache Results
);

    import rv_mem::*;

    `STATIC_ASSERT($bits(command.data) == $bits(result.data))
    `STATIC_ASSERT($bits(command.data) == $bits(cache_command.data))
    `STATIC_ASSERT($bits(command.data) == $bits(cache_result.data))

    `STATIC_ASSERT($bits(command.addr) == $bits(result.addr))
    `STATIC_ASSERT($bits(command.addr) == $bits(cache_command.addr))
    `STATIC_ASSERT($bits(command.addr) == $bits(cache_result.addr))

    localparam DATA_WIDTH = $bits(command.data);
    localparam ADDR_WIDTH = $bits(command.addr);
    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    localparam TAG_BITS = ADDR_WIDTH - BLOCK_BITS - INDEX_BITS;

    `STATIC_ASSERT(TAG_BITS >= 0)

    logic enable, command_block, result_block, 
            cache_command_block, cache_result_block;
    rv_seq_flow_controller #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(2)
    ) flow_controller_inst (
        .clk, .rst, .enable(enable),
        .inputs_valid({command.valid, cache_result.valid}), 
        .inputs_ready({command.ready, cache_result.ready}),
        .inputs_block({command_block, cache_result_block}),

        .outputs_valid({result.valid, cache_command.valid}),
        .outputs_ready({result.ready, cache_command.ready}),
        .outputs_block({result_block, cache_command_block})
    );

    // rv_memory_double_port #(
    //     .DATA_WIDTH(DATA_WIDTH),
    //     .ADDR_WIDTH(ADDR_WIDTH)
    // ) rv_memory_double_port_inst (
    //     .clk, .rst,

    //     .enable0(!rst && enable0),
    //     .write_enable0(command0.op == RV_MEM_WRITE),
    //     .addr_in0(command0.addr),
    //     .data_in0(command0.data),
    //     .data_out0(result0.data),

    //     .enable1(!rst && enable1),
    //     .write_enable1(command1.op == RV_MEM_WRITE),
    //     .addr_in1(command1.addr),
    //     .data_in1(command1.data),
    //     .data_out1(result1.data)
    // );

endmodule
