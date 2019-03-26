`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"
`include "../../lib/gecko/gecko_decode_util.svh"

/*
 * A round-robin scheduler for producing commands to write back to the
 * register file, one result at a time. The writeback stage also implements
 * the logic necessary to align a value read from memory according to halfword
 * or byte boundaries.
 *
 * A result is not accepted unless its reg_status matches the current
 * reg_status for that result, in order to preserve ordering.
 */
module gecko_writeback
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
    import gecko_decode_util::*;
#()(
    input logic clk, rst,

    std_stream_intf.in execute_result, // gecko_operation_t

    std_stream_intf.in mem_command, // gecko_mem_operation_t
    std_mem_intf.in mem_result,

    std_stream_intf.in system_result, // gecko_operation_t

    std_stream_intf.out writeback_result // gecko_operation_t
);

    typedef enum logic [1:0] {
        GECKO_WRITEBACK_RESET = 2'b00,
        GECKO_WRITEBACK_EXECUTE = 2'b01,
        GECKO_WRITEBACK_MEM = 2'b10,
        GECKO_WRITEBACK_SYSTEM = 2'b11
    } gecko_writeback_state_t;

    logic enable;
    logic produce, consume_execute, consume_mem, consume_system;

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
        .produce({produce}),

        .enable
    );

    logic status_write_enable;
    rv32_reg_addr_t status_write_addr;
    gecko_reg_status_t status_write_value;

    rv32_reg_addr_t execute_status_read_addr, memory_status_read_addr, system_status_read_addr;
    gecko_reg_status_t execute_reg_status, mem_reg_status, system_reg_status;

    // Local Register File Status
    localparam GECKO_REG_STATUS_WIDTH = $size(gecko_reg_status_t);
    std_distributed_ram #(
        .DATA_WIDTH(GECKO_REG_STATUS_WIDTH),
        .ADDR_WIDTH($size(rv32_reg_addr_t)),
        .READ_PORTS(3)
    ) register_file_inst (
        .clk, .rst,

        // Always write to all bits in register, gate with state clock enable
        .write_enable({GECKO_REG_STATUS_WIDTH{status_write_enable && enable}}),
        .write_addr(status_write_addr),
        .write_data_in(status_write_value),

        .read_addr('{execute_status_read_addr, memory_status_read_addr, system_status_read_addr}),
        .read_data_out('{execute_reg_status, mem_reg_status, system_reg_status})
    );

    gecko_writeback_state_t current_state, next_state;
    rv32_reg_addr_t current_counter, next_counter;

    gecko_operation_t next_writeback_result;

    always_ff @(posedge clk) begin
        if(rst) begin
            current_state <= GECKO_WRITEBACK_RESET;
            current_counter <= 'b0;
        end else if (enable) begin
            current_state <= next_state;
            current_counter <= next_counter;
        end

        if (enable) begin
            writeback_result.payload <= next_writeback_result;
        end
    end

    always_comb begin
        automatic logic execute_status_good, memory_status_good, system_status_good;
        automatic gecko_operation_t execute_operation, mem_operation, system_operation;
        automatic gecko_mem_operation_t mem_operation_partial;

        execute_operation = gecko_operation_t'(execute_result.payload);
        system_operation = gecko_operation_t'(system_result.payload);

        mem_operation_partial = gecko_mem_operation_t'(mem_command.payload);
        mem_operation.value = gecko_get_load_result(mem_result.data, 
                mem_operation_partial.offset,
                mem_operation_partial.op);
        mem_operation.addr = mem_operation_partial.addr;
        mem_operation.reg_status = mem_operation_partial.reg_status;
        mem_operation.speculative = 'b0;

        // Read local register file status flags
        execute_status_read_addr = execute_operation.addr;
        memory_status_read_addr = mem_operation.addr;
        system_status_read_addr = system_operation.addr;

        // Find if input matches current ordering to accept it
        execute_status_good = (execute_reg_status == execute_operation.reg_status); 
        memory_status_good = (mem_reg_status == mem_operation.reg_status);
        system_status_good = (system_reg_status == system_operation.reg_status);

        next_state = current_state;
        next_counter = current_counter + 'b1;

        status_write_enable = 'b0;
        status_write_addr = current_counter;
        status_write_value = 'b0;

        consume_execute = 'b0;
        consume_mem = 'b0;
        consume_system = 'b0;

        // Round-Robin input selection
        case (current_state)
        GECKO_WRITEBACK_RESET: begin
            status_write_enable = 'b1;
            if (next_counter == 'b0) begin
                next_state = GECKO_WRITEBACK_EXECUTE;
            end else begin
                next_state = GECKO_WRITEBACK_RESET;
            end
        end
        GECKO_WRITEBACK_EXECUTE: begin
            if (execute_result.valid && execute_status_good) begin
                consume_execute = 'b1;
            end else if (mem_command.valid && mem_result.valid && memory_status_good) begin
                consume_mem = 'b1;
            end else if (system_result.valid && system_status_good) begin
                consume_system = 'b1;
            end
        end
        GECKO_WRITEBACK_MEM: begin
            if (mem_command.valid && mem_result.valid && memory_status_good) begin
                consume_mem = 'b1;
            end else if (system_result.valid && system_status_good) begin
                consume_system = 'b1;
            end else if (execute_result.valid && execute_status_good) begin
                consume_execute = 'b1;
            end
        end
        GECKO_WRITEBACK_SYSTEM: begin
            if (system_result.valid && system_status_good) begin
                consume_system = 'b1;
            end else if (execute_result.valid && execute_status_good) begin
                consume_execute = 'b1;
            end else if (mem_command.valid && mem_result.valid && memory_status_good) begin
                consume_mem = 'b1;
            end
        end
        endcase

        produce = consume_execute || consume_mem || consume_system;

        // Copy selected input to output
        next_writeback_result = execute_operation;
        if (consume_execute) begin
            next_writeback_result = execute_operation;
            next_state = GECKO_WRITEBACK_MEM; 
        end else if (consume_mem) begin
            next_writeback_result = mem_operation;
            next_state = GECKO_WRITEBACK_SYSTEM;
        end else if (consume_system) begin
            next_writeback_result = system_operation;
            next_state = GECKO_WRITEBACK_EXECUTE;
        end

        // Update local register file status
        if (produce) begin
            status_write_enable = 'b1;
            status_write_addr = next_writeback_result.addr;
            status_write_value = next_writeback_result.reg_status + 'b1;
        end
    end

endmodule
