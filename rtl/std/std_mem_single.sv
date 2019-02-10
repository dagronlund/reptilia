`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

/*
 * Implements a single cycle memory with an input stream for commands and an 
 * output stream for the results of those commands. Adding a single register 
 * stage immediately after this will allow for the block memory output 
 * register to be used.
 */ 
module std_mem_single #()(
    input logic clk, rst,
    std_mem_intf.in command, // Inbound Commands
    std_mem_intf.out result // Outbound Results
);

    `STATIC_MATCH_MEM(command, result)

    localparam DATA_WIDTH = $bits(command.data);
    localparam ADDR_WIDTH = $bits(command.addr);
    localparam MASK_WIDTH = DATA_WIDTH / 8;
    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    /*
     * Custom flow control is used here since the block RAM cannot be written
     * to without changing the read value.
     */
    logic enable;

    std_block_ram_single #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) std_block_ram_single_inst (
        .clk, .rst,
        // Avoid writing to memory values during reset, since they are not reset
        .enable(!rst && enable),
        .write_enable(command.write_enable),
        .addr_in(command.addr),
        .data_in(command.data),
        .data_out(result.data)
    );

    always_ff @ (posedge clk) begin
        if (rst) begin
            result.valid <= 'b0;
        end else if (enable) begin
            result.valid <= command.read_enable;
        end else if (result.ready) begin
            result.valid <= 'b0;
        end
    end

    always_comb begin
        command.ready = result.ready || !result.valid;
        enable = command.valid && command.ready;
    end

endmodule
