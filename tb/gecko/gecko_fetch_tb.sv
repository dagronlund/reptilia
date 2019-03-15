`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

module gecko_fetch_tb
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#()();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    std_stream_intf #(.T(gecko_jump_command_t)) jump_command (.clk, .rst);
    std_stream_intf #(.T(gecko_branch_command_t)) branch_command (.clk, .rst);
    std_stream_intf #(.T(gecko_instruction_operation_t)) instruction_command (.clk, .rst);

    std_mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .ADDR_BYTE_SHIFTED(1)
    ) instruction_request (.clk, .rst);

    gecko_fetch gecko_fetch_inst(
        .clk, .rst,

        .jump_command,
        .branch_command,
        .instruction_command,
        .instruction_request
    );

    gecko_instruction_operation_t inst_op_temp;
    logic [31:0] data_temp, addr_temp;
    logic [3:0] write_enable_temp;
    logic read_enable_temp;

    initial begin
        jump_command.valid = 'b0;
        branch_command.valid = 'b0;
        instruction_command.ready = 'b0;
        instruction_request.ready = 'b0;
        while (rst) @ (posedge clk);

        fork
        begin
            branch_command.send('{branch: 'b0, relative_addr: 'hFF});
            @ (posedge clk);
            branch_command.send('{branch: 'b1, relative_addr: 'hFF});
            @ (posedge clk);
            jump_command.send('{absolute_jump: 'b0, absolute_addr: 'h200, relative_addr: 'hF});
            @ (posedge clk);
            jump_command.send('{absolute_jump: 'b1, absolute_addr: 'h200, relative_addr: 'hF});
        end
        begin
            while (1'b1) begin
                fork
                    instruction_command.recv(inst_op_temp);
                    instruction_request.recv(read_enable_temp, write_enable_temp, addr_temp, data_temp);
                join
            end
        end
        join
    end

endmodule
