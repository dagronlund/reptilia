`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/gecko/gecko.svh"
`include "../../lib/gecko/gecko_decode_util.svh"

`else

`include "std_util.svh"
`include "std_mem.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32i.svh"
`include "rv32f.svh"
`include "gecko.svh"
`include "gecko_decode_util.svh"

`endif

/*
 * Decode State:
 *      RESET - Clearing all register values coming out of reset, all writebacks accepted
 *      NORMAL - All branches resolved, normally executing, all writebacks accepted
 *      SPECULATIVE - Only issue register-file instructions, non-speculative writebacks accepted
 *      MISPREDICTED - Normally executing, throw away speculative writebacks
 *
 * Execute Saved Result:
 *      Flag for which register is currently is stored in the execute stage,
 *      should be x0 if no valid result exists.
 *
 * Jump Flag: (Configurable Width)
 *      A counter which is used to keep jumps in sync with the other stages
 *
 * Speculative Counter: (Configurable Width)
 *      A counter for how many instructions were issued while in the speculative state
 *
 * While in the speculative state, the jump counter cannot be incremented until
 * the branch is indicated that it was resolved. Only instructions with
 * side-effects only on the register-file are allowed to pass, and a counter
 * is incremented to indicate how many speculated instructions exist.
 * 
 *      If the branch wasn't taken, then the state moves back to normal, and
 *      the speculative counter is cleared.
 *
 *      If the branch was taken, then the state moves to mispredicted, and the
 *      execute saved result is cleared, and the jump flag is incremented.
 *
 * Incoming instructions are thrown away if their jump flag does not match the
 * current jump flag.
 */
module gecko_decode
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import rv32f::*;
    import gecko::*;
    import gecko_decode_util::*;
#(
    parameter int NUM_FORWARDED = 0,
    parameter int ENABLE_PRINT = 1,
    parameter int OUTPUT_REGISTER_MODE = 2,
    parameter int ENABLE_FLOAT = 1
)(
    input logic clk, rst,

    std_mem_intf.in instruction_result,
    std_stream_intf.in instruction_command, // gecko_instruction_operation_t

    std_stream_intf.out system_command, // gecko_system_operation_t
    std_stream_intf.out execute_command, // gecko_execute_operation_t
    std_stream_intf.out float_command, // gecko_float_operation_t
    std_stream_intf.out ecall_command, // gecko_ecall_operation_t

    // Non-flow Controlled
    std_stream_intf.in jump_command, // gecko_jump_operation_t
    std_stream_intf.in writeback_result, // gecko_operation_t

    // Vivado does not like zero-width arrays
    input gecko_forwarded_t forwarded_results [NUM_FORWARDED == 0 ? 1 : NUM_FORWARDED],

    // output logic faulted_flag, finished_flag,
    output gecko_retired_count_t retired_instructions,

    output logic exit_flag,
    output logic [7:0] exit_code
);

    localparam GECKO_REG_STATUS_WIDTH = $size(gecko_reg_status_t);

    typedef enum logic [1:0] {
        GECKO_DECODE_RESET = 2'b00,
        GECKO_DECODE_NORMAL = 2'b01,
        GECKO_DECODE_SPECULATIVE = 2'b10,
        GECKO_DECODE_EXIT = 2'b11
        // GECKO_DECODE_FAULT = 3'b101
    } gecko_decode_state_t;

    localparam NUM_SPECULATIVE_COUNTERS = 2**$bits(gecko_jump_flag_t);

    typedef struct packed {
        logic mispredicted;
        gecko_speculative_count_t count;
    } gecko_speculative_entry_t;

    typedef gecko_speculative_entry_t [NUM_SPECULATIVE_COUNTERS-1:0] gecko_speculative_status_t;

    typedef struct packed {
        logic consume_instruction, flush_instruction;
        gecko_decode_state_t next_state;
        gecko_speculative_status_t next_speculative_status;
    } gecko_decode_state_transition_t;

    function automatic gecko_decode_state_transition_t get_state_transition(
            input gecko_decode_state_t current_state,
            input rv32_fields_t instruction_fields,
            input rv32_reg_addr_t current_reset_counter,
            input gecko_jump_flag_t current_speculative_flag,
            input gecko_speculative_status_t current_speculative_status,
            input gecko_jump_flag_t instruction_jump_flag, current_jump_flag,
            input logic reg_file_ready
    );
        gecko_decode_state_transition_t result = '{
                next_state: current_state,
                next_speculative_status: current_speculative_status,
                consume_instruction: 'b0,
                flush_instruction: 'b0
        };
        case (current_state)
        GECKO_DECODE_RESET: begin
            if (current_reset_counter == 'd31) begin
                result.next_state = GECKO_DECODE_NORMAL;
            end
        end
        GECKO_DECODE_NORMAL, GECKO_DECODE_SPECULATIVE: begin
            if (instruction_jump_flag != current_jump_flag) begin
                result.consume_instruction = 'b1;
                result.flush_instruction = 'b1;
            end else if (reg_file_ready) begin
                // Only execute non side effect instructions in speculative
                if (current_state == GECKO_DECODE_SPECULATIVE) begin
                    // Make sure speculative counter still has room
                    if (current_speculative_status[current_speculative_flag] != GECKO_SPECULATIVE_FULL) begin
                        if (!is_opcode_side_effects(instruction_fields)) begin
                            result.consume_instruction = 'b1;
                            result.next_speculative_status[current_speculative_flag].count += 
                                    (instruction_fields.rd != 'b0);
                        end
                    end
                end else if (is_opcode_control_flow(instruction_fields)) begin
                    if (current_speculative_status[current_speculative_flag].count == 'b0) begin
                        result.consume_instruction = 'b1;
                        result.next_state = GECKO_DECODE_SPECULATIVE;
                        // Set mispredicted to zero by default
                        result.next_speculative_status[current_speculative_flag].mispredicted = 'b0;
                    end
                end else begin
                    result.consume_instruction = 'b1;
                end
            end
        end
        GECKO_DECODE_EXIT: begin
            result.consume_instruction = 'b1;
            result.flush_instruction = 'b1;
            result.next_state = current_state;
        end
        default: begin
            result.next_state = GECKO_DECODE_RESET;
        end
        endcase
        return result;
    endfunction

    logic consume_instruction;
    logic produce_system, produce_execute, produce_print, produce_float;
    logic enable;

    std_stream_intf #(.T(gecko_system_operation_t)) next_system_command (.clk, .rst);
    std_stream_intf #(.T(gecko_execute_operation_t)) next_execute_command (.clk, .rst);
    std_stream_intf #(.T(gecko_float_operation_t)) next_float_command (.clk, .rst);
    std_stream_intf #(.T(gecko_ecall_operation_t)) next_ecall_command (.clk, .rst);

    std_flow_lite #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(4)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({instruction_result.valid, instruction_command.valid}),
        .ready_input({instruction_result.ready, instruction_command.ready}),

        .valid_output({next_system_command.valid, next_execute_command.valid, next_ecall_command.valid, next_float_command.valid}),
        .ready_output({next_system_command.ready, next_execute_command.ready, next_ecall_command.ready, next_float_command.ready}),

        .consume({consume_instruction, consume_instruction}), 
        .produce({produce_system, produce_execute, produce_print, produce_float}),
        .enable
    );

    std_flow_stage #(
        .T(gecko_system_operation_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) system_operation_output_stage (
        .clk, .rst,
        .stream_in(next_system_command), .stream_out(system_command)
    );

    std_flow_stage #(
        .T(gecko_execute_operation_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) execute_operation_output_stage (
        .clk, .rst,
        .stream_in(next_execute_command), .stream_out(execute_command)
    );

    std_flow_stage #(
        .T(gecko_ecall_operation_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) ecall_command_output_stage (
        .clk, .rst,
        .stream_in(next_ecall_command), .stream_out(ecall_command)
    );

    std_flow_stage #(
        .T(gecko_float_operation_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) float_operation_output_stage (
        .clk, .rst,
        .stream_in(next_float_command), .stream_out(float_command)
    );

    logic faulted, fault_flag;
    logic [7:0] next_exit_code;
    logic next_state_speculative_to_normal;
    gecko_decode_state_t state, next_state;
    rv32_reg_addr_t reset_counter, next_reset_counter;
    logic update_jump_flag;
    gecko_jump_flag_t jump_flag;
    logic clear_speculative_retired_counter;
    gecko_speculative_count_t speculative_retired_counter, next_speculative_retired_counter;
    logic clear_execute_saved;
    rv32_reg_addr_t execute_saved, next_execute_saved;

    logic speculative_status_decrement_enable;
    gecko_jump_flag_t speculative_status_decrement_index;
    logic speculative_status_mispredicted_enable;
    gecko_jump_flag_t speculative_status_mispredicted_index;
    gecko_speculative_status_t speculative_status, next_speculative_status;
    gecko_jump_flag_t speculative_flag, next_speculative_flag;

    logic normal_resolved_instruction;
    gecko_speculative_count_t speculation_resolved_instructions;

    always_ff @(posedge clk) begin
        if(rst) begin
            state <= GECKO_DECODE_RESET;
            reset_counter <= 'b0;
            retired_instructions <= 'b0;
            speculative_flag <= 'b0;
            faulted <= 'b0;
        end else begin
            if (enable) begin
                state <= next_state;
            end else if (state == GECKO_DECODE_SPECULATIVE) begin
                if (next_state_speculative_to_normal) begin
                    state <= GECKO_DECODE_NORMAL;
                end
            end
            reset_counter <= next_reset_counter;
            retired_instructions <= speculation_resolved_instructions + 
                    (enable && normal_resolved_instruction);
            speculative_flag <= next_speculative_flag;
            if (fault_flag) faulted <= 'b1;
        end

        if (rst) begin
            exit_code <= 'b0;
        end else if (enable) begin
            exit_code <= next_exit_code;
        end
        
        if (rst) begin
            speculative_status <= '{NUM_SPECULATIVE_COUNTERS{'{
                mispredicted: 'b0,
                count: 'b0
            }}};
        end else if (enable) begin
            speculative_status <= next_speculative_status;
        end else begin
            if (speculative_status_decrement_enable) begin
                speculative_status[speculative_status_decrement_index].count <= 
                        speculative_status[speculative_status_decrement_index].count - 1;
            end
            if (speculative_status_mispredicted_enable) begin
                speculative_status[speculative_status_mispredicted_index].count <= 'b1;
            end
        end

        if (rst) begin
            jump_flag <= 'b0;
        end else if (update_jump_flag) begin
            jump_flag <= jump_flag + 'b1;
        end

        if (rst || clear_speculative_retired_counter) begin
            speculative_retired_counter <= 'b0;
        end else if (enable) begin
            speculative_retired_counter <= next_speculative_retired_counter;
        end

        if (rst || clear_execute_saved) begin
            execute_saved <= 'b0;
        end else if (enable) begin
            execute_saved <= next_execute_saved;
        end
    end

    logic register_write_enable;
    rv32_reg_addr_t register_write_addr;
    rv32_reg_value_t register_write_value;
    rv32_reg_addr_t register_read_addr0, register_read_addr1;
    rv32_reg_value_t register_read_value0, register_read_value1;

    // Register File
    std_distributed_ram #(
        .DATA_WIDTH($size(rv32_reg_value_t)),
        .ADDR_WIDTH($size(rv32_reg_addr_t)),
        .READ_PORTS(2)
    ) register_file_inst (
        .clk, .rst,

        // Always write to all bits in register
        .write_enable({32{register_write_enable}}),
        .write_addr(register_write_addr),
        .write_data_in(register_write_value),

        .read_addr('{register_read_addr0, register_read_addr1}),
        .read_data_out('{register_read_value0, register_read_value1})
    );

    logic front_status_rd_write_enable, rear_status_writeback_enable;

    rv32_reg_addr_t reg_status_rd_addr, reg_status_rs1_addr, reg_status_rs2_addr;
    gecko_reg_status_t front_status_rd, front_status_rs1, front_status_rs2;
    gecko_reg_status_t rear_status_rd, rear_status_rs1, rear_status_rs2;

    // Register file status from decode alone
    std_distributed_ram #(
        .DATA_WIDTH(GECKO_REG_STATUS_WIDTH),
        .ADDR_WIDTH($size(rv32_reg_addr_t)),
        .READ_PORTS(2)
    ) register_status_front_inst (
        .clk, .rst,

        // Always write to all bits in register, gate with state clock enable
        .write_enable({GECKO_REG_STATUS_WIDTH{front_status_rd_write_enable && enable}}),
        .write_addr(reg_status_rd_addr),
        // Simply increment the status when written to
        .write_data_in((state == GECKO_DECODE_RESET) ? 'b0 : (front_status_rd + 'b1)),
        .write_data_out(front_status_rd),

        .read_addr('{reg_status_rs1_addr, reg_status_rs2_addr}),
        .read_data_out('{front_status_rs1, front_status_rs2})
    );

    rv32_reg_addr_t rear_status_writeback_addr;
    gecko_reg_status_t rear_status_writeback;

    // Register file status from writebacks
    std_distributed_ram #(
        .DATA_WIDTH(GECKO_REG_STATUS_WIDTH),
        .ADDR_WIDTH($size(rv32_reg_addr_t)),
        .READ_PORTS(3)
    ) register_status_rear_inst (
        .clk, .rst,

        // Always write to all bits in register, gate with state clock enable
        .write_enable({GECKO_REG_STATUS_WIDTH{rear_status_writeback_enable}}),
        .write_addr(rear_status_writeback_addr),
        // Simply increment the status when written to
        .write_data_in((state == GECKO_DECODE_RESET) ? 'b0 : (rear_status_writeback + 'b1)),
        .write_data_out(rear_status_writeback),

        .read_addr('{reg_status_rd_addr, reg_status_rs1_addr, reg_status_rs2_addr}),
        .read_data_out('{rear_status_rd, rear_status_rs1, rear_status_rs2})
    );

    (* mark_debug = "true" *) logic inst_valid, inst_ready;
    (* mark_debug = "true" *) logic [31:0] inst_debug, pc_debug;
    (* mark_debug = "true" *) logic debug_decode_consume_inst;
    (* mark_debug = "true" *) logic debug_decode_produce_system, debug_decode_produce_execute, debug_decode_produce_print;
    (* mark_debug = "true" *) logic debug_decode_enable;
    (* mark_debug = "true" *) logic debug_decode_print_ready, debug_decode_execute_ready, debug_decode_system_ready;
    (* mark_debug = "true" *) logic [2:0] debug_decode_state;
    (* mark_debug = "true" *) logic debug_decode_spec_normal, debug_decode_jump_valid, debug_decode_jump_ready;

    always_comb begin
        inst_valid = instruction_result.valid;
        inst_ready = instruction_result.ready;
        inst_debug = instruction_result.data;
        pc_debug = instruction_command.payload.pc;

        debug_decode_consume_inst = consume_instruction;
        debug_decode_produce_execute = produce_execute;
        debug_decode_produce_system = produce_system;
        debug_decode_produce_print = produce_print;
        debug_decode_enable = enable;

        debug_decode_state = state;

        debug_decode_print_ready = next_ecall_command.ready;
        debug_decode_execute_ready = next_execute_command.ready;
        debug_decode_system_ready = next_system_command.ready;

        debug_decode_spec_normal = next_state_speculative_to_normal;
        debug_decode_jump_valid = jump_command.valid;
        debug_decode_jump_ready = jump_command.ready;
        
    end

    always_comb begin
        automatic gecko_instruction_operation_t inst_cmd_in;
        automatic gecko_jump_operation_t jump_cmd_in;
        automatic gecko_operation_t writeback_in;

        automatic gecko_decode_operands_status_t operands_status;
        automatic gecko_reg_status_t forwarded_status_plus;
        automatic rv32_reg_value_t rs1_value, rs2_value;
        automatic gecko_reg_status_t rd_status, rd_counter;
        automatic rv32_fields_t instruction_fields;

        automatic logic send_operation, reg_file_ready, reg_file_clear;
        automatic logic decode_exit;
        automatic gecko_decode_state_transition_t state_transition;
        automatic gecko_decode_opcode_status_t opcode_status;
        automatic gecko_jump_flag_t next_jump_flag;

        automatic gecko_reg_status_t rd_status_calc, rs1_status_calc, rs2_status_calc;

        // Reassign payloads to typed values
        jump_cmd_in = gecko_jump_operation_t'(jump_command.payload);
        inst_cmd_in = gecko_instruction_operation_t'(instruction_command.payload);
        writeback_in = gecko_operation_t'(writeback_result.payload);
        instruction_fields = rv32_get_fields(instruction_result.data);

        // Assign next values to defaults
        next_state = state;
        next_reset_counter = reset_counter + 'b1;
        next_speculative_retired_counter = speculative_retired_counter;
        next_execute_saved = execute_saved;
        next_speculative_status = speculative_status;
        next_speculative_flag = speculative_flag;

        // Assign internal flags to defaults
        decode_exit = 'b0;
        normal_resolved_instruction = 'b0;
        consume_instruction = 'b0;
        produce_execute = 'b0;
        produce_system = 'b0;
        produce_float = 'b0;
        produce_print = 'b0;
        next_ecall_command.payload = '{default: 'b0};
        fault_flag = 'b0;

        // Handle clearing register file by default
        register_write_enable = (state == GECKO_DECODE_RESET);
        register_write_addr = reset_counter;
        register_write_value = 'b0;

        // Read specific registers if calling the operating environment
        if (instruction_fields.opcode == RV32I_OPCODE_SYSTEM && 
                instruction_fields.funct3 == RV32I_FUNCT3_SYS_ENV) begin
            instruction_fields.rs1 = 'd10;
            instruction_fields.rs2 = 'd11;
        end

        // Clear register file status by default
        front_status_rd_write_enable = (state == GECKO_DECODE_RESET);
        rear_status_writeback_enable = (state == GECKO_DECODE_RESET);
        rear_status_writeback_addr = reset_counter;

        // Determine register status
        reg_status_rd_addr = (state == GECKO_DECODE_RESET) ? reset_counter : instruction_fields.rd;
        reg_status_rs1_addr = instruction_fields.rs1;
        reg_status_rs2_addr = instruction_fields.rs2;
        rd_status_calc = front_status_rd - rear_status_rd;
        rs1_status_calc = front_status_rs1 - rear_status_rs1;
        rs2_status_calc = front_status_rs2 - rear_status_rs2;

        // Determine various external flags
        reg_file_clear = 'b1; // TODO: Fix register file status for distributed-RAM
        // faulted_flag = (state == GECKO_DECODE_FAULT);
        // finished_flag = (state == GECKO_DECODE_HALT);
        exit_flag = (state == GECKO_DECODE_EXIT);

        // Handle incoming branch signals earlier than other logic
        speculative_status_mispredicted_enable = 'b0;
        speculative_status_mispredicted_index = next_speculative_flag;
        next_state_speculative_to_normal = 'b0;
        clear_execute_saved = 'b0;
        clear_speculative_retired_counter = 'b0;
        speculation_resolved_instructions = 'b0;
        update_jump_flag = 'b0;
        next_jump_flag = jump_flag;
        if (jump_command.valid) begin
            if (jump_cmd_in.update_pc) begin // Mispredicted
                update_jump_flag = 'b1;
                next_jump_flag = jump_flag + update_jump_flag;
                clear_execute_saved = 'b1;
                next_execute_saved = 'b0;
                speculative_status_mispredicted_enable = 'b1;
                next_speculative_status[speculative_status_mispredicted_index].mispredicted = 'b1;
            end else begin // Predicted Correctly
                speculation_resolved_instructions = next_speculative_retired_counter;
            end

            next_state_speculative_to_normal = 'b1;
            if (next_state == GECKO_DECODE_SPECULATIVE) begin
                next_state = GECKO_DECODE_NORMAL;
            end

            clear_speculative_retired_counter = 'b1;
            next_speculative_flag += 'b1;
        end

        // Handle incoming writeback updates to speculative state
        speculative_status_decrement_enable = 'b0;
        speculative_status_decrement_index = writeback_in.jump_flag;
        if (writeback_result.valid && writeback_result.ready && writeback_in.speculative) begin
            speculative_status_decrement_enable = 'b1;
            next_speculative_status[speculative_status_decrement_index].count -= 1;
        end
        
        // Halt incoming speculative writes until speculation resolved
        if (next_state == GECKO_DECODE_SPECULATIVE) begin
            writeback_result.ready = !writeback_in.speculative || 
                writeback_in.jump_flag != next_speculative_flag;
        end else begin
            writeback_result.ready = 'b1;
        end

        // Get the status of the current register file
        operands_status = gecko_decode_find_operand_status(instruction_fields, next_execute_saved, 
                rd_status_calc, rs1_status_calc, rs2_status_calc);

        // Set register file addresses
        register_read_addr0 = instruction_fields.rs1;
        register_read_addr1 = instruction_fields.rs2;

        // Get register values
        rs1_value = register_read_value0;
        rs2_value = register_read_value1;

        // Find forwarded results
        for (int i = 0; i < NUM_FORWARDED; i++) begin
            if (forwarded_results[i].valid && (
                    !forwarded_results[i].speculative ||
                    (!next_speculative_status[forwarded_results[i].jump_flag].mispredicted &&
                    next_state != GECKO_DECODE_SPECULATIVE))) begin

                forwarded_status_plus = forwarded_results[i].reg_status + 'b1;

                // Check forwarding for result of rs1
                if (!operands_status.rs1_valid && 
                        forwarded_results[i].addr == instruction_fields.rs1 &&
                        forwarded_status_plus == front_status_rs1) begin
                    rs1_value = forwarded_results[i].value;
                    operands_status.rs1_valid = 'b1;
                end

                // Check forwarding for result of rs2
                if (!operands_status.rs2_valid && 
                        forwarded_results[i].addr == instruction_fields.rs2 &&
                        forwarded_status_plus == front_status_rs2) begin
                    rs2_value = forwarded_results[i].value;
                    operands_status.rs2_valid = 'b1;
                end
            end
        end

        reg_file_ready = operands_status.rs1_valid && 
                operands_status.rs2_valid && 
                operands_status.rd_valid;

        // Build commands
        next_execute_command.payload = create_execute_op(instruction_fields, next_execute_saved, 
                                                 rs1_value, rs2_value, inst_cmd_in.pc);
        next_execute_command.payload.reg_status = front_status_rd;
        next_execute_command.payload.prediction = inst_cmd_in.prediction;
        next_execute_command.payload.next_pc = inst_cmd_in.next_pc;
        next_execute_command.payload.current_pc = inst_cmd_in.pc;
        // Issue flag if command is speculative
        next_execute_command.payload.speculative = (next_state == GECKO_DECODE_SPECULATIVE);
        next_execute_command.payload.jump_flag = next_speculative_flag;

        next_system_command.payload = create_system_op(instruction_fields, next_execute_saved, 
                                               rs1_value, rs2_value);
        next_system_command.payload.reg_status = front_status_rd;
        next_system_command.payload.jump_flag = next_speculative_flag;

        next_ecall_command.payload.operation = rs1_value[7:0];
        next_ecall_command.payload.data = rs2_value[7:0];
        next_exit_code = exit_code;

        next_float_command.payload.dest_reg_addr = instruction_fields.rd;
        next_float_command.payload.dest_reg_status = front_status_rd;
        next_float_command.payload.jump_flag = next_speculative_flag;
        next_float_command.payload.instruction_fields = instruction_fields;
        next_float_command.payload.rs1_value = rs1_value;
        next_float_command.payload.enable_status_op = 'b0;
        next_float_command.payload.sys_op = rv32i_funct3_sys_t'(instruction_fields.funct3);
        next_float_command.payload.sys_imm = {{27{instruction_fields.rs1[4]}}, instruction_fields.rs1};
        next_float_command.payload.sys_csr = instruction_fields.funct12;

        state_transition = get_state_transition(next_state, 
                instruction_fields,
                reset_counter,
                next_speculative_flag,
                next_speculative_status,
                inst_cmd_in.jump_flag, 
                next_jump_flag,
                reg_file_ready);
        opcode_status = get_opcode_status(instruction_fields);

        next_speculative_status = state_transition.next_speculative_status;

        consume_instruction = state_transition.consume_instruction;
        send_operation = !state_transition.flush_instruction && consume_instruction;



        if (send_operation) begin
            if (next_state == GECKO_DECODE_SPECULATIVE) begin
                next_speculative_retired_counter += 'b1;
            end else begin
                normal_resolved_instruction = 'b1;
            end

            if (opcode_status.error || (opcode_status.float && ENABLE_FLOAT == 0)) begin
                decode_exit = 'b1;
                next_exit_code = 'b1;
            end

            next_execute_saved = update_execute_saved(instruction_fields, next_execute_saved);

            if (instruction_fields.opcode == RV32I_OPCODE_SYSTEM &&
                    instruction_fields.funct3 == RV32I_FUNCT3_SYS_ENV) begin
                case (instruction_fields.funct12)
                RV32I_CSR_EBREAK: begin // System Exit
                    next_exit_code = rs1_value[7:0];
                    decode_exit = 'b1;
                end
                RV32I_CSR_ECALL: begin // System Call
                    if (ENABLE_PRINT) begin
                        produce_print = 'b1;
                    end
                end
                endcase
            end

            if (instruction_fields.rd != 'b0 && does_opcode_writeback(instruction_fields)) begin
                front_status_rd_write_enable = 'b1;
            end
        end

        if (decode_exit) begin
            next_state = GECKO_DECODE_EXIT;
            next_execute_command.payload.halt = 'b1;
            next_execute_command.payload.op_type = GECKO_EXECUTE_TYPE_JUMP;
            produce_execute = 'b1;
            produce_system = 'b0;
            produce_float = 'b0;
        end else begin
            next_state = state_transition.next_state;
            produce_execute = opcode_status.execute && send_operation;
            produce_system = opcode_status.system && send_operation;
            produce_float = opcode_status.float && send_operation;
        end

        // Handle writing back to the register file
        if (writeback_result.valid && writeback_result.ready) begin
            // Throw away writes to x0 and mispeculated results
            if (writeback_in.addr != 'b0) begin
                if (!next_speculative_status[writeback_in.jump_flag].mispredicted || 
                        !writeback_in.speculative) begin
                    register_write_enable = 'b1;
                    register_write_addr = writeback_in.addr;
                    register_write_value = writeback_in.value;
                end
            end
            // Validate register regardless of speculative
            rear_status_writeback_enable = 'b1;
            rear_status_writeback_addr = writeback_in.addr;
        end
    end

endmodule
