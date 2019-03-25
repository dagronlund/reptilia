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
 * Register File Flag: (2 bits per register)
 *      VALID - Register contents are valid
 *      INVALID - Register contents are invalid and exist 
 *      INVALID_EXECUTE(1-2) - Register contents are invalid, but one or two
 *          instructions were sent to execute that will write to this register
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
#()(
    input logic clk, rst,

    std_mem_intf.in instruction_result,
    std_stream_intf.in instruction_command, // gecko_instruction_operation_t

    std_stream_intf.out system_command, // gecko_system_operation_t
    std_stream_intf.out execute_command, // gecko_execute_operation_t

    std_stream_intf.out jump_command, // gecko_jump_command_t

    // Non-flow Controlled
    std_stream_intf.in branch_signal, // gecko_branch_signal_t
    std_stream_intf.in writeback_result, // gecko_operation_t

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

    logic consume_instruction;
    logic produce_jump, produce_system, produce_execute;
    logic enable, enable_jump, enable_system, enable_execute;

    // Flow Controller
    std_flow #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(3)
    ) std_flow_inst (
        .clk, .rst,

        .valid_input({instruction_result.valid, instruction_command.valid}),
        .ready_input({instruction_result.ready, instruction_command.ready}),

        .valid_output({jump_command.valid, system_command.valid, execute_command.valid}),
        .ready_output({jump_command.ready, system_command.ready, execute_command.ready}),

        .consume({consume_instruction, consume_instruction}),
        .produce({produce_jump, produce_system, produce_execute}),

        .enable,
        .enable_output({enable_jump, enable_system, enable_execute})
    );

    gecko_decode_state_t state, next_state;
    rv32_reg_addr_t reset_counter, next_reset_counter;
    gecko_jump_flag_t jump_flag, next_jump_flag;
    gecko_speculative_count_t speculative_counter, next_speculative_counter;
    gecko_speculative_count_t speculative_retired_counter, next_speculative_retired_counter;
    gecko_decode_reg_file_status_t reg_file_status, next_reg_file_status;
    rv32_reg_addr_t execute_saved, next_execute_saved;

    gecko_system_operation_t next_system_command; 
    gecko_execute_operation_t next_execute_command;
    gecko_jump_command_t next_jump_command; 

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

    logic simulation_ecall;
    logic simulation_write_char;
    logic [7:0] simulation_char;
    integer file;

    rv32_reg_value_t debug_counter;
    rv32_reg_value_t debug_full_counter;

    initial begin
        file = $fopen("log.txt", "w");
        $display("Opened file");
        @ (posedge clk);
        while (1) begin
            debug_counter <= debug_counter + 1;
            debug_full_counter <= debug_full_counter + debug_signals.register_full;
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
            jump_flag <= 'b0;
            speculative_counter <= 'b0;
            speculative_retired_counter <= 'b0;
            reg_file_status = '{32{GECKO_DECODE_REG_VALID}};
            execute_saved <= 'b0;
        end else begin
            state <= next_state;
            reset_counter <= next_reset_counter;
            jump_flag <= next_jump_flag;
            speculative_counter <= next_speculative_counter;
            speculative_retired_counter <= next_speculative_retired_counter;
            reg_file_status <= next_reg_file_status;
            execute_saved <= next_execute_saved;
        end
        if (enable_system) begin
            system_command.payload <= next_system_command;
        end
        if (enable_execute) begin
            execute_command.payload <= next_execute_command;
        end
        if (enable_jump) begin
            jump_command.payload <= next_jump_command;
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

    always_comb begin
        automatic logic send_operation, reg_file_ready, reg_file_clear;

        automatic gecko_decode_reg_status_t rd_status;
        automatic gecko_instruction_operation_t inst_cmd_in;
        automatic gecko_operation_t writeback_in;
        automatic gecko_branch_signal_t branch_cmd_in;
        automatic rv32_fields_t instruction_fields;
        automatic gecko_decode_require_t instruction_requirements;

        branch_cmd_in = gecko_branch_signal_t'(branch_signal.payload);
        inst_cmd_in = gecko_instruction_operation_t'(instruction_command.payload);
        writeback_in = gecko_operation_t'(writeback_result.payload);
        instruction_fields = rv32_get_fields(instruction_result.data);

        branch_signal.ready = 'b1;

        faulted_flag = 'b0;
        finished_flag = 'b0;
        retired_instructions = 'b0;

        // Halt incoming speculative writes until speculation resolved
        if (state == GECKO_DECODE_SPECULATIVE) begin
            writeback_result.ready = !writeback_in.speculative && writeback_result.valid;
        end else begin
            writeback_result.ready = 'b1;
        end

        send_operation = 'b0;

        consume_instruction = 'b0;
        produce_jump = 'b0;
        produce_execute = 'b0;
        produce_system = 'b0;

        // Get register values
        register_read_addr0 = instruction_fields.rs1;
        register_read_addr1 = instruction_fields.rs2;

        // Build commands
        next_execute_command = create_execute_op(instruction_fields, execute_saved, 
                                                 register_read_value0, register_read_value1,
                                                 inst_cmd_in.pc);
        next_system_command = create_system_op(instruction_fields, execute_saved, 
                                               register_read_value0, register_read_value1);
        next_jump_command = create_jump_op(instruction_fields, execute_saved, 
                                           register_read_value0, register_read_value1,
                                           inst_cmd_in.pc);

        // instruction_requirements = find_instruction_requirements(instruction_fields);
        reg_file_ready = is_register_file_ready(instruction_fields, execute_saved, reg_file_status);

        reg_file_clear = 'b1;
        for (int i = 0; i < 32; i++) begin
            reg_file_clear &= (reg_file_status[i[4:0]] == GECKO_DECODE_REG_VALID);
        end

