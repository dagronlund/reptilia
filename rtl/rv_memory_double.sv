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

    rv_memory_double_port #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) rv_memory_double_port_inst (
        .clk, .rst,

        .enable0(!rst && enable0),
        .write_enable0(command0.op == RV_MEM_WRITE),
        .addr_in0(command0.addr),
        .data_in0(command0.data),
        .data_out0(result0.data),

        .enable1(!rst && enable1),
        .write_enable1(command1.op == RV_MEM_WRITE),
        .addr_in1(command1.addr),
        .data_in1(command1.data),
        .data_out1(result1.data)
    );

    always_ff @ (posedge clk) begin
        if (rst) begin
            data_valid0 <= 1'b0;
            data_valid1 <= 1'b0;
        end else begin
            if (enable0) begin
                data_valid0 <= (command0.op == RV_MEM_READ) ? 
                        1'b1 : (WRITE_PROPAGATE != 0);
                result0.op <= command0.op;
                result0.addr <= command0.addr;
            end

            if (enable1) begin
                data_valid1 <= (command1.op == RV_MEM_READ) ? 
                        1'b1 : (WRITE_PROPAGATE != 0);
                result1.op <= command1.op;
                result1.addr <= command1.addr;
            end
        end
    end

endmodule
