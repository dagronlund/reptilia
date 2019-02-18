`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

module gecko_execute
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
(
    // Recieve jump commands
    input logic                jump_command_valid,
    input gecko_jump_command_t jump_command_in,

    // Recieve register writeback commands
    input logic                register_writeback_valid,
    input gecko_reg_result_t   register_writeback_in,

    // Recieve instruction memory and program counter
    std_mem_intf.in inst_result_in,
    std_stream_intf.in pc_command_in,

    // Send commands to execution units
    std_mem_intf.out data_command_out,
    std_stream_intf.out csr_command_out,
    std_stream_intf.out alu_command_out
);

    typedef enum logic [1:0] {
        GECKO_EXECUTE_RESET = 2'b00,
        GECKO_EXECUTE_NORMAL = 2'b01
    } gecko_execute_state_t;

    logic consume;
    logic produce_data, produce_csr, produce_alu;
    logic enable, data_enable, csr_enable, alu_enable;

    // Flow Controller
    std_flow #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(3)
    ) std_flow_inst (
        .clk, .rst,

        .valid_input({inst_result_in.valid, pc_command_in.valid}),
        .ready_input({inst_result_in.ready, pc_command_in.ready}),

        .valid_output({data_command_out.valid, csr_command_out.valid, alu_command_out.valid}),
        .ready_output({data_command_out.ready, csr_command_out.ready, alu_command_out.ready}),

        // Always consumes both inputs or not
        .consume({consume, consume}),
        .produce({produce_data, produce_csr, produce_alu}),

        .enable,
        .enable_output({data_enable, csr_enable, alu_enable})
    );

    logic state_enable;
    gecko_execute_state_t state, next_state;

    // Current state register
    std_register #(
        .WIDTH($size(gecko_execute_state_t)),
        .RESET(GECKO_EXECUTE_RESET)
    ) state_register_inst (
        .clk, .rst,
        .enable(state_enable),
        .next_value(next_state), .value(state)
    );

    logic reset_counter_enable;
    rv32_reg_addr_t reset_counter, next_reset_counter;

    // Reset counter register
    std_register #(
        .WIDTH($size(rv32_reg_addr_t)),
        .RESET('b0)
    ) reset_counter_register_inst (
        .clk, .rst,
        .enable(reset_counter_enable),
        .next_value(next_reset_counter), .value(reset_counter)
    );

    logic register_write_enable;
    rv32_reg_addr_t register_write_addr;
    rv32_reg_value_t register_write_value;

    // Register File
    std_distributed_ram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(5),
        .READ_PORTS(2)
    ) register_file_inst (
        .clk, .rst,

        // Always write to all bits in register
        .write_enable({32{register_write_enable}}),
        .write_addr(register_write_addr),
        .write_data_in(register_write_value),

        .read_addr('{}),
        .read_data_out('{})
    );


    always_comb begin
        // Default values
        state_enable = 'b0;
        next_state = state;
        reset_counter_enable = 'b0;
        next_reset_counter = reset_counter + 'b1;
        
        register_write_enable = 'b0;
        register_write_addr = reset_counter;
        register_write_value = 'b0;

        case (state)
        GECKO_EXECUTE_RESET: begin
            reset_counter_enable = 'b1;
            if (reset_counter == 'd31) begin
                state_enable = 'b1;
                next_state = GECKO_EXECUTE_NORMAL;
            end
        end
        GECKO_EXECUTE_NORMAL: begin

        end
        default: begin

        end
        endcase

        // Determine register writing logic
        if (state == GECKO_EXECUTE_RESET) begin
            register_write_enable = 'b1;
        end else if (register_writeback_valid) begin
            // Make sure to not write to r0
            register_write_enable = (register_writeback_in.rd_addr != 'b0);
            register_write_addr = register_writeback_in.rd_addr;
            register_write_value = register_writeback_in.rd_value;
        end

    end

endmodule
