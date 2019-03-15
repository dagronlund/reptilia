`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

module gecko_decode_tb
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#()();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    std_stream_intf #(.T(gecko_instruction_operation_t)) instruction_command (.clk, .rst);
    std_stream_intf #(.T(gecko_system_operation_t)) system_command (.clk, .rst);
    std_stream_intf #(.T(gecko_execute_operation_t)) execute_command (.clk, .rst);
    std_stream_intf #(.T(gecko_jump_command_t)) jump_command (.clk, .rst);

    std_stream_intf #(.T(gecko_branch_signal_t)) branch_signal (.clk, .rst);
    std_stream_intf #(.T(gecko_operation_t)) writeback_result (.clk, .rst);

    std_mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .ADDR_BYTE_SHIFTED(1)
    ) instruction_data (.clk, .rst);

    gecko_decode gecko_decode_inst(
        .clk, .rst,
        .instruction_data, .instruction_command, // in
        .system_command, .execute_command, .jump_command, // out
        .branch_signal, .writeback_result // in
    );

    gecko_execute_operation_t exec_op;

    initial begin
        instruction_data.valid = 'b0;
        instruction_command.valid = 'b0;

        branch_signal.valid = 'b0;
        writeback_result.valid = 'b0;

        system_command.ready = 'b0;
        execute_command.ready = 'b0;
        jump_command.ready = 'b0;
        while (rst) @ (posedge clk);

        fork
        begin
            fork
                instruction_command.send('{pc: 'h0, jump_flag: 'b0});
                instruction_data.send(0, 0, 0, {7'b0, 5'b0, 5'b0, 3'b0, 5'b1, RV32I_OPCODE_OP});
            join
            fork
                instruction_command.send('{pc: 'h4, jump_flag: 'b0});
                instruction_data.send(0, 0, 0, {7'b0, 5'b0, 5'b1, 3'b0, 5'b1, RV32I_OPCODE_OP});
            join
        end
        begin
            execute_command.recv(exec_op);
            execute_command.recv(exec_op);
        end
        join

    end

endmodule
