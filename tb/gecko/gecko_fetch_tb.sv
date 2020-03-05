`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "../mem/mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

module gecko_fetch_tb
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import gecko_pkg::*;
#()();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    stream_intf #(.T(gecko_jump_operation_t)) jump_command (.clk, .rst);
    stream_intf #(.T(gecko_instruction_operation_t)) instruction_command (.clk, .rst);

    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .ADDR_BYTE_SHIFTED(1)
    ) instruction_request (.clk, .rst);

    gecko_fetch #(
        .START_ADDR('b0),
        .BRANCH_PREDICTOR_TYPE(GECKO_BRANCH_PREDICTOR_LOCAL),
        .BRANCH_PREDICTOR_TARGET_ADDR_WIDTH(5),
        .BRANCH_PREDICTOR_HISTORY_WIDTH(6),
        .BRANCH_PREDICTOR_LOCAL_ADDR_WIDTH(7)
    ) gecko_fetch_inst (
        .clk, .rst,

        .jump_command,

        .instruction_command,
        .instruction_request
    );

    assign jump_command.ready = 'b1;

    gecko_instruction_operation_t inst_op_temp;
    logic [31:0] data_temp, addr_temp;
    logic [3:0] write_enable_temp;
    logic read_enable_temp;
    logic id_temp;

    initial begin
        jump_command.valid = 'b0;
        instruction_command.ready = 'b0;
        instruction_request.ready = 'b0;
        while (rst) @ (posedge clk);

        // Wait for first instruction commands before sending jumps
        fork
            instruction_command.recv(inst_op_temp);
            instruction_request.recv(read_enable_temp, write_enable_temp, addr_temp, data_temp, id_temp);
        join

        fork
        while (1'b1) begin
            fork
                instruction_command.recv(inst_op_temp);
                instruction_request.recv(read_enable_temp, write_enable_temp, addr_temp, data_temp, id_temp);
            join
        end
        begin
            jump_command.send('{
                update_pc: 'b0,
                branched: 'b1,
                jumped: 'b0,
                current_pc: 'd0,
                actual_next_pc: 'd4,
                halt: 'b0,
                prediction: '{
                    miss: 'b1,
                    history: GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_TAKEN
                }
            });
            @ (posedge clk);
            @ (posedge clk);
            jump_command.send('{
                update_pc: 'b1,
                branched: 'b1,
                jumped: 'b0,
                current_pc: 'd8,
                actual_next_pc: 'd4,
                halt: 'b0,
                prediction: '{
                    miss: 'b0,
                    history: GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_NOT_TAKEN
                }
            });
            @ (posedge clk);
            @ (posedge clk);
            jump_command.send('{
                update_pc: 'b1,
                branched: 'b1,
                jumped: 'b0,
                current_pc: 'b0,
                actual_next_pc: 'd4,
                halt: 'b1,
                prediction: '{
                    miss: 'b0,
                    history: GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_TAKEN
                }
            });
        end
        join
    end

endmodule
