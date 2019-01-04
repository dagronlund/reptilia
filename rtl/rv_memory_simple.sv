`timescale 1ns/1ps

`include "../lib/rv_util.svh"
`include "../lib/rv_mem.svh"

/*
 * Implements a single cycle memory with an input stream for commands and an 
 * output port for the results of those commands. This will usually map to a
 * block memory device in the FPGA, and adding a single register stage
 * immediately after this will allow for the block memory output register to
 * be used.
 */

module rv_memory_simple #(
    parameter WRITE_GENERATE_RESULT = 0 // Writes generate a result as well
)(
    input logic clk, rst,
    rv_mem.in command, // Inbound Commands
    rv_mem.out result // Outbound Results
);

    `STATIC_ASSERT(command.DATA_WIDTH == result.DATA_WIDTH)
    `STATIC_ASSERT(command.ADDR_WIDTH == result.ADDR_WIDTH)

    parameter DATA_WIDTH = command.DATA_WIDTH;
    parameter ADDR_WIDTH = command.ADDR_WIDTH;
    parameter DATA_LENGTH = 2**ADDR_WIDTH;

    logic enable, data_valid;
    logic [DATA_WIDTH-1:0] data [DATA_LENGTH];

    rv_seq_flow_controller #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) flow_controller (
        .clk, .rst, .enable,
        .inputs_valid({command.valid}), 
        .inputs_ready({command.ready}),
        .inputs_block({1'b1}),

        .outputs_valid({result.valid}),
        .outputs_ready({result.ready}),
        .outputs_block({data_valid})
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            data_valid <= 1'b0;
        end else if (enable) begin
            if (command.op == RV_MEM_READ) begin
                data_valid <= 1'b1;
            end else begin // write
                data[command.addr] <= command.data;
                data_valid <= (WRITE_GENERATE_RESULT != 0);
            end

            result.data <= data[command.addr];
            result.op <= command.op;
            result.addr <= command.addr;
        end
    end

endmodule
