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
    parameter INDEX_BITS = 4, // 
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

endmodule
