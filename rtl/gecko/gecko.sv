`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

module gecko
    import gecko::*;
(
    input logic clk, rst
);

    /*
     * FETCH
     */

    logic jump_command_valid;
    gecko_jump_command_t jump_command;

    std_mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH($size(gecko_pc_t)),
        .ADDR_BYTE_SHIFTED(1)
    ) fetch_inst_command_inst (.clk, .rst);

    std_stream_intf #(
        .T(gecko_pc_t)
    ) fetch_pc_command_inst (.clk, .rst);

    gecko_fetch gecko_fetch_inst (
        .clk, .rst,

        .jump_command_valid(jump_command_valid),
        .jump_command_in(jump_command),

        .inst_command_out(fetch_inst_command_inst),
        .pc_command_out(fetch_pc_command_inst)
    );

    /*
     * INSTRUCTION CACHE
     */



endmodule
