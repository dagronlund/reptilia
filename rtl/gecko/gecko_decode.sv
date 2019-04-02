`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"
`include "../../lib/gecko/gecko_decode_util.svh"

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
    import gecko::*;
    import gecko_decode_util::*;
#(
    parameter int NUM_FORWARDED = 0
)(
    input logic clk, rst,

    std_mem_intf.in instruction_result,
    std_stream_intf.in instruction_command, // gecko_instruction_operation_t

    std_stream_intf.out system_command, // gecko_system_operation_t
    std_stream_intf.out execute_command, // gecko_execute_operation_t

    // Non-flow Controlled
    std_stream_intf.in jump_command, // gecko_jump_operation_t
    std_stream_intf.in writeback_result, // gecko_operation_t

    // Vivado does not like zero-width arrays
    input gecko_forwarded_t forwarded_results [NUM_FORWARDED == 0 ? 1 : NUM_FORWARDED],

    output logic faulted_flag, finished_flag,
    output gecko_retired_count_t retired_instructions
);

    typedef enum logic [2:0] {
        GECKO_DECODE_RESET = 3'b000,
        GECKO_DECODE_NORMAL = 3'b001,
        GECKO_DECODE_SPECULATIVE = 3'b010,
        GECKO_DECODE_MISPREDICTED = 3'b011,
        GECKO_DECODE_HALT = 3'b100,
        GECKO_DECODE_FAULT = 3'b101,
        GECKO_DECODE_UNDEF = 3'bXXX
    } gecko_decode_state_t;

    localparam NUM_SPECULATIVE_COUNTERS = 2**$bits(gecko_jump_flag_t);

    // typedef enum logic [1:0] {
    //     GECKO_DECODE_SPECULATIVE_UNRESOLVED = 2'b000,
    //     GECKO_DECODE_SPECULATIVE_PREDICTED = 2'b01,
    //     GECKO_DECODE_SPECULATIVE_MISPREDICTED = 2'b10,
    //     GECKO_DECODE_SPECULATIVE_UNDEF = 2'bXX
    // } gecko_speculative_state_t;

    typedef struct packed {
        // gecko_speculative_state_t state;
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
            input gecko_speculative_count_t current_speculative_counter,
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
        GECKO_DECODE_NORMAL, GECKO_DECODE_MISPREDICTED, GECKO_DECODE_SPECULATIVE: begin
            if (instruction_jump_flag != current_jump_flag) begin
                result.consume_instruction = 'b1;
                result.flush_instruction = 'b1;
            end else if (reg_file_ready) begin
                // Only execute non side effect instructions in speculative
                if (current_state == GECKO_DECODE_SPECULATIVE) begin
                    // Make sure speculative counter still has room
                    if (current_speculative_counter != GECKO_SPECULATIVE_FULL) begin
                    // if (current_speculative_status[current_speculative_flag] 
                    //         != GECKO_SPECULATIVE_FULL) begin
                        if (!is_opcode_side_effects(instruction_fields)) begin
                            result.consume_instruction = 'b1;
                            result.next_speculative_status[current_speculative_flag].count += 'b1;
                        end
                    end
                end else if (is_opcode_control_flow(instruction_fields)) begin
                    if (current_speculative_counter == 'b0) begin
                    // if (current_speculative_status[current_speculative_flag] == 'b0) begin
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
        GECKO_DECODE_HALT, GECKO_DECODE_FAULT: begin
            result.next_state = current_state;
        end
        default: begin
            result.next_state = GECKO_DECODE_RESET;
        end
        endcase
        return result;
    endfunction

    logic consume_instruction;
    logic produce_system, produce_execute;
    logic enable, enable_system, enable_execute;

    // Flow Controller
    std_flow #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(2)
    ) std_flow_inst (
        .clk, .rst,

        .valid_input({instruction_result.valid, instruction_command.valid}),
        .ready_input({instruction_result.ready, instruction_command.ready}),

        .valid_output({system_command.valid, execute_command.valid}),
        .ready_output({system_command.ready, execute_command.ready}),

        .consume({consume_instruction, consume_instruction}),
        .produce({produce_system, produce_execute}),

        .enable,
        .enable_output({enable_system, enable_execute})
    );

    logic next_state_speculative_to_normal, 
            next_state_speculative_to_mispredicted,
            next_state_to_normal;
    gecko_decode_state_t state, next_state;
    rv32_reg_addr_t reset_counter, next_reset_counter;
    logic update_jump_flag;
    gecko_jump_flag_t jump_flag;
    gecko_speculative_count_t speculative_counter, next_speculative_counter;
    logic clear_speculative_retired_counter;
    gecko_speculative_count_t speculative_retired_counter, next_speculative_retired_counter;
    gecko_decode_reg_file_status_t reg_file_status, next_reg_file_status;
    gecko_decode_reg_file_status_t reg_file_counter, next_reg_file_counter; // TODO: Replace with RAM
    logic clear_execute_saved;
    rv32_reg_addr_t execute_saved, next_execute_saved;

    logic speculative_status_decrement_enable;
    gecko_jump_flag_t speculative_status_decrement_index;
    logic speculative_status_mispredicted_enable;
    gecko_jump_flag_t speculative_status_mispredicted_index;
    gecko_speculative_status_t speculative_status, next_speculative_status;
    gecko_jump_flag_t speculative_flag, next_speculative_flag;

    gecko_system_operation_t next_system_command; 
    gecko_execute_operation_t next_execute_command;
    logic normal_resolved_instruction;
    gecko_speculative_count_t speculation_resolved_instructions;

`ifdef __SIMULATION__

    typedef struct packed {
        logic register_pending;
        logic register_full;
        logic inst_branch;
        logic inst_jump;
        logic inst_execute;
        logic inst_load;
        logic inst_store;
        logic inst_system;
    } debug_signals_t;

    debug_signals_t debug_signals;
    logic [31:0] debug_register_pending_counter;

    logic flushing_inst;
    logic [31:0] flushing_inst_counter;

    logic simulation_ecall;
    logic simulation_write_char;
    logic [7:0] simulation_char;
    integer file;

    rv32_reg_value_t debug_counter;
    rv32_reg_value_t debug_full_counter;

    logic execute_stalled;
    logic [31:0] execute_stalled_counter;

    logic instruction_type_stalled;
    logic [31:0] instruction_type_stalled_counter;

    initial begin
        debug_register_pending_counter = 'b0;
        flushing_inst_counter = 'b0;
        execute_stalled_counter = 'b0;
        instruction_type_stalled_counter = 'b0;
        file = $fopen("log.txt", "w");
        $display("Opened file");
        @ (posedge clk);
        while (1) begin
            debug_counter <= debug_counter + 1;
            flushing_inst_counter <= flushing_inst_counter + flushing_inst;
            debug_full_counter <= debug_full_counter + debug_signals.register_full;
            debug_register_pending_counter <= debug_register_pending_counter + debug_signals.register_pending;
            execute_stalled_counter <= execute_stalled_counter + execute_stalled;
            instruction_type_stalled_counter <= instruction_type_stalled_counter + instruction_type_stalled;
            if (simulation_write_char) begin
                $fwrite(file, "%c", simulation_char);
            end
            if (state == GECKO_DECODE_HALT || state == GECKO_DECODE_FAULT) begin
                $display("Closed file");
                $fclose(file);
                break;
            end
            @ (posedge clk);
        end
        while (!finished_flag) @ (posedge clk);
        file = $fopen("status.txt", "w");
        if (faulted_flag) begin
            $display("Exit Error!!!");
            $fwrite(file, "Failure");
        end else begin
            $display("Exit Success!!!");
            $fwrite(file, "Success");
        end
        $fclose(file);
        $finish();
    end
`endif

    always_ff @(posedge clk) begin
        if(rst) begin
            state <= GECKO_DECODE_RESET;
            reset_counter <= 'b0;
            speculative_counter <= 'b0;
            reg_file_status = '{32{GECKO_REG_STATUS_VALID}};
            retired_instructions <= 'b0;
            speculative_flag <= 'b0;
        end else begin
            if (enable) begin
                state <= next_state;
            end else if (state == GECKO_DECODE_SPECULATIVE) begin
                if (next_state_speculative_to_normal) state <= GECKO_DECODE_NORMAL;
                if (next_state_speculative_to_mispredicted) state <= GECKO_DECODE_MISPREDICTED;
            end
            if (next_state_to_normal) state <= GECKO_DECODE_NORMAL;
            reset_counter <= next_reset_counter;
            speculative_counter <= next_speculative_counter;
            reg_file_status <= next_reg_file_status;
            retired_instructions <= speculation_resolved_instructions + 
                    (enable && normal_resolved_instruction);
            speculative_flag <= next_speculative_flag;
        end
        
        if (rst) begin
            speculative_status <= '{NUM_SPECULATIVE_COUNTERS{'{
                // state: GECKO_DECODE_SPECULATIVE_UNRESOLVED,
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

        if (rst) begin
            reg_file_counter = '{32{GECKO_REG_STATUS_VALID}};
        end else if (enable) begin
            reg_file_counter <= next_reg_file_counter;
        end

        if (rst || clear_execute_saved) begin
            execute_saved <= 'b0;
        end else if (enable) begin
            execute_saved <= next_execute_saved;
        end
        
        if (enable_system) begin
            system_command.payload <= next_system_command;
        end
        if (enable_execute) begin
            execute_command.payload <= next_execute_command;
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

    gecko_decode_state_transition_t state_transition;
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
        automatic logic decode_stop, decode_error;
        // automatic gecko_decode_state_transition_t state_transition;
        automatic gecko_decode_opcode_status_t opcode_status;
        automatic gecko_jump_flag_t next_jump_flag;

        // Reassign payloads to typed values
        jump_cmd_in = gecko_jump_operation_t'(jump_command.payload);
        inst_cmd_in = gecko_instruction_operation_t'(instruction_command.payload);
        writeback_in = gecko_operation_t'(writeback_result.payload);
        instruction_fields = rv32_get_fields(instruction_result.data);

        // Assign next values to defaults
        next_state = state;
        next_reset_counter = reset_counter + 'b1;
        next_speculative_counter = speculative_counter;
        next_speculative_retired_counter = speculative_retired_counter;
        next_reg_file_status = reg_file_status;
        next_reg_file_counter = reg_file_counter;
        next_execute_saved = execute_saved;
        next_speculative_status = speculative_status;
        next_speculative_flag = speculative_flag;

        // Assign internal flags to defaults
        decode_error = 'b0;
        decode_stop = 'b0;
        normal_resolved_instruction = 'b0;
        consume_instruction = 'b0;
        produce_execute = 'b0;
        produce_system = 'b0;

        // Handle clearing register file by default
        register_write_enable = (state == GECKO_DECODE_RESET);
        register_write_addr = reset_counter;
        register_write_value = 'b0;

        // Determine various external flags
        reg_file_clear = 'b1;
        for (int i = 0; i < 32; i++) begin
            reg_file_clear &= (reg_file_status[i[4:0]] == GECKO_REG_STATUS_VALID);
        end
        faulted_flag = (state == GECKO_DECODE_FAULT);
        finished_flag = reg_file_clear && 
                (state == GECKO_DECODE_HALT || state == GECKO_DECODE_FAULT);

        // Handle incoming branch signals earlier than other logic
        speculative_status_mispredicted_enable = 'b0;
        speculative_status_mispredicted_index = next_speculative_flag;
        next_state_speculative_to_normal = 'b0;
        next_state_speculative_to_mispredicted = 'b0;
        clear_execute_saved = 'b0;
        clear_speculative_retired_counter = 'b0;
        speculation_resolved_instructions = 'b0;
        update_jump_flag = 'b0;
        next_jump_flag = jump_flag;
        if (jump_command.valid && jump_command.ready) begin
            if (jump_cmd_in.update_pc) begin // Mispredicted
                next_state_speculative_to_mispredicted = 'b1;
                if (next_state == GECKO_DECODE_SPECULATIVE) next_state = GECKO_DECODE_MISPREDICTED;
                update_jump_flag = 'b1;
                next_jump_flag = jump_flag + update_jump_flag;
                clear_execute_saved = 'b1;
                next_execute_saved = 'b0;
                speculative_status_mispredicted_enable = 'b1;
                next_speculative_status[speculative_status_mispredicted_index].mispredicted = 'b1;
            end else begin // Predicted Correctly
                next_state_speculative_to_normal = 'b1;
                if (next_state == GECKO_DECODE_SPECULATIVE) next_state = GECKO_DECODE_NORMAL;
                speculation_resolved_instructions = next_speculative_retired_counter;
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
            writeback_result.ready = !writeback_in.speculative;
        end else begin
            writeback_result.ready = 'b1;
        end

`ifdef __SIMULATION__
        if (instruction_fields.opcode == RV32I_OPCODE_SYSTEM && 
                instruction_fields.funct3 == RV32I_FUNCT3_SYS_ENV) begin
            // Read out a0 and a1 registers, SIMULATION ONLY
            instruction_fields.rs1 = 'd10;
            instruction_fields.rs2 = 'd11;
        end
`endif

        // Get the status of the current register file
        operands_status = gecko_decode_find_operand_status(instruction_fields, 
                next_execute_saved, reg_file_status);

        // Set register file addresses
        register_read_addr0 = instruction_fields.rs1;
        register_read_addr1 = instruction_fields.rs2;

        // Get register values
        rs1_value = register_read_value0;
        rs2_value = register_read_value1;

        // Find forwarded results
        for (int i = 0; i < NUM_FORWARDED; i++) begin
            if (forwarded_results[i].valid && (next_state == GECKO_DECODE_NORMAL || 
                    !forwarded_results[i].speculative)) begin

                forwarded_status_plus = forwarded_results[i].reg_status + 'b1;

                // Check forwarding for result of rs1
                if (!operands_status.rs1_valid && 
                        forwarded_results[i].addr == instruction_fields.rs1 &&
                        forwarded_status_plus == reg_file_counter[instruction_fields.rs1]) begin
                    rs1_value = forwarded_results[i].value;
                    operands_status.rs1_valid = 'b1;
                end

                // Check forwarding for result of rs2
                if (!operands_status.rs2_valid && 
                        forwarded_results[i].addr == instruction_fields.rs2 &&
                        forwarded_status_plus == reg_file_counter[instruction_fields.rs2]) begin
                    rs2_value = forwarded_results[i].value;
                    operands_status.rs2_valid = 'b1;
                end
            end
        end

        reg_file_ready = operands_status.rs1_valid && 
                operands_status.rs2_valid && 
                operands_status.rd_valid;

        // Build commands
        next_execute_command = create_execute_op(instruction_fields, next_execute_saved, 
                                                 rs1_value, rs2_value, inst_cmd_in.pc);
        next_execute_command.reg_status = reg_file_counter[instruction_fields.rd];
        next_execute_command.prediction = inst_cmd_in.prediction;
        next_execute_command.next_pc = inst_cmd_in.next_pc;
        next_execute_command.current_pc = inst_cmd_in.pc;
        // Issue flag if command is speculative
        next_execute_command.speculative = (next_state == GECKO_DECODE_SPECULATIVE);
        next_execute_command.jump_flag = next_speculative_flag;

        next_system_command = create_system_op(instruction_fields, next_execute_saved, 
                                               rs1_value, rs2_value);
        next_system_command.reg_status = reg_file_counter[instruction_fields.rd];
        next_system_command.jump_flag = next_speculative_flag;

`ifdef __SIMULATION__
        simulation_ecall = 'b0;
        simulation_write_char = 'b0;
        simulation_char = 'b0;

        flushing_inst = 'b0;
        instruction_type_stalled = 'b0;

        debug_signals = '{default: 'b0};
        debug_signals.register_pending = !reg_file_ready;
        debug_signals.register_full = (reg_file_status[instruction_fields.rd] == 
            GECKO_REG_STATUS_FULL);

        case (rv32i_opcode_t'(instruction_fields.opcode))
        RV32I_OPCODE_OP, RV32I_OPCODE_IMM, RV32I_OPCODE_LUI, RV32I_OPCODE_AUIPC: begin
            debug_signals.inst_execute = 'b1;
        end
        RV32I_OPCODE_LOAD: begin
            debug_signals.inst_execute = 'b1;
            debug_signals.inst_load = 'b1;
        end
        RV32I_OPCODE_STORE: begin
            debug_signals.inst_execute = 'b1;
            debug_signals.inst_store = 'b1;
        end
        RV32I_OPCODE_JAL, RV32I_OPCODE_JALR: begin
            debug_signals.inst_jump = 'b1;
        end
        RV32I_OPCODE_BRANCH: begin
            debug_signals.inst_execute = 'b1;
            debug_signals.inst_branch = 'b1;
        end
        RV32I_OPCODE_SYSTEM: begin
            debug_signals.inst_system = 'b1;
        end
        default: begin
        end
        endcase
`endif

        state_transition = get_state_transition(next_state, 
                instruction_fields,
                reset_counter,
                // Early check for incoming speculative result
                speculative_counter + (writeback_result.valid && writeback_result.ready && writeback_in.speculative),
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
                next_speculative_counter += (instruction_fields.rd != 'b0);
                next_speculative_retired_counter += 'b1;
            end else begin
                normal_resolved_instruction = 'b1;
            end

            decode_error = opcode_status.error;

            next_execute_saved = update_execute_saved(instruction_fields, next_execute_saved);

            if (instruction_fields.opcode == RV32I_OPCODE_SYSTEM &&
                    instruction_fields.funct3 == RV32I_FUNCT3_SYS_ENV) begin
`ifdef __SIMULATION__
                case (instruction_fields.funct12)
                RV32I_CSR_EBREAK: begin // System Exit
                    if (rs1_value == 0) begin
                        decode_stop = 'b1;
                    end else begin
                        decode_error = 'b1;
                    end
                end
                RV32I_CSR_ECALL: begin // System Call
                    if (enable) begin
                        simulation_ecall = 'b1;
                        if (rs1_value == 0) begin
                            simulation_write_char = 'b1;
                            simulation_char = rs2_value[7:0];
                        end
                    end
                end
                endcase
`else
                decode_stop = 'b1;
`endif
            end

            if (instruction_fields.rd != 'b0 && does_opcode_writeback(instruction_fields)) begin
                next_reg_file_status[instruction_fields.rd] += 1;
                next_reg_file_counter[instruction_fields.rd] += 1;
            end
        end

        produce_execute = opcode_status.execute && send_operation;
        produce_system = opcode_status.system && send_operation;

        if (decode_stop) next_state = GECKO_DECODE_HALT;
        else if (decode_error) next_state = GECKO_DECODE_FAULT;
        else next_state = state_transition.next_state;

        // DANGER: Uses the enable signal to prevent state changes from earlier
        //         which is only needed because of the following asynchronous
        //         control flow signals
        if (!enable) begin
            next_speculative_counter = speculative_counter;
            next_reg_file_status = reg_file_status;
        end

        // Handle writing back to the register file
        if (writeback_result.valid && writeback_result.ready) begin
            // Throw away writes to x0 and mispeculated results
            if (writeback_in.addr != 'b0 && 
                    !(state == GECKO_DECODE_MISPREDICTED && writeback_in.speculative)) begin
                register_write_enable = 'b1;
                register_write_addr = writeback_in.addr;
                register_write_value = writeback_in.value;
            end
            // Countdown when speculative writeback occurs
            next_speculative_counter -= writeback_in.speculative;
            // Validate register regardless of speculative
            next_reg_file_status[writeback_in.addr] -= 'b1;
        end

        // Handle moving out of misprediction on the next_cycle
        next_state_to_normal = 'b0;
        if (state == GECKO_DECODE_MISPREDICTED && next_state == GECKO_DECODE_MISPREDICTED) begin
            next_state_to_normal = (speculative_counter == 0);
        end
    end

endmodule
