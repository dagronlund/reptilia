`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

/*
 * A round-robin scheduler for producing commands to write back to the
 * register file, one result at a time. The writeback stage also implements
 * the logic necessary to align a value read from memory according to halfword
 * or byte boundaries.
 */
module gecko_writeback
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#()(
    input logic clk, rst,

    std_stream_intf.in execute_result, // gecko_operation_t

    std_stream_intf.in mem_command, // gecko_mem_operation_t
    std_mem_intf.in mem_result,

    std_stream_intf.in system_result, // gecko_operation_t

    std_stream_intf.out writeback_result // gecko_operation_t
);

    logic enable;
    logic consume_execute, consume_mem, consume_system;

    // Flow Controller
    std_flow #(
        .NUM_INPUTS(4),
        .NUM_OUTPUTS(1)
    ) std_flow_inst (
        .clk, .rst,

        .valid_input({execute_result.valid, 
                mem_command.valid, 
                mem_result.valid, 
                system_result.valid}),
        .ready_input({execute_result.ready, 
                mem_command.ready, 
                mem_result.ready, 
                system_result.ready}),
        
        .valid_output({writeback_result.valid}),
        .ready_output({writeback_result.ready}),

        .consume({consume_execute, consume_mem, consume_mem, consume_system}),
        .produce({1'b1}),

        .enable
    );

    typedef enum logic [1:0] {
        GECKO_WRITEBACK_EXECUTE = 2'b00,
        GECKO_WRITEBACK_MEM = 2'b01,
        GECKO_WRITEBACK_SYSTEM = 2'b10,
        GECKO_WRITEBACK_UNDEF = 2'b11
    } gecko_writeback_priority_t;

    gecko_writeback_priority_t current_priority, next_priority;

    gecko_operation_t next_writeback_result;

    always_ff @(posedge clk) begin
        if(rst) begin
            current_priority <= GECKO_WRITEBACK_EXECUTE;
        end else if (enable) begin
            current_priority <= next_priority;
        end

        if (enable) begin
            writeback_result.payload <= next_writeback_result;
        end
    end

    always_comb begin
        automatic gecko_operation_t execute_operation, mem_operation, system_operation;
        automatic gecko_mem_operation_t mem_operation_partial;

        execute_operation = gecko_operation_t'(execute_result.payload);
        system_operation = gecko_operation_t'(system_result.payload);

        mem_operation_partial = gecko_mem_operation_t'(mem_command.payload);
        mem_operation.value = gecko_get_load_result(mem_result.data, 
                mem_operation_partial.offset,
                mem_operation_partial.op);
        mem_operation.addr = mem_operation_partial.addr;
        mem_operation.jump_flag = mem_operation_partial.jump_flag;
        mem_operation.speculative = 'b0;

        consume_execute = 'b0;
        consume_mem = 'b0;
        consume_system = 'b0;

        // Round-Robin input selection
        unique case (current_priority)
        GECKO_WRITEBACK_EXECUTE: begin
            if (execute_result.valid) begin
                consume_execute = 'b1;
            end else if (mem_command.valid && mem_result.valid) begin
                consume_mem = 'b1;
            end else if (system_result.valid) begin
                consume_system = 'b1;
            end else begin
                consume_execute = 'b1;
            end
            next_priority = GECKO_WRITEBACK_MEM;
        end
        GECKO_WRITEBACK_MEM: begin
            if (mem_command.valid && mem_result.valid) begin
                consume_mem = 'b1;
            end else if (system_result.valid) begin
                consume_system = 'b1;
            end else if (execute_result.valid) begin
                consume_execute = 'b1;
            end else begin
                consume_mem = 'b1;
            end
            next_priority = GECKO_WRITEBACK_SYSTEM;
        end
        GECKO_WRITEBACK_SYSTEM, GECKO_WRITEBACK_UNDEF: begin
            if (system_result.valid) begin
                consume_system = 'b1;
            end else if (execute_result.valid) begin
                consume_execute = 'b1;
            end else if (mem_command.valid && mem_result.valid) begin
                consume_mem = 'b1;
            end else begin
                consume_system = 'b1;
            end
            next_priority = GECKO_WRITEBACK_EXECUTE;
        end
        endcase

        // Copy selected input to output
        if (consume_execute) begin
            next_writeback_result = execute_operation; 
        end else if (consume_mem) begin
            next_writeback_result = mem_operation;
        end else begin
            next_writeback_result = system_operation;
        end
    end

endmodule
