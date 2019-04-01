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

    std_stream_intf #(.T(gecko_jump_operation_t)) jump_command (.clk, .rst);
    std_stream_intf #(.T(gecko_instruction_operation_t)) instruction_command (.clk, .rst);

    std_mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .ADDR_BYTE_SHIFTED(1)
    ) instruction_request (.clk, .rst);

    gecko_fetch #(
        .START_ADDR('b0),
        .BRANCH_ADDR_WIDTH(5)
    ) gecko_fetch_inst (
        .clk, .rst,

        .jump_command,

        .instruction_command,
        .instruction_request
    );

    gecko_instruction_operation_t inst_op_temp;
    logic [31:0] data_temp, addr_temp;
    logic [3:0] write_enable_temp;
    logic read_enable_temp;

    initial begin
        jump_command.valid = 'b0;
        instruction_command.ready = 'b0;
        instruction_request.ready = 'b0;
        while (rst) @ (posedge clk);

        fork
        begin
            @ (posedge clk);
            @ (posedge clk);
            @ (posedge clk);
            @ (posedge clk);
            jump_command.send('{
                update_pc: 'b0,
                branched: 'b1,
                jumped: 'b0,
                current_pc: 'b0,
                actual_next_pc: 'd4,
                prediction: '{
                    miss: 'b1,
                    history: 'd5
                }
            });
            @ (posedge clk);
            jump_command.send('{
                update_pc: 'b1,
                branched: 'b1,
                jumped: 'b0,
                current_pc: 'b0,
                actual_next_pc: 'd4,
                prediction: '{
                    miss: 'b0,
                    history: 'd5
                }
            });
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
