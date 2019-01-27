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
 
module rv_memory_single #(
    parameter WRITE_RESPOND = 0 // Writes generate a result as well
)(
    input logic clk, rst,
    rv_mem_intf.in command, // Inbound Commands
    rv_mem_intf.out result // Outbound Results
);

    import rv_mem::*;

    `STATIC_ASSERT($bits(command.data) == $bits(result.data))
    `STATIC_ASSERT($bits(command.addr) == $bits(result.addr))

    localparam DATA_WIDTH = $bits(command.data);
    localparam ADDR_WIDTH = $bits(command.addr);
    localparam DATA_LENGTH = 2**ADDR_WIDTH;

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

    rv_memory_single_port #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) rv_memory_single_port_inst (
        .clk, .rst,

        // Memory values do not get reset on the device after startup,
        // so avoid writing to them during normal reset
        .enable(!rst && enable),
        .write_enable(command.op == RV_MEM_WRITE),
        .addr_in(command.addr),
        .data_in(command.data),
        .data_out(result.data)
    );

    always_ff @ (posedge clk) begin
        if (rst) begin
            data_valid <= 1'b0;
        end else begin
            if (enable) begin
                data_valid <= (command.op == RV_MEM_READ) ? 
                        1'b1 : (WRITE_RESPOND != 0);
                result.op <= command.op;
                result.addr <= command.addr;
            end
        end
    end

endmodule

module rv_memory_single_tb ();

    import rv_mem::*;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    rv_mem_intf mem_command(.*);
    rv_mem_intf mem_result(.*);

    rv_memory_single #(
        .WRITE_RESPOND(0)
    ) mem_inst0 (
        .clk, .rst,
        .command(mem_command),
        .result(mem_result)
    );

    initial begin
        mem_command.valid = 0;
        while (rst) @ (posedge clk);

        @ (posedge clk);
        mem_command.send(RV_MEM_READ, 'b0, 'b0);

        @ (posedge clk);
        mem_command.send(RV_MEM_WRITE, 'b0, 'b1);

        @ (posedge clk);
        mem_command.send(RV_MEM_READ, 'b0, 'b0);

        $display("Sends Complete");
    end

    rv_memory_op result_op;
    logic [9:0] result_addr;
    logic [31:0] result_data;

    initial begin
        mem_result.ready = 0;
        while (rst) @ (posedge clk);

        @ (posedge clk);
        mem_result.recv(result_op, result_addr, result_data);

        @ (posedge clk);
        mem_result.recv(result_op, result_addr, result_data);

        $display("Recvs Complete");
        $finish;
    end

endmodule
