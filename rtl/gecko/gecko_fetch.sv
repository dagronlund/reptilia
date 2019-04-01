`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

module gecko_fetch
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#(
    parameter gecko_pc_t START_ADDR = 'b0,
    // How big is the branch-prediction table
    parameter int BRANCH_ADDR_WIDTH = 7
)(
    input logic clk, rst,

    std_stream_intf.in jump_command, // gecko_jump_operation_t

    std_stream_intf.out instruction_command, // gecko_instruction_operation_t
    std_mem_intf.out instruction_request
);

    localparam BRANCH_HISTORY_LENGTH = 2**BRANCH_ADDR_WIDTH;
    localparam BRANCH_HISTORY_WIDTH = $bits(gecko_prediction_history_t);
    localparam BRANCH_TAG_WIDTH = $bits(gecko_pc_t) - BRANCH_ADDR_WIDTH - 2;

    typedef logic [BRANCH_ADDR_WIDTH-1:0] gecko_fetch_table_addr_t;
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
        TAKEN: return branched ? STRONG_TAKEN : NOT_TAKEN;
        NOT_TAKEN: return branched ? TAKEN : STRONG_NOT_TAKEN;
        STRONG_NOT_TAKEN: return branched ? NOT_TAKEN : STRONG_NOT_TAKEN;
        endcase
    endfunction

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

    logic [BRANCH_HISTORY_LENGTH-1:0] branch_table_valid, next_branch_table_valid;
    gecko_instruction_operation_t next_inst_cmd;

    always_ff @(posedge clk) begin
        if (rst) begin
            instruction_command.payload <= '{
                pc: (START_ADDR-4),
                next_pc: (START_ADDR),
                default: 'b0
            };
        end else begin
            instruction_command.payload.pc <= next_inst_cmd.pc;
            instruction_command.payload.jump_flag <= next_inst_cmd.jump_flag;
            instruction_command.payload.prediction <= next_inst_cmd.prediction;
        end
        if (rst) begin
            branch_table_valid <= 'b0;
        end else if (jump_command.valid) begin
            branch_table_valid <= next_branch_table_valid;
        end
    end

    logic branch_table_write_enable;
    gecko_fetch_table_addr_t branch_table_write_addr;
    gecko_fetch_table_entry_t branch_table_write_data;

    gecko_fetch_table_addr_t branch_table_read_addr;
    gecko_fetch_table_entry_t branch_table_read_data;

    std_distributed_ram #(
        .DATA_WIDTH(BRANCH_ENTRY_WIDTH),
        .ADDR_WIDTH(BRANCH_ADDR_WIDTH),
        .READ_PORTS(1)
    ) branch_table_inst (
        .clk, .rst,

        .write_enable({BRANCH_ENTRY_WIDTH{branch_table_write_enable}}),
        .write_addr(branch_table_write_addr),
        .write_data_in(branch_table_write_data),

        .read_addr('{branch_table_read_addr}),
        .read_data_out('{branch_table_read_data})
    );

    always_comb begin
        automatic logic branch_table_hit;
        automatic gecko_pc_t current_pc, next_pc, default_next_pc;
        automatic gecko_instruction_operation_t inst_cmd;
        automatic gecko_jump_operation_t jump_op;

        inst_cmd = gecko_instruction_operation_t'(instruction_command.payload);
        jump_op = gecko_jump_operation_t'(jump_command.payload);
        current_pc = inst_cmd.pc;

        // Default Values
        jump_command.ready = 'b1;
        instruction_request.read_enable = 'b1;
        instruction_request.write_enable = 'b0;
        instruction_request.data = 'b0;
        instruction_request.addr = current_pc;

        // Default instruction increment
        default_next_pc = current_pc + 'd4;

        // Read from branch table
        branch_table_read_addr = current_pc[(BRANCH_ADDR_WIDTH+2-1):2];

        // Determine if entry exists in branch table
        branch_table_hit = branch_table_valid[branch_table_read_addr] && 
                branch_table_read_data.tag == current_pc[31:BRANCH_ADDR_WIDTH+2];

        // Take branch if it is a jump instruction or branch predicted take
        if (branch_table_hit && (branch_table_read_data.jump_instruction ||
                predict_branch(branch_table_read_data.history))) begin
            next_pc = branch_table_read_data.predicted_next;
        end else begin
            next_pc = default_next_pc;
        end

        // Set proper outputs
        next_inst_cmd.pc = next_pc;
        next_inst_cmd.jump_flag = inst_cmd.jump_flag;
        next_inst_cmd.prediction.miss = !branch_table_hit;
        next_inst_cmd.prediction.history = branch_table_read_data.history;

        // DANGER: This only works since the instruction command is immediately buffered
        //         by the next stage without any logic in front
        instruction_command.payload.next_pc = next_pc;

        // Gate flow-control logic with clock-enable
        if (!enable) begin
            next_inst_cmd = inst_cmd;
        end

        // If a jump command actually needs to update the pc
        if (jump_command.valid && jump_op.update_pc) begin
            next_inst_cmd.pc = jump_op.actual_next_pc;
            next_inst_cmd.jump_flag = next_inst_cmd.jump_flag + 'b1;
        end

        // Update branch table when a jump command is recieved
        branch_table_write_enable = jump_command.valid;
        branch_table_write_addr = jump_op.current_pc[(BRANCH_ADDR_WIDTH+2-1):2];
        branch_table_write_data.predicted_next = jump_op.actual_next_pc;
        branch_table_write_data.tag = jump_op.current_pc[31:BRANCH_ADDR_WIDTH+2];
        branch_table_write_data.jump_instruction = jump_op.jumped;
        if (jump_op.prediction.miss) begin
            branch_table_write_data.history = jump_op.branched ? DEFAULT_TAKEN_HISTORY : DEFAULT_NOT_TAKEN_HISTORY;
        end else begin
            branch_table_write_data.history = update_history(jump_op.prediction.history, jump_op.branched);
        end
        // Clock gated by jump_command.valid
        next_branch_table_valid = branch_table_valid | (1'b1 << branch_table_write_addr);
    end

endmodule