`ifdef __SIMULATION__
        simulation_ecall = 'b0;
        simulation_write_char = 'b0;
        simulation_char = 'b0;

        debug_signals = '{default: 'b0};
        debug_signals.register_pending = !reg_file_ready;
        debug_signals.register_full = (reg_file_status[instruction_fields.rd] == 
            GECKO_DECODE_REG_EXECUTE1);

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

        register_write_enable = 'b0;
        register_write_addr = reset_counter;
        register_write_value = 'b0;

        next_state = state;
        next_reset_counter = reset_counter + 'b1;
        next_execute_saved = execute_saved;
        next_jump_flag = jump_flag;
        next_speculative_counter = speculative_counter;
        next_speculative_retired_counter = speculative_retired_counter;
        next_reg_file_status = reg_file_status;

        case (state)
        GECKO_DECODE_RESET: begin
            register_write_enable = 'b1;
            if (reset_counter == 'd31) begin
                next_state = GECKO_DECODE_NORMAL;
            end
        end
        GECKO_DECODE_NORMAL: begin
            if (inst_cmd_in.jump_flag != jump_flag) begin
                consume_instruction = 'b1;
            end else if (reg_file_ready) begin
                case (rv32i_opcode_t'(instruction_fields.opcode))
                RV32I_OPCODE_JAL, RV32I_OPCODE_JALR: begin
                    consume_instruction = 'b1;
                    send_operation = 'b1;
                    next_jump_flag = next_jump_flag + 'b1;
                end
                RV32I_OPCODE_BRANCH: begin
                    if (speculative_counter == 'b0) begin
                        consume_instruction = 'b1;
                        send_operation = 'b1;
                        next_state = GECKO_DECODE_SPECULATIVE;
                    end
                end
                default: begin
                    consume_instruction = 'b1;
                    send_operation = 'b1;
                end
                endcase
            end
        end
        GECKO_DECODE_SPECULATIVE: begin
            if (inst_cmd_in.jump_flag != jump_flag) begin
                consume_instruction = 'b1;
            end else if (reg_file_ready) begin
                case (rv32i_opcode_t'(instruction_fields.opcode))
                RV32I_OPCODE_LOAD, RV32I_OPCODE_STORE, RV32I_OPCODE_SYSTEM, RV32I_OPCODE_FENCE: begin // Side-Effects
                end
                RV32I_OPCODE_JAL, RV32I_OPCODE_JALR, RV32I_OPCODE_BRANCH: begin // Jumps
                end
                default: begin
                    consume_instruction = 'b1;
                    send_operation = 'b1;
                    next_execute_command.speculative = 'b1;
                end
                endcase
            end
        end
        GECKO_DECODE_MISPREDICTED: begin
            if (inst_cmd_in.jump_flag != jump_flag) begin
                consume_instruction = 'b1;
            end else if (reg_file_ready) begin
                case (rv32i_opcode_t'(instruction_fields.opcode))
                RV32I_OPCODE_JAL, RV32I_OPCODE_JALR: begin
                    consume_instruction = 'b1;
                    send_operation = 'b1;
                    next_jump_flag = next_jump_flag + 'b1;
                end
                RV32I_OPCODE_BRANCH: begin // Can't speculatively branch while cleaning up misprediction 
                end
                default: begin
                    consume_instruction = 'b1;
                    send_operation = 'b1;
                end
                endcase
            end
        end
        GECKO_DECODE_FAULT: begin
            faulted_flag = 'b1;
            finished_flag = reg_file_clear;
        end
        GECKO_DECODE_HALT: begin
            finished_flag = reg_file_clear;
        end
        GECKO_DECODE_UNDEF: begin
            next_state = GECKO_DECODE_RESET;
        end
        endcase

        rd_status = next_reg_file_status[instruction_fields.rd];

        if (send_operation) begin
            if (state == GECKO_DECODE_SPECULATIVE) begin
                next_speculative_counter = 
                    next_speculative_counter + (instruction_fields.rd != 'b0);
                next_speculative_retired_counter = 
                    next_speculative_retired_counter + 'b1;
            end else begin
                retired_instructions = retired_instructions + 'b1;
            end
            
            case (rv32i_opcode_t'(instruction_fields.opcode))
            RV32I_OPCODE_OP, RV32I_OPCODE_IMM, RV32I_OPCODE_LUI, RV32I_OPCODE_AUIPC: begin
                produce_execute = (instruction_fields.rd != 'b0);
                next_execute_saved = next_execute_command.reg_addr;
                rd_status = invalidate_reg_status(rd_status, 'b1);
            end
            RV32I_OPCODE_LOAD: begin // Issue load regardless of going to x0
                produce_execute = 'b1;
                if (execute_saved == next_execute_command.reg_addr) begin
                    next_execute_saved = 'b0;
                end
                rd_status = invalidate_reg_status(rd_status, 'b0);
            end
            RV32I_OPCODE_STORE: begin
                produce_execute = 'b1;
                // rd_status = invalidate_reg_status(rd_status, 'b0);
            end
            RV32I_OPCODE_JAL, RV32I_OPCODE_JALR: begin
                produce_jump = 'b1;
                produce_execute = (instruction_fields.rd != 'b0);
                next_execute_saved = next_execute_command.reg_addr;
                rd_status = invalidate_reg_status(rd_status, 'b1);
            end
            RV32I_OPCODE_BRANCH: begin
                produce_execute = 'b1;
            end
            RV32I_OPCODE_SYSTEM: begin
                case (rv32i_funct3_sys_t'(instruction_fields.funct3))
                RV32I_FUNCT3_SYS_ENV: begin
`ifdef __SIMULATION__
                    // Read out a0 and a1 registers, SIMULATION ONLY
                    register_read_addr0 = 'd10;
                    register_read_addr1 = 'd11;

                    case (instruction_fields.funct12)
                    RV32I_CSR_EBREAK: begin // System Exit
                        if (register_read_value0 == 0) begin
                            next_state = GECKO_DECODE_HALT;
                        end else begin
                            next_state = GECKO_DECODE_FAULT;
                        end
                    end
                    RV32I_CSR_ECALL: begin // System Call
                        if (enable) begin
                            simulation_ecall = 'b1;
                            if (register_read_value0 == 0) begin
                                simulation_write_char = 'b1;
                                simulation_char = register_read_value1[7:0];
                            end
                        end
                    end
                    default: begin
                        next_state = GECKO_DECODE_FAULT;
                    end
                    endcase
