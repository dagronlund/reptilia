`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

// TODO: Add branch prediction
module gecko_fetch
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
(
    input logic clk, rst,

    std_stream_intf.in jump_command, // gecko_jump_command_t
    std_stream_intf.in branch_command, // gecko_branch_command_t

    std_stream_intf.out instruction_command, // gecko_instruction_operation_t
    std_mem_intf.out instruction_request
);

    logic enable;
    logic ready_input_null;
    logic [1:0] enable_output_null;
    std_flow #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(2)
    ) std_flow_inst (
        .clk, .rst,

        .valid_input('b1),
        .ready_input(ready_input_null),

        .valid_output({instruction_command.valid, instruction_request.valid}),
        .ready_output({instruction_command.ready, instruction_request.ready}),

        .consume('b1),
        .produce('b11),

        .enable(enable),
        .enable_output(enable_output_null)
    );

    gecko_instruction_operation_t next_instruction_command;

    always_ff @(posedge clk) begin
        if (rst) begin
            instruction_command.payload <= '{pc: (0-4), default: 'b0};
        end else begin
            instruction_command.payload <= next_instruction_command;
        end
    end

    always_comb begin
        automatic gecko_instruction_operation_t current_instruction_op;
        automatic gecko_jump_command_t jump_cmd_in;
        automatic gecko_branch_command_t branch_cmd_in;
        automatic gecko_pc_t next_base, next_step;
        automatic gecko_jump_flag_t next_jump_flag;

        current_instruction_op = gecko_instruction_operation_t'(instruction_command.payload);
        jump_cmd_in = gecko_jump_command_t'(jump_command.payload);
        branch_cmd_in = gecko_branch_command_t'(branch_command.payload);

        branch_command.ready = 'b1;
        jump_command.ready = 'b1;

        instruction_request.read_enable = 'b1;
        instruction_request.write_enable = 'b0;
        instruction_request.data = 'b0;
        instruction_request.addr = current_instruction_op.pc;

        next_instruction_command = current_instruction_op;

        next_base = current_instruction_op.pc;
        next_step = 'd4;

        if (!enable) begin
            next_instruction_command = current_instruction_op;
            next_base = current_instruction_op.pc;
            next_step = 'b0;
        end

        if (jump_command.valid) begin
            next_base = jump_cmd_in.base_addr;
            next_step = jump_cmd_in.relative_addr;
            next_instruction_command.jump_flag = next_instruction_command.jump_flag + 'b1;
        end else if (branch_command.valid && branch_cmd_in.branch) begin
            next_base = branch_cmd_in.base_addr;
            next_step = branch_cmd_in.relative_addr;
            next_instruction_command.jump_flag = next_instruction_command.jump_flag + 'b1;
        end

        next_instruction_command.pc = next_base + next_step;
    end

endmodule
