`timescale 1ns/1ps

`include "../lib/rv_util.svh"
`include "../lib/rv_mem.svh"

/*
 * Implements a single cycle memory with two input streams for commands and
 * two output ports for the results of those commands. This will usually map 
 * to a block memory device in the FPGA, and adding a single register stage
 * immediately after this will allow for the block memory output register to
 * be used.
 */
module rv_memory_double #(
    parameter WRITE_PROPAGATE = 0 // Writes generate a result as well
)(
    input logic clk, rst,
    rv_mem.in command0, // Inbound Commands
    rv_mem.out result0, // Outbound Results
    rv_mem.in command1, // Inbound Commands
    rv_mem.out result1, // Outbound Results
);

    `STATIC_ASSERT(command0.DATA_WIDTH == result0.DATA_WIDTH)
    `STATIC_ASSERT(command0.DATA_WIDTH == command1.DATA_WIDTH)
    `STATIC_ASSERT(command0.DATA_WIDTH == result1.DATA_WIDTH)

    `STATIC_ASSERT(command0.ADDR_WIDTH == result0.ADDR_WIDTH)
    `STATIC_ASSERT(command0.ADDR_WIDTH == command1.ADDR_WIDTH)
    `STATIC_ASSERT(command0.ADDR_WIDTH == result1.ADDR_WIDTH)

    parameter DATA_WIDTH = command0.DATA_WIDTH;
    parameter ADDR_WIDTH = command0.ADDR_WIDTH;
    parameter DATA_LENGTH = 2**ADDR_WIDTH;

    logic enable0, data_valid0;
    logic enable1, data_valid1;
    
    logic [DATA_WIDTH-1:0] data [DATA_LENGTH];

    rv_seq_flow_controller #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) flow_controller0 (
        .clk, .rst, .enable(enable0),
        .inputs_valid({command0.valid}), 
        .inputs_ready({command0.ready}),
        .inputs_block({1'b1}),

        .outputs_valid({result0.valid}),
        .outputs_ready({result0.ready}),
        .outputs_block({data_valid0})
    );

    rv_seq_flow_controller #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) flow_controller1 (
        .clk, .rst, .enable(enable1),
        .inputs_valid({command1.valid}), 
        .inputs_ready({command1.ready}),
        .inputs_block({1'b1}),

        .outputs_valid({result1.valid}),
        .outputs_ready({result1.ready}),
        .outputs_block({data_valid1})
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            data_valid0 <= 1'b0;
        end else if (enable0) begin
            if (command0.op == RV_MEM_READ) begin
                data_valid0 <= 1'b1;
            end else begin // write
                data[command0.addr] <= command0.data;
                data_valid0 <= (WRITE_PROPAGATE != 0);
            end

            result0.data <= data[command0.addr];
            result0.op <= command0.op;
            result0.addr <= command0.addr;
        end

        if(rst) begin
            data_valid1 <= 1'b0;
        end else if (enable1) begin
            if (command1.op == RV_MEM_READ) begin
                data_valid1 <= 1'b1;
            end else begin // write
                data[command1.addr] <= command1.data;
                data_valid1 <= (WRITE_PROPAGATE != 0);
            end

            result1.data <= data[command1.addr];
            result1.op <= command1.op;
            result1.addr <= command1.addr;
        end
    end

endmodule
