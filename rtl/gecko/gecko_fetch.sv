//!import std/std_pkg
//!import stream/stream_pkg
//!import riscv/riscv_pkg
//!import riscv/riscv32_pkg
//!import riscv/riscv32i_pkg
//!import gecko/gecko_pkg

`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "../mem/mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

module gecko_fetch
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import gecko_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,
    parameter gecko_pc_t START_ADDR = 'b0,
    parameter logic ENABLE_BRANCH_PREDICTOR = 1,
    // How big is the branch-prediction table
    parameter int BRANCH_PREDICTOR_ADDR_WIDTH = 5
)(
    input wire clk, 
    input wire rst,

    stream_intf.in jump_command, // gecko_jump_operation_t

    stream_intf.out instruction_command, // gecko_instruction_operation_t
    mem_intf.out instruction_request
);

    localparam BRANCH_HISTORY_LENGTH = 2**BRANCH_PREDICTOR_ADDR_WIDTH;
    localparam BRANCH_HISTORY_WIDTH = $bits(gecko_prediction_history_t);
    localparam BRANCH_TAG_WIDTH = $bits(gecko_pc_t) - BRANCH_PREDICTOR_ADDR_WIDTH - 2;

    typedef logic [BRANCH_PREDICTOR_ADDR_WIDTH-1:0] gecko_fetch_table_addr_t;
    typedef logic [BRANCH_TAG_WIDTH-1:0] gecko_fetch_tag_t;

    typedef struct packed {
        gecko_pc_t predicted_next;
        gecko_fetch_tag_t tag;
        logic jump_instruction;
        gecko_prediction_history_t history;
    } gecko_fetch_table_entry_t;

    localparam BRANCH_ENTRY_WIDTH = $bits(gecko_fetch_table_entry_t);

    typedef enum logic [1:0] {
        STRONG_TAKEN = 'h0,
        TAKEN = 'h1,
        NOT_TAKEN = 'h2,
        STRONG_NOT_TAKEN = 'h3
    } branch_prediction_state_t;

    parameter gecko_prediction_history_t DEFAULT_TAKEN_HISTORY = TAKEN;
    parameter gecko_prediction_history_t DEFAULT_NOT_TAKEN_HISTORY = NOT_TAKEN;

    function automatic logic predict_branch(
            input gecko_prediction_history_t history
    );
        return history[1:0] == STRONG_TAKEN || history[1:0] == TAKEN;
    endfunction

    function automatic gecko_prediction_history_t update_history(
            input gecko_prediction_history_t history,
            input logic branched
    );
        case (history[1:0])
        STRONG_TAKEN: return branched ? STRONG_TAKEN : TAKEN;
        TAKEN: return branched ? STRONG_TAKEN : STRONG_NOT_TAKEN;
        NOT_TAKEN: return branched ? STRONG_TAKEN : STRONG_NOT_TAKEN;
        STRONG_NOT_TAKEN: return branched ? NOT_TAKEN : STRONG_NOT_TAKEN;
        endcase
    endfunction

    logic enable, produce, ready_input_null;

    stream_intf #(.T(gecko_instruction_operation_t)) next_instruction_command (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) next_instruction_request (.clk, .rst);

    stream_controller #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(2)
    ) stream_controller_inst (
        .clk, .rst,

        .valid_input('b1),
        .ready_input(ready_input_null),

        .valid_output({next_instruction_command.valid, next_instruction_request.valid}),
        .ready_output({next_instruction_command.ready, next_instruction_request.ready}),

        .consume('b1),
        .produce({produce, produce}),

        .enable
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(gecko_instruction_operation_t)
    ) instruction_command_stage_inst (
        .clk, .rst,
        .stream_in(next_instruction_command), .stream_out(instruction_command)
    );

    mem_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE)
    ) instruction_request_stage_inst (
        .clk, .rst,
        .mem_in(next_instruction_request), .mem_out(instruction_request)
    );

    logic branch_table_write_enable;
    gecko_fetch_table_addr_t branch_table_write_addr;
    gecko_fetch_table_entry_t branch_table_write_data;

    gecko_fetch_table_addr_t branch_table_read_addr;
    gecko_fetch_table_entry_t branch_table_read_data;

    logic branch_table_reset_done;

    mem_combinational #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .DATA_WIDTH(BRANCH_ENTRY_WIDTH),
        .ADDR_WIDTH(BRANCH_PREDICTOR_ADDR_WIDTH),
        .READ_PORTS(1),
        .AUTO_RESET(1)
    ) register_status_counters_inst (
        .clk, .rst,

        .write_enable({BRANCH_ENTRY_WIDTH{branch_table_write_enable}}),
        .write_addr(branch_table_write_addr),
        .write_data_in(branch_table_write_data),

        .read_addr('{branch_table_read_addr}),
        .read_data_out('{branch_table_read_data}),

        .reset_done(branch_table_reset_done)
    );

    logic enable_fetch_state;

    gecko_pc_t current_pc, next_pc;
    gecko_jump_flag_t current_jump_flag, next_jump_flag;
    logic halt_flag;
    logic [BRANCH_HISTORY_LENGTH-1:0] current_branch_table_valid, next_branch_table_valid;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(gecko_pc_t),
        .RESET_VECTOR(START_ADDR)
    ) pc_register_inst (
        .clk, .rst,
        .enable(enable_fetch_state),
        .next(next_pc),
        .value(current_pc)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(gecko_jump_flag_t),
        .RESET_VECTOR('b0)
    ) prediction_register_inst (
        .clk, .rst,
        .enable(enable_fetch_state),
        .next(next_jump_flag),
        .value(current_jump_flag)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic),
        .RESET_VECTOR('b0)
    ) halt_flag_register_inst (
        .clk, .rst,
        .enable(branch_table_write_enable),
        .next(jump_command.payload.halt || halt_flag),
        .value(halt_flag)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic [BRANCH_HISTORY_LENGTH-1:0]),
        .RESET_VECTOR('b0)
    ) branch_table_valid_register_inst (
        .clk, .rst,
        .enable(branch_table_write_enable),
        .next(next_branch_table_valid),
        .value(current_branch_table_valid)
    );

    always_comb begin
        automatic logic branch_table_hit;

        produce = !halt_flag && branch_table_reset_done;
        enable_fetch_state = (produce && enable) || (jump_command.valid && jump_command.payload.update_pc);

        // Read from branch table
        branch_table_read_addr = current_pc[(BRANCH_PREDICTOR_ADDR_WIDTH+2-1):2];

        // Determine if entry exists in branch table
        branch_table_hit = current_branch_table_valid[branch_table_read_addr] && 
                branch_table_read_data.tag == current_pc[31:BRANCH_PREDICTOR_ADDR_WIDTH+2];

        // Take branch if it is a jump instruction or branch predicted take
        if (ENABLE_BRANCH_PREDICTOR && branch_table_hit && 
                (branch_table_read_data.jump_instruction ||
                predict_branch(branch_table_read_data.history))) begin
            next_pc = branch_table_read_data.predicted_next;
        end else begin
            next_pc = current_pc + 'd4;
        end

        // Override next_pc decision if a jump command comes in
        if (jump_command.valid && jump_command.payload.update_pc) begin
            next_pc = jump_command.payload.actual_next_pc;
            next_jump_flag = current_jump_flag + 'b1;
        end

        // Pass outputs to memory and command streams
        next_instruction_command.payload.pc = current_pc;
        next_instruction_command.payload.next_pc = next_pc;
        next_instruction_command.payload.jump_flag = current_jump_flag;
        next_instruction_command.payload.prediction.miss = !branch_table_hit;
        next_instruction_command.payload.prediction.history = branch_table_read_data.history;

        next_instruction_request.read_enable = 'b1;
        next_instruction_request.write_enable = 'b0;
        next_instruction_request.addr = current_pc;
        next_instruction_request.data = 'b0;

        // Update branch prediction table from jump commands (always accepts)
        branch_table_write_enable = jump_command.valid;
        branch_table_write_addr = jump_command.payload.current_pc[(BRANCH_PREDICTOR_ADDR_WIDTH+2-1):2];
        branch_table_write_data.predicted_next = jump_command.payload.actual_next_pc;
        branch_table_write_data.tag = jump_command.payload.current_pc[31:BRANCH_PREDICTOR_ADDR_WIDTH+2];
        branch_table_write_data.jump_instruction = jump_command.payload.jumped;
        if (jump_command.payload.prediction.miss) begin
            branch_table_write_data.history = jump_command.payload.branched ? 
                    DEFAULT_TAKEN_HISTORY : DEFAULT_NOT_TAKEN_HISTORY;
        end else begin
            branch_table_write_data.history = update_history(jump_command.payload.prediction.history, 
                    jump_command.payload.branched);
        end

        // Updates branch prediction valid flags (always accepts)
        next_branch_table_valid = current_branch_table_valid;
        next_branch_table_valid[branch_table_write_addr] = 'b1;
    end

endmodule