`else
                    next_state = GECKO_DECODE_HALT; // Halt if encountered
`endif
                end
                RV32I_FUNCT3_SYS_CSRRW, RV32I_FUNCT3_SYS_CSRRS, 
                RV32I_FUNCT3_SYS_CSRRC, RV32I_FUNCT3_SYS_CSRRWI, 
                RV32I_FUNCT3_SYS_CSRRSI, RV32I_FUNCT3_SYS_CSRRCI: begin
                    produce_system = 'b1;
                    if (execute_saved == next_system_command.rd_addr) begin
                        next_execute_saved = 'b0;
                    end
                    rd_status = invalidate_reg_status(rd_status, 'b0);    
                end
                default: begin
                    next_state = GECKO_DECODE_FAULT;
                end
                endcase
            end
            default: begin
                next_state = GECKO_DECODE_FAULT;
            end
            endcase

            if (instruction_fields.rd != 'b0) begin
                next_reg_file_status[instruction_fields.rd] = rd_status;
            end
        end

        // DANGER: Uses the enable signal to prevent state changes from earlier
        //         which is only needed because of the following interrupts
        if (!enable) begin
            next_state = state;
            next_reset_counter = reset_counter + 'b1;
            next_execute_saved = execute_saved;
            next_jump_flag = jump_flag;
            next_speculative_counter = speculative_counter;
            next_speculative_retired_counter = speculative_retired_counter;
            next_reg_file_status = reg_file_status;
            retired_instructions = 'b0;
        end

        // Handle writing back to the register file
        if (writeback_result.valid && writeback_result.ready) begin
            // Throw away writes to x0 and mispeculated results
            if (writeback_in.addr != 'b0 && !(state == GECKO_DECODE_MISPREDICTED && writeback_in.speculative)) begin
                register_write_enable = 'b1;
                register_write_addr = writeback_in.addr;
                register_write_value = writeback_in.value;
            end
            // Countdown when speculative writeback occurs
            if (writeback_in.speculative) begin
                next_speculative_counter = next_speculative_counter - 'b1;
                if (next_speculative_counter == 0) begin
                    next_state = (state == GECKO_DECODE_MISPREDICTED) ? GECKO_DECODE_NORMAL : next_state;
                end
            end
            // Validate register regardless of speculative
            next_reg_file_status[writeback_in.addr] = validate_reg_status(next_reg_file_status[writeback_in.addr]);
        end

        // Handle incoming branch signals
        if (branch_signal.valid && branch_signal.ready) begin
            if (branch_cmd_in.branch) begin
                // Return to normal immediately if no speculative instructions executed
                if (next_speculative_counter == 0) begin
                    next_state = (state == GECKO_DECODE_SPECULATIVE) ? GECKO_DECODE_NORMAL : next_state;
                end else begin
                    next_state = (state == GECKO_DECODE_SPECULATIVE) ? GECKO_DECODE_MISPREDICTED : next_state;
                end
                next_jump_flag = next_jump_flag + 'b1;
                next_execute_saved = 'b0;
            end else begin
                next_state = (state == GECKO_DECODE_SPECULATIVE) ? GECKO_DECODE_NORMAL : next_state;
                retired_instructions = retired_instructions + next_speculative_retired_counter;
            end
            next_speculative_retired_counter = 'b0;
        end
    end

endmodule
