`ifndef __GECKO_DECODE_UTIL__
`define __GECKO_DECODE_UTIL__

`ifdef __SIMULATION__
`include "../isa/rv.svh"
`include "../isa/rv32.svh"
`include "../isa/rv32i.svh"
`include "gecko.svh"
`endif

package gecko_decode_util;

    import rv32::*;
    import rv32i::*;
    import gecko::*;

    typedef gecko_reg_status_t gecko_decode_reg_file_status_t [32];
    typedef gecko_reg_status_t gecko_decode_reg_file_counter_t [32];

    typedef struct packed {
        logic rs1_valid, rs2_valid, rd_valid;
    } gecko_decode_operands_status_t;

    typedef struct packed {
        logic execute, system, error;
    } gecko_decode_opcode_status_t;

    function automatic rv32_reg_addr_t update_execute_saved(
            input rv32_fields_t instruction_fields,
            input rv32_reg_addr_t current_execute_saved
    );
        case (rv32i_opcode_t'(instruction_fields.opcode))
        RV32I_OPCODE_OP, RV32I_OPCODE_IMM, 
        RV32I_OPCODE_LUI, RV32I_OPCODE_AUIPC,
        RV32I_OPCODE_JAL, RV32I_OPCODE_JALR: begin
            // Execute has new result
            return instruction_fields.rd;
        end
        RV32I_OPCODE_LOAD: begin
            // Execute result superceded
            if (current_execute_saved == instruction_fields.rd) begin
                return 'b0;
            end
        end
        RV32I_OPCODE_SYSTEM: begin
            case (rv32i_funct3_sys_t'(instruction_fields.funct3))
            RV32I_FUNCT3_SYS_CSRRW, RV32I_FUNCT3_SYS_CSRRS, 
            RV32I_FUNCT3_SYS_CSRRC, RV32I_FUNCT3_SYS_CSRRWI, 
            RV32I_FUNCT3_SYS_CSRRSI, RV32I_FUNCT3_SYS_CSRRCI: begin
                // Execute result superceded
                if (current_execute_saved == instruction_fields.rd) begin
                    return 'b0;
                end
            end
            endcase
        end
        endcase
        return current_execute_saved;
    endfunction

    function automatic gecko_decode_opcode_status_t get_opcode_status(
            input rv32_fields_t instruction_fields
    );
        gecko_decode_opcode_status_t status = '{default: 'b0};
        case (rv32i_opcode_t'(instruction_fields.opcode))
        RV32I_OPCODE_OP, RV32I_OPCODE_IMM, RV32I_OPCODE_LUI, 
        RV32I_OPCODE_AUIPC, RV32I_OPCODE_LOAD: begin
            status.execute = (instruction_fields.rd != 'b0);
        end
        RV32I_OPCODE_STORE, RV32I_OPCODE_JAL, 
        RV32I_OPCODE_JALR, RV32I_OPCODE_BRANCH: begin
            status.execute = 'b1;
        end
        RV32I_OPCODE_SYSTEM: begin
            case (rv32i_funct3_sys_t'(instruction_fields.funct3))
            RV32I_FUNCT3_SYS_ENV: begin
            end
            RV32I_FUNCT3_SYS_CSRRW, RV32I_FUNCT3_SYS_CSRRS, 
            RV32I_FUNCT3_SYS_CSRRC, RV32I_FUNCT3_SYS_CSRRWI, 
            RV32I_FUNCT3_SYS_CSRRSI, RV32I_FUNCT3_SYS_CSRRCI: begin
                status.system = 'b1;
            end
            default: begin
                status.error = 'b1;
            end
            endcase
        end
        default: begin
            status.error = 'b1;
        end
        endcase
        return status;
    endfunction

    function automatic logic is_opcode_control_flow(
            input rv32_fields_t instruction_fields
    );
        case (rv32i_opcode_t'(instruction_fields.opcode))
        RV32I_OPCODE_JAL, RV32I_OPCODE_JALR, 
        RV32I_OPCODE_BRANCH: return 'b1;
        default: return 'b0;
        endcase
    endfunction

    function automatic logic is_opcode_side_effects(
            input rv32_fields_t instruction_fields
    );
        case (rv32i_opcode_t'(instruction_fields.opcode))
        RV32I_OPCODE_OP, RV32I_OPCODE_IMM, 
        RV32I_OPCODE_LUI, RV32I_OPCODE_AUIPC: return 'b0;
        default: return 'b1;
        endcase
    endfunction

    function automatic logic is_register_readable(
            input rv32_reg_addr_t reg_addr,
            input rv32_reg_addr_t execute_saved_reg,
            input gecko_decode_reg_file_status_t reg_file_status
    );
        return (reg_addr == execute_saved_reg || 
                reg_file_status[reg_addr] == GECKO_REG_STATUS_VALID);
    endfunction

    function automatic logic is_register_writeable(
            input rv32_reg_addr_t reg_addr,
            input gecko_decode_reg_file_status_t reg_file_status
    );
        return reg_file_status[reg_addr] != GECKO_REG_STATUS_FULL;
    endfunction

    function automatic gecko_decode_operands_status_t gecko_decode_find_operand_status(
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
            return '{
                rs1_valid: is_register_readable(rs1, ex_saved, rf_status), 
                rs2_valid: is_register_readable(rs2, ex_saved, rf_status),
                rd_valid: is_register_writeable(rd, rf_status)
            };
        end
        RV32I_OPCODE_IMM: begin // rd, rs1
            return '{
                rs1_valid: is_register_readable(rs1, ex_saved, rf_status), 
                rs2_valid: 'b1,
                rd_valid: is_register_writeable(rd, rf_status)
            };
        end
        RV32I_OPCODE_LOAD, RV32I_OPCODE_JALR: begin // rd, rs1
            return '{
                rs1_valid: is_register_readable(rs1, ex_saved, rf_status), 
                rs2_valid: 'b1,
                rd_valid: is_register_writeable(rd, rf_status)
            };
        end
        RV32I_OPCODE_STORE, RV32I_OPCODE_BRANCH: begin // rs1, rs2
            return '{
                rs1_valid: is_register_readable(rs1, ex_saved, rf_status), 
                rs2_valid: is_register_readable(rs2, ex_saved, rf_status),
                rd_valid: 'b1
            };
        end
        RV32I_OPCODE_LUI, RV32I_OPCODE_AUIPC, RV32I_OPCODE_JAL: begin // rd
            return '{
                rs1_valid: 'b1, 
                rs2_valid: 'b1,
                rd_valid: is_register_writeable(rd, rf_status)
            };
        end
        RV32I_OPCODE_SYSTEM: begin // rd, rs1
            case (rv32i_funct3_sys_t'(instruction_fields.funct3))
            RV32I_FUNCT3_SYS_ENV: begin // a0, a1 (not from execute)
                return '{
                    rs1_valid: is_register_readable(rs1, 'b0, rf_status), 
                    rs2_valid: is_register_readable(rs2, 'b0, rf_status),
                    rd_valid: 'b1
                };
            end
            default: begin
                return '{
                    rs1_valid: is_register_readable(rs1, 'b0, rf_status), 
                    rs2_valid: 'b1,
                    rd_valid: is_register_writeable(rd, rf_status)
                };
            end
            endcase
        end
        default: begin
            return '{default: 'b1};
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
        execute_op.reuse_jump = 'b0;

        execute_op.rs1_value = rs1_value;
        execute_op.rs2_value = rs2_value;

        execute_op.mem_value = rs2_value;
        execute_op.immediate_value = instruction_fields.imm;
        execute_op.jump_value = pc;

        case (rv32i_opcode_t'(instruction_fields.opcode))
        RV32I_OPCODE_OP: begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = instruction_fields.funct3;
            execute_op.alu_alternate = (instruction_fields.funct7 == RV32I_FUNCT7_ALT_INT) ? 
                    GECKO_ALTERNATE : GECKO_NORMAL;
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
            execute_op.op_type = GECKO_EXECUTE_TYPE_JUMP;
            execute_op.op = RV32I_FUNCT3_IR_ADD_SUB;
            execute_op.alu_alternate = GECKO_NORMAL;

            execute_op.rs1_value = pc;
            execute_op.rs2_value = 'd4;
            execute_op.reuse_rs1 = 'b0;
            execute_op.reuse_rs2 = 'b0;
        end
        RV32I_OPCODE_JALR: begin // Jump
            execute_op.op_type = GECKO_EXECUTE_TYPE_JUMP;
            execute_op.op = RV32I_FUNCT3_IR_ADD_SUB;
            execute_op.alu_alternate = GECKO_NORMAL;
            
            execute_op.jump_value = rs1_value;
            execute_op.reuse_jump = (execute_saved_reg != 'b0 && 
                    execute_saved_reg == instruction_fields.rs1);

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
        system_op.reg_addr = instruction_fields.rd;
        system_op.sys_op = rv32i_funct3_sys_t'(instruction_fields.funct3);
        system_op.csr = instruction_fields.funct12;

        return system_op;
    endfunction

    function automatic logic does_opcode_writeback (
            input rv32_fields_t instruction_fields
    );
        case (rv32i_opcode_t'(instruction_fields.opcode))
        RV32I_OPCODE_STORE, RV32I_OPCODE_BRANCH: begin
            return 'b0;
        end
        RV32I_OPCODE_SYSTEM: begin
            case (rv32i_funct3_sys_t'(instruction_fields.funct3))
            RV32I_FUNCT3_SYS_CSRRW, RV32I_FUNCT3_SYS_CSRRS, 
            RV32I_FUNCT3_SYS_CSRRC, RV32I_FUNCT3_SYS_CSRRWI, 
            RV32I_FUNCT3_SYS_CSRRSI, RV32I_FUNCT3_SYS_CSRRCI: begin
                return (instruction_fields.rd != 'b0);
            end
            default: return 'b0;
            endcase
        end
        default: return (instruction_fields.rd != 'b0);
        endcase
    endfunction

endpackage

`endif
