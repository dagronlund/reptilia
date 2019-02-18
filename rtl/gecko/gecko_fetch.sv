`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

// TODO: Add branch prediction
module gecko_fetch
    import gecko::*;
(
    input logic clk, rst,

    input logic                jump_command_valid,
    input gecko_jump_command_t jump_command_in,

    std_mem_intf.out inst_command_out,
    std_stream_intf.out pc_command_out
);

    logic enable;
    std_flow #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(2)
    ) std_flow_inst (
        .clk, .rst,

        // No actual input streams
        .valid_input('b1),

        .valid_output({inst_command_out.valid, pc_command_out.valid}),
        .ready_output({inst_command_out.ready, pc_command_out.ready}),

        // No actual input streams
        .consume('b1),
        .produce('b11),

        // Really only generating a single output stream
        .enable(enable)
    );

    // Store program counter
    gecko_pc_t pc, next_pc;
    std_register #(
        .WIDTH($size(gecko_pc_t))
    ) pc_register_inst (
        .clk, .rst, .enable,
        .next_value(next_pc), .value(pc)
    );

    // Store jump flag
    gecko_jump_flag_t jump_flag, next_jump_flag;
    std_register #(
        .WIDTH($size(gecko_jump_flag_t))
    ) jump_flag_register_inst (
        .clk, .rst, .enable,
        .next_value(next_jump_flag), .value(jump_flag)
    );

    always_comb begin
        automatic gecko_pc_command_t pc_command;
        automatic gecko_pc_t addr_current, addr_step;

        // Work out next pc
        addr_current = pc;
        addr_step = 'd4;
        if (jump_command_valid) begin
            if (jump_command_in.absolute_jump) begin
                addr_current = jump_command_in.absolute_addr;
            end
            if (jump_command_in.relative_jump) begin
                addr_step = jump_command_in.relative_addr;
            end
        end
        next_pc = addr_current + addr_step;

        // Work out next jump flag
        if (jump_command_valid) begin
            next_jump_flag = jump_flag + 'b1;
        end else begin
            next_jump_flag = jump_flag;
        end

        // Assign outputs
        pc_command.pc = pc;
        pc_command.jump_flag = jump_flag;
        pc_command_out.payload = pc_command;

        inst_command_out.read_enable = 'b1;
        inst_command_out.write_enable = 'b0;
        inst_command_out.addr = pc;
        inst_command_out.data = 'b0;
    end

endmodule
