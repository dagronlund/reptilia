`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

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
#()(
    input logic clk, rst,

    std_mem_intf.in instruction_result,
    std_stream_intf.in instruction_command, // gecko_instruction_operation_t

    std_stream_intf.out system_command, // gecko_system_operation_t
    std_stream_intf.out execute_command, // gecko_execute_operation_t

    std_stream_intf.out jump_command, // gecko_jump_command_t

    // Non-flow Controlled
    std_stream_intf.in branch_signal, // gecko_branch_signal_t
    std_stream_intf.in writeback_result // gecko_operation_t
);

    typedef enum logic [1:0] {
        GECKO_DECODE_RESET = 2'b00,
        GECKO_DECODE_NORMAL = 2'b01,
        GECKO_DECODE_SPECULATIVE = 2'b10,
        GECKO_DECODE_MISPREDICTED = 2'b11
    } gecko_decode_state_t;

    typedef enum logic [1:0] {
        GECKO_DECODE_REG_VALID = 2'b00,
        GECKO_DECODE_REG_INVALID = 2'b01,
        GECKO_DECODE_REG_EXECUTE0 = 2'b10,
        GECKO_DECODE_REG_EXECUTE1 = 2'b11
    } gecko_decode_reg_status_t;

    typedef enum logic [1:0] {
        GECKO_DECODE_REQUIRE_NORMAL = 2'b00,
        GECKO_DECODE_REQUIRE_SIDE_EFFECTS = 2'b01,
        GECKO_DECODE_REQUIRE_JUMP = 2'b10,
        GEKCO_DECODE_REQUIRE_UNDEF = 2'b11
    } gecko_decode_require_t;

    typedef gecko_decode_reg_status_t [31:0] gecko_decode_reg_file_status_t;

    function automatic gecko_decode_require_t find_instruction_requirements(
            input rv32_fields_t instruction_fields
    );
        case (rv32i_opcode_t'(instruction_fields.opcode))
        RV32I_OPCODE_LOAD, RV32I_OPCODE_STORE, RV32I_OPCODE_SYSTEM, RV32I_OPCODE_FENCE: 
            return GECKO_DECODE_REQUIRE_SIDE_EFFECTS;
        RV32I_OPCODE_JAL, RV32I_OPCODE_JALR, RV32I_OPCODE_BRANCH: 
            return GECKO_DECODE_REQUIRE_JUMP;
        default: 
            return GECKO_DECODE_REQUIRE_NORMAL;
        endcase
    endfunction

    function automatic gecko_decode_reg_status_t write_register_state(
            input gecko_decode_reg_status_t current_status,
            input logic sending_execute
    );
        case (current_status)
        GECKO_DECODE_REG_VALID: return sending_execute ? GECKO_DECODE_REG_EXECUTE0 : GECKO_DECODE_REG_INVALID;
        GECKO_DECODE_REG_INVALID: return GECKO_DECODE_REG_INVALID; // Invalid path
        GECKO_DECODE_REG_EXECUTE0: return GECKO_DECODE_REG_EXECUTE1;
        GECKO_DECODE_REG_EXECUTE1: return GECKO_DECODE_REG_EXECUTE1; // Invalid path
        endcase
    endfunction

    function automatic logic is_register_readable(
            input rv32_reg_addr_t reg_addr,
            input rv32_reg_addr_t execute_saved_reg,
            input gecko_decode_reg_file_status_t reg_file_status
    );
        return (reg_addr == 'b0 || 
            (reg_addr == execute_saved_reg && (
                reg_file_status[reg_addr] == GECKO_DECODE_REG_EXECUTE0 ||
                reg_file_status[reg_addr] == GECKO_DECODE_REG_EXECUTE1)) ||
            reg_file_status[reg_addr] == GECKO_DECODE_REG_VALID);
    endfunction

    function automatic logic is_register_file_ready(
            input rv32_fields_t instruction_fields,
            input rv32_reg_addr_t ex_saved,
            input gecko_decode_reg_file_status_t rf_status
    );
        rv32_reg_addr_t rd, rs1, rs2;
        rd = instruction_fields.rd;
        rs1 = instruction_fields.rs1;
        rs2 = instruction_fields.rs2;

        case (rv32i_opcode_t'(instruction_fields.opcode))
        RV32I_OPCODE_OP: begin // rd, rs1, rs2
            return is_register_readable(rs1, ex_saved, rf_status) && 
                    is_register_readable(rs2, ex_saved, rf_status) &&
                    (rf_status[rd] == GECKO_DECODE_REG_VALID || rf_status[rd] == GECKO_DECODE_REG_EXECUTE0);
        end
        RV32I_OPCODE_IMM: begin // rd, rs1
            return is_register_readable(rs1, ex_saved, rf_status) &&
                    (rf_status[rd] == GECKO_DECODE_REG_VALID || rf_status[rd] == GECKO_DECODE_REG_EXECUTE0);
        end
        RV32I_OPCODE_LOAD: begin // rd, rs1
            return is_register_readable(rs1, ex_saved, rf_status) &&
                    (rf_status[rd] == GECKO_DECODE_REG_VALID);
        end
        RV32I_OPCODE_STORE: begin // rs1, rs2
            return is_register_readable(rs1, ex_saved, rf_status) && 
                    is_register_readable(rs2, ex_saved, rf_status);
        end
        RV32I_OPCODE_LUI, RV32I_OPCODE_AUIPC, RV32I_OPCODE_JAL: begin // rd
            return (rf_status[rd] == GECKO_DECODE_REG_VALID || rf_status[rd] == GECKO_DECODE_REG_EXECUTE0);
        end
        RV32I_OPCODE_JALR: begin // rd, rs1
            return (rf_status[rs1] == GECKO_DECODE_REG_VALID) &&
                    (rf_status[rd] == GECKO_DECODE_REG_VALID || rf_status[rd] == GECKO_DECODE_REG_EXECUTE0); 
        end
        RV32I_OPCODE_BRANCH: begin // rs1, rs2
            return is_register_readable(rs1, ex_saved, rf_status) && 
                    is_register_readable(rs2, ex_saved, rf_status);
        end
        RV32I_OPCODE_FENCE, RV32I_OPCODE_SYSTEM: begin // rd, rs1
            return (rf_status[rs1] == GECKO_DECODE_REG_VALID) &&
                    (rf_status[rd] == GECKO_DECODE_REG_VALID);
        end
        default: begin
            return 'b1;
        end
        endcase
    endfunction

    function automatic gecko_execute_operation_t create_execute_op(
            input rv32_fields_t instruction_fields,
            input rv32_reg_addr_t execute_saved_reg,
            input rv32_reg_value_t rs1_value, rs2_value,
            input rv32_reg_value_t pc
    );
        gecko_execute_operation_t execute_op;
        execute_op.speculative = 'b0;

        // Default Execute Command Values
        execute_op.reg_addr = instruction_fields.rd;

        execute_op.reuse_rs1 = (execute_saved_reg != 'b0 && execute_saved_reg == instruction_fields.rs1);
        execute_op.reuse_rs2 = (execute_saved_reg != 'b0 && execute_saved_reg == instruction_fields.rs2);
        execute_op.reuse_mem = (execute_saved_reg != 'b0 && execute_saved_reg == instruction_fields.rs2);

        execute_op.rs1_value = rs1_value;
        execute_op.rs2_value = rs2_value;

        execute_op.mem_value = rs2_value;
        execute_op.immediate_value = instruction_fields.imm;

        case (rv32i_opcode_t'(instruction_fields.opcode))
        RV32I_OPCODE_OP: begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = instruction_fields.funct3;
            execute_op.alu_alternate = (instruction_fields.funct7 == RV32I_FUNCT7_ALT_INT) ? 
                    GECKO_ALTERNATE : GECKO_NORMAL;
            execute_op.alu_alternate = GECKO_NORMAL; // wack
        end
        RV32I_OPCODE_IMM: begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = instruction_fields.funct3;
            // Only allow alternate modes for the ALU
            execute_op.alu_alternate = (instruction_fields.funct7 == RV32I_FUNCT7_ALT_INT && 
                    instruction_fields.funct3 == RV32I_FUNCT3_IR_SRL_SRA) ? GECKO_ALTERNATE : GECKO_NORMAL;
            
            execute_op.rs2_value = instruction_fields.imm;
            execute_op.reuse_rs2 = 'b0; // rs2 will be an immediate
        end
        RV32I_OPCODE_LUI: begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = RV32I_FUNCT3_IR_ADD_SUB;
            execute_op.alu_alternate = GECKO_NORMAL;
            
            execute_op.rs1_value = 'b0;
            execute_op.rs2_value = instruction_fields.imm;
            execute_op.reuse_rs1 = 'b0;
            execute_op.reuse_rs2 = 'b0;
        end
        RV32I_OPCODE_AUIPC: begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = RV32I_FUNCT3_IR_ADD_SUB;
            execute_op.alu_alternate = GECKO_NORMAL;

            execute_op.rs1_value = pc;
            execute_op.rs2_value = instruction_fields.imm;
            execute_op.reuse_rs1 = 'b0;
            execute_op.reuse_rs2 = 'b0;
        end
        RV32I_OPCODE_LOAD: begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_LOAD;
            execute_op.op = instruction_fields.funct3;
            execute_op.alu_alternate = GECKO_NORMAL;

            execute_op.rs2_value = instruction_fields.imm;
            execute_op.reuse_rs2 = 'b0; // rs2 will be an immediate
        end
        RV32I_OPCODE_STORE: begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_STORE;
            execute_op.op = instruction_fields.funct3;
            execute_op.alu_alternate = GECKO_NORMAL;

            execute_op.rs2_value = instruction_fields.imm;
            execute_op.reuse_rs2 = 'b0; // rs2 will be an immediate
        end
        RV32I_OPCODE_JAL: begin // Jump
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = RV32I_FUNCT3_IR_ADD_SUB;
            execute_op.alu_alternate = GECKO_NORMAL;

            execute_op.rs1_value = pc;
            execute_op.rs2_value = 'd4;
            execute_op.reuse_rs1 = 'b0;
            execute_op.reuse_rs2 = 'b0;
        end
        RV32I_OPCODE_JALR: begin // Jump
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = RV32I_FUNCT3_IR_ADD_SUB;
            execute_op.alu_alternate = GECKO_NORMAL;

            execute_op.rs1_value = pc;
            execute_op.rs2_value = 'd4;
            execute_op.reuse_rs1 = 'b0;
            execute_op.reuse_rs2 = 'b0;
        end
        RV32I_OPCODE_BRANCH: begin // Conditional Jump
            execute_op.op_type = GECKO_EXECUTE_TYPE_BRANCH;
            execute_op.op = instruction_fields.funct3;
            execute_op.alu_alternate = GECKO_NORMAL;
        end
        default: begin // Invalid instruction
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = RV32I_FUNCT3_IR_ADD_SUB;
            execute_op.alu_alternate = GECKO_NORMAL;

            execute_op.reg_addr = 'b0; // Write to x0, do nothing
        end
        endcase

        return execute_op;
    endfunction

    function automatic gecko_system_operation_t create_system_op(
            input rv32_fields_t instruction_fields,
            input rv32_reg_addr_t execute_saved_reg,
            input rv32_reg_value_t rs1_value, rs2_value
    );
        gecko_system_operation_t system_op;

        system_op.imm_value = {{27{instruction_fields.rs1[4]}}, instruction_fields.rs1};
        system_op.rs1_value = rs1_value;
        system_op.rd_addr = instruction_fields.rd;
        system_op.sys_op = rv32i_funct3_sys_t'(instruction_fields.funct3);
        system_op.csr = instruction_fields.funct12;

        return system_op;
    endfunction

    function automatic gecko_jump_command_t create_jump_op(
            input rv32_fields_t instruction_fields,
            input rv32_reg_addr_t execute_saved_reg,
            input rv32_reg_value_t rs1_value, rs2_value
    );
        gecko_jump_command_t jump_cmd;

        jump_cmd.absolute_addr = rs1_value;
        jump_cmd.relative_addr = instruction_fields.imm;

        case (rv32i_opcode_t'(instruction_fields.opcode))
        RV32I_OPCODE_JAL: jump_cmd.absolute_jump = 'b0;
        RV32I_OPCODE_JALR: jump_cmd.absolute_jump = 'b1;
        endcase

        return jump_cmd;
    endfunction

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
    gecko_decode_reg_file_status_t reg_file_status, next_reg_file_status;
    rv32_reg_addr_t execute_saved, next_execute_saved;

    gecko_system_operation_t next_system_command; 
    gecko_execute_operation_t next_execute_command;
    gecko_jump_command_t next_jump_command; 

    always_ff @(posedge clk) begin
        if(rst) begin
            state <= GECKO_DECODE_RESET;
            reset_counter <= 'b0;
            jump_flag <= 'b0;
            speculative_counter <= 'b0;
            for (int i = 0; i < 32; i++) begin
                reg_file_status[i] <= GECKO_DECODE_REG_VALID;
            end
            execute_saved <= 'b0;
        end else begin
            state <= next_state;
            reset_counter <= next_reset_counter;
            jump_flag <= next_jump_flag;
            speculative_counter <= next_speculative_counter;
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
        automatic logic send_operation, reg_file_ready;

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

        // Halt incoming speculative writes until speculation resolved
        if (state == GECKO_DECODE_SPECULATIVE) begin
            writeback_result.ready = !writeback_in.speculative;
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
                                           register_read_value0, register_read_value1);

        instruction_requirements = find_instruction_requirements(instruction_fields);
        reg_file_ready = is_register_file_ready(instruction_fields, execute_saved, reg_file_status);

        register_write_enable = 'b0;
        register_write_addr = reset_counter;
        register_write_value = 'b0;

        next_state = state;
        next_reset_counter = reset_counter + 'b1;
        next_execute_saved = execute_saved;
        next_jump_flag = jump_flag;
        next_speculative_counter = speculative_counter;
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
                consume_instruction = 'b1;
                send_operation = 'b1;
                case (rv32i_opcode_t'(instruction_fields.opcode))
                RV32I_OPCODE_JAL, RV32I_OPCODE_JALR: 
                    next_jump_flag = next_jump_flag + 'b1;
                RV32I_OPCODE_BRANCH: 
                    next_state = GECKO_DECODE_SPECULATIVE;
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
                    next_speculative_counter = next_speculative_counter + 'b1;
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
                RV32I_OPCODE_BRANCH: begin // Can't speculatively branch while cleaning up misprediction 
                end
                default: begin 
                    consume_instruction = 'b1;
                    send_operation = 'b1;
                end
                endcase
            end
        end
        endcase

        rd_status = next_reg_file_status[instruction_fields.rd];

        if (send_operation) begin
            case (rv32i_opcode_t'(instruction_fields.opcode))
            RV32I_OPCODE_OP, RV32I_OPCODE_IMM, RV32I_OPCODE_LUI, RV32I_OPCODE_AUIPC: begin
                produce_execute = 'b1;
                next_execute_saved = next_execute_command.reg_addr;
                rd_status = write_register_state(rd_status, 'b1);
            end
            RV32I_OPCODE_LOAD: begin
                produce_execute = 'b1;
                if (execute_saved == next_execute_command.reg_addr) begin
                    next_execute_saved = 'b0;
                end
                rd_status = write_register_state(rd_status, 'b0);
            end
            RV32I_OPCODE_STORE: begin
                produce_execute = 'b1;
                rd_status = write_register_state(rd_status, 'b0);
            end
            RV32I_OPCODE_JAL, RV32I_OPCODE_JALR: begin
                produce_jump = 'b1;
                produce_execute = 'b1;
                next_execute_saved = next_execute_command.reg_addr;
                rd_status = write_register_state(rd_status, 'b1);
            end
            RV32I_OPCODE_BRANCH: begin
                produce_execute = 'b1;
            end
            RV32I_OPCODE_SYSTEM: begin
                produce_system = 'b1;
                if (execute_saved == next_system_command.rd_addr) begin
                    next_execute_saved = 'b0;
                end
                rd_status = write_register_state(rd_status, 'b0);
            end
            endcase
            next_reg_file_status[instruction_fields.rd] = rd_status;
        end

        // DANGER: Uses the enable signal to prevent state changes from earlier
        //         which is only needed because of the following interrupts
        if (!enable) begin
            next_state = state;
            next_reset_counter = reset_counter + 'b1;
            next_execute_saved = execute_saved;
            next_jump_flag = jump_flag;
            next_speculative_counter = speculative_counter;
            next_reg_file_status = reg_file_status;
        end

        // Handle writing back to the register file
        if (writeback_result.valid && writeback_result.ready) begin
            // Throw away writes to x0 and mispeculated results
            if (writeback_in.addr != 'b0 && !(state == GECKO_DECODE_MISPREDICTED && writeback_in.speculative)) begin
                case (next_reg_file_status[writeback_in.addr])
                GECKO_DECODE_REG_EXECUTE1: 
                    next_reg_file_status[writeback_in.addr] = GECKO_DECODE_REG_EXECUTE0;
                default: 
                    next_reg_file_status[writeback_in.addr] = GECKO_DECODE_REG_VALID;
                endcase
                register_write_enable = 'b1;
                register_write_addr = writeback_in.addr;
                register_write_value = writeback_in.value;
            end
            // Countdown when speculative writeback occurs
            if (writeback_in.speculative) begin
                next_speculative_counter = next_speculative_counter - 'b1;
                if (next_speculative_counter == 0) begin
                    next_state = GECKO_DECODE_NORMAL;
                end
            end
        end

        // Handle incoming branch signals
        if (branch_signal.valid && branch_signal.ready) begin
            if (branch_cmd_in.branch) begin
                next_state = GECKO_DECODE_MISPREDICTED;
                next_jump_flag = next_jump_flag + 'b1;
                next_execute_saved = 'b0;
            end else begin
                next_state = GECKO_DECODE_NORMAL;
                next_speculative_counter = 'b0;
            end
        end
    end

endmodule
