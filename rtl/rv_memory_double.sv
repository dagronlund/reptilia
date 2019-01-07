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
    rv_mem_intf.in command0, // Inbound Commands
    rv_mem_intf.out result0, // Outbound Results
    rv_mem_intf.in command1, // Inbound Commands
    rv_mem_intf.out result1 // Outbound Results
);

    import rv_mem::*;

    `STATIC_ASSERT($bits(command0.data) == $bits(result0.data))
    `STATIC_ASSERT($bits(command0.data) == $bits(command1.data))
    `STATIC_ASSERT($bits(command0.data) == $bits(result1.data))

    `STATIC_ASSERT($bits(command0.addr) == $bits(result0.addr))
    `STATIC_ASSERT($bits(command0.addr) == $bits(command1.addr))
    `STATIC_ASSERT($bits(command0.addr) == $bits(result1.addr))

    localparam DATA_WIDTH = $bits(command0.data);
    localparam ADDR_WIDTH = $bits(command0.addr);
    localparam DATA_LENGTH = 2**ADDR_WIDTH;

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

    /*
    Note:
    Using four seperate always_ff blocks is super important for Vivado to 
    recognize that this is a true-dual-port block-ram, without a weird output
    register stage.

    A single always_ff block will imply some priority when writing to the
    block-ram at the same time and place, which won't synthesize.
    */

    always_ff @ (posedge clk) begin
        if (rst) begin
            data_valid0 <= 1'b0;
        end else if (enable0) begin
            if (command0.op == RV_MEM_READ) begin
                data_valid0 <= 1'b1;
            end else begin // write
                data_valid0 <= (WRITE_PROPAGATE != 0);
            end

            result0.op <= command0.op;
            result0.addr <= command0.addr;
        end
    end

    always_ff @ (posedge clk) begin
        if (!rst && enable0) begin
            if (command0.op == RV_MEM_WRITE) begin
                data[command0.addr] <= command0.data;
            end
            result0.data <= data[command0.addr];
        end
    end

    always_ff @ (posedge clk) begin
        if (rst) begin
            data_valid1 <= 1'b0;
        end else if (enable1) begin
            if (command1.op == RV_MEM_READ) begin
                data_valid1 <= 1'b1;
            end else begin // write
                data_valid1 <= (WRITE_PROPAGATE != 0);
            end

            result1.op <= command1.op;
            result1.addr <= command1.addr;
        end
    end

    always_ff @ (posedge clk) begin
        if (!rst && enable1) begin
            if (command1.op == RV_MEM_WRITE) begin
                data[command1.addr] <= command1.data;
            end
            result1.data <= data[command1.addr];
        end
    end

endmodule
