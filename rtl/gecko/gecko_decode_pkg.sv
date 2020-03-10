//!import riscv/riscv_pkg
//!import riscv/riscv32_pkg
//!import riscv/riscv32i_pkg
//!import riscv/riscv32m_pkg
//!import riscv/riscv32f_pkg
//!import riscv/riscv32v_pkg
//!import gecko/gecko_pkg

package gecko_decode_pkg;

    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import riscv32m_pkg::*;
    import riscv32f_pkg::*;
    import riscv32v_pkg::*;
    import gecko_pkg::*;

    typedef gecko_reg_status_t gecko_decode_reg_file_status_t [32];
    typedef gecko_reg_status_t gecko_decode_reg_file_counter_t [32];

    typedef struct packed {
        logic rs1_valid, rs2_valid, rd_valid;
    } gecko_decode_operands_status_t;

    typedef struct packed {
        logic execute, system, float, error;
    } gecko_decode_opcode_status_t;

    function automatic riscv32_reg_addr_t update_execute_saved(
            input riscv32_fields_t instruction_fields,
            input riscv32_reg_addr_t current_execute_saved
    );
        case (riscv32i_opcode_t'(instruction_fields.opcode))
        RISCV32I_OPCODE_OP, RISCV32I_OPCODE_IMM, 
        RISCV32I_OPCODE_LUI, RISCV32I_OPCODE_AUIPC,
        RISCV32I_OPCODE_JAL, RISCV32I_OPCODE_JALR: begin
            // Execute has new result
            return instruction_fields.rd;
        end
        RISCV32I_OPCODE_LOAD: begin
            // Execute result superceded
            if (current_execute_saved == instruction_fields.rd) begin
                return 'b0;
            end
        end
        RISCV32I_OPCODE_SYSTEM: begin
            case (riscv32i_funct3_sys_t'(instruction_fields.funct3))
            RISCV32I_FUNCT3_SYS_CSRRW, RISCV32I_FUNCT3_SYS_CSRRS, 
            RISCV32I_FUNCT3_SYS_CSRRC, RISCV32I_FUNCT3_SYS_CSRRWI, 
            RISCV32I_FUNCT3_SYS_CSRRSI, RISCV32I_FUNCT3_SYS_CSRRCI: begin
                // Execute result superceded
                if (current_execute_saved == instruction_fields.rd) begin
                    return 'b0;
                end
            end
            endcase
        end
        endcase
        case (riscv32f_opcode_t'(instruction_fields.opcode))
        RISCV32F_OPCODE_FP_OP_S: begin
            case (riscv32f_funct7_t'(instruction_fields.funct7))
            RISCV32F_FUNCT7_FCVT_W_S, RISCV32F_FUNCT7_FMV_X_W, RISCV32F_FUNCT7_FCMP_S: begin
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
            input riscv32_fields_t instruction_fields
    );
        gecko_decode_opcode_status_t status = '{default: 'b0};
        case (riscv32i_opcode_t'(instruction_fields.opcode))
        RISCV32I_OPCODE_OP, RISCV32I_OPCODE_IMM, RISCV32I_OPCODE_LUI, 
        RISCV32I_OPCODE_AUIPC, RISCV32I_OPCODE_LOAD: begin
            status.execute = (instruction_fields.rd != 'b0);
        end
        RISCV32I_OPCODE_STORE, RISCV32I_OPCODE_JAL, 
        RISCV32I_OPCODE_JALR, RISCV32I_OPCODE_BRANCH: begin
            status.execute = 'b1;
        end
        RISCV32I_OPCODE_SYSTEM: begin
            case (riscv32i_funct3_sys_t'(instruction_fields.funct3))
            RISCV32I_FUNCT3_SYS_ENV: begin
            end
            RISCV32I_FUNCT3_SYS_CSRRW, RISCV32I_FUNCT3_SYS_CSRRS, 
            RISCV32I_FUNCT3_SYS_CSRRC, RISCV32I_FUNCT3_SYS_CSRRWI, 
            RISCV32I_FUNCT3_SYS_CSRRSI, RISCV32I_FUNCT3_SYS_CSRRCI: begin
                case (instruction_fields.funct12)
                RISCV32I_CSR_CYCLE, RISCV32I_CSR_TIME, RISCV32I_CSR_INSTRET, 
                RISCV32I_CSR_CYCLEH, RISCV32I_CSR_TIMEH, RISCV32I_CSR_INSTRETH: begin
                    status.system = 'b1;
                end
                RISCV32F_CSR_FFLAGS, RISCV32F_CSR_FRM, RISCV32F_CSR_FCSR, RISCV32V_CSR_VL: begin
                    status.float = 'b1;
                end
                default: status.error = 'b1;
                endcase
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

        case (riscv32f_opcode_t'(instruction_fields.opcode))
        RISCV32F_OPCODE_FLW, RISCV32F_OPCODE_FSW,
        RISCV32F_OPCODE_FMADD_S, RISCV32F_OPCODE_FMSUB_S,
        RISCV32F_OPCODE_FNMSUB_S, RISCV32F_OPCODE_FNMADD_S, RISCV32F_OPCODE_FP_OP_S: begin
            status.float = 'b1;
            status.error = 'b0;
        end
        endcase
        
        case (riscv32v_opcode_t'(instruction_fields.opcode))
        RISCV32V_OPCODE_OP: begin
            case(riscv32v_funct3_t'(instruction_fields.funct3))
            RISCV32V_FUNCT3_OP_FVV: begin // Floating Point Vector-Vector
                case (riscv32v_funct6_t'(instruction_fields.funct6))
                RISCV32V_FUNCT6_VFADD, RISCV32V_FUNCT6_VFSUB, RISCV32V_FUNCT6_VFDIV, 
                RISCV32V_FUNCT6_VFSQRT, RISCV32V_FUNCT6_VFMUL, RISCV32V_FUNCT6_VFMACC,
                RISCV32V_FUNCT6_VFNMACC, RISCV32V_FUNCT6_VFMSAC, RISCV32V_FUNCT6_VFNMSAC: begin
                    status.float = 'b1;
                    status.error = 'b0;
                end
                endcase
            end
            RISCV32V_FUNCT3_OP_FVF: begin // Floating Point Vector-Scalar
                case (riscv32v_funct6_t'(instruction_fields.funct6))
                RISCV32V_FUNCT6_VFADD, RISCV32V_FUNCT6_VFSUB, RISCV32V_FUNCT6_VFDIV,
                RISCV32V_FUNCT6_VFSQRT, RISCV32V_FUNCT6_VFRDIV, RISCV32V_FUNCT6_VFMUL: begin
                    status.float = 'b1;
                    status.error = 'b0;
                end
                endcase
            end
            RISCV32V_FUNCT3_OP_IVI: begin // Integer Vector-Immediate (Slideup/Slidedown)
                case (riscv32v_funct6_t'(instruction_fields.funct6))
                RISCV32V_FUNCT6_VSLIDEUP, RISCV32V_FUNCT6_VSLIDEDOWN: begin
                    status.float = 'b1;
                    status.error = 'b0;
                end
                endcase
            end
            endcase
        end
        endcase
        
        return status;
    endfunction

    function automatic logic is_opcode_control_flow(
            input riscv32_fields_t instruction_fields
    );
        case (riscv32i_opcode_t'(instruction_fields.opcode))
        RISCV32I_OPCODE_JAL, RISCV32I_OPCODE_JALR, 
        RISCV32I_OPCODE_BRANCH: return 'b1;
        default: return 'b0;
        endcase
    endfunction

    function automatic logic is_opcode_side_effects(
            input riscv32_fields_t instruction_fields
    );
        case (riscv32i_opcode_t'(instruction_fields.opcode))
        RISCV32I_OPCODE_OP, RISCV32I_OPCODE_IMM, 
        RISCV32I_OPCODE_LUI, RISCV32I_OPCODE_AUIPC: return 'b0;
        default: return 'b1;
        endcase
    endfunction

    function automatic logic is_instruction_ecall(
            input riscv32_fields_t instruction_fields
    );
        return (instruction_fields.opcode == RISCV32I_OPCODE_SYSTEM) &&
                (instruction_fields.funct3 == RISCV32I_FUNCT3_SYS_ENV) &&
                (instruction_fields.funct12 == RISCV32I_CSR_ECALL);
    endfunction

    function automatic logic is_instruction_ebreak(
            input riscv32_fields_t instruction_fields
    );
        return (instruction_fields.opcode == RISCV32I_OPCODE_SYSTEM) &&
                (instruction_fields.funct3 == RISCV32I_FUNCT3_SYS_ENV) &&
                (instruction_fields.funct12 == RISCV32I_CSR_EBREAK);
    endfunction

    function automatic logic does_opcode_writeback (
            input riscv32_fields_t instruction_fields
    );
        case (riscv32i_opcode_t'(instruction_fields.opcode))
        RISCV32I_OPCODE_OP, RISCV32I_OPCODE_IMM,
        RISCV32I_OPCODE_LOAD, RISCV32I_OPCODE_LUI,
        RISCV32I_OPCODE_AUIPC, RISCV32I_OPCODE_JAL,
        RISCV32I_OPCODE_JALR, RISCV32I_OPCODE_FENCE: return (instruction_fields.rd != 'b0);
        RISCV32I_OPCODE_STORE, RISCV32I_OPCODE_BRANCH: return 'b0;
        RISCV32I_OPCODE_SYSTEM: begin
            case (riscv32i_funct3_sys_t'(instruction_fields.funct3))
            RISCV32I_FUNCT3_SYS_CSRRW, RISCV32I_FUNCT3_SYS_CSRRS, 
            RISCV32I_FUNCT3_SYS_CSRRC, RISCV32I_FUNCT3_SYS_CSRRWI, 
            RISCV32I_FUNCT3_SYS_CSRRSI, RISCV32I_FUNCT3_SYS_CSRRCI: begin
                return (instruction_fields.rd != 'b0);
            end
            default: return 'b0;
            endcase
        end
        endcase

        case (riscv32f_opcode_t'(instruction_fields.opcode))
        RISCV32F_OPCODE_FP_OP_S: begin
            case (riscv32f_funct7_t'(instruction_fields.funct7))
            RISCV32F_FUNCT7_FCVT_W_S, RISCV32F_FUNCT7_FMV_X_W, 
            RISCV32F_FUNCT7_FCMP_S: return (instruction_fields.rd != 'b0);
            default: return 'b0;
            endcase
        end
        // RISCV32F_OPCODE_FLW, RISCV32F_OPCODE_FSW,
        // RISCV32F_OPCODE_FMADD_S, RISCV32F_OPCODE_FMSUB_S,
        // RISCV32F_OPCODE_FNMSUB_S, RISCV32F_OPCODE_FNMADD_S: begin
        //     return 'b0;
        // end
        endcase

        return 'b0;
    endfunction

    function automatic logic is_register_readable(
            input riscv32_reg_addr_t reg_addr,
            input riscv32_reg_addr_t execute_saved_reg,
            input gecko_reg_status_t reg_status
    );
        return (reg_addr == execute_saved_reg || reg_status == GECKO_REG_STATUS_VALID);
    endfunction

    function automatic logic is_register_writeable(
            input gecko_reg_status_t reg_status
    );
        return reg_status != GECKO_REG_STATUS_FULL;
    endfunction

    function automatic gecko_decode_operands_status_t gecko_decode_find_operand_status(
            input riscv32_fields_t instruction_fields,
            input riscv32_reg_addr_t ex_saved,
            input gecko_reg_status_t rd_front_status, rd_rear_status,
            input gecko_reg_status_t rs1_front_status, rs1_rear_status,
            input gecko_reg_status_t rs2_front_status, rs2_rear_status
    );
        riscv32_reg_addr_t rd, rs1, rs2;
        gecko_reg_status_t rd_status, rs1_status, rs2_status;
        gecko_decode_operands_status_t op_status, op_required;

        rd = instruction_fields.rd;
        rs1 = instruction_fields.rs1;
        rs2 = instruction_fields.rs2;

        rd_status = rd_front_status - rd_rear_status;
        rs1_status = rs1_front_status - rs1_rear_status;
        rs2_status = rs2_front_status - rs2_rear_status;

        op_status = '{
                rs1_valid: is_register_readable(rs1, ex_saved, rs1_status),
                rs2_valid: is_register_readable(rs2, ex_saved, rs2_status),
                rd_valid: is_register_writeable(rd_status)
        };

        op_required = '{rs1_valid: 'b0, rs2_valid: 'b0, rd_valid: 'b0};

        case (riscv32i_opcode_t'(instruction_fields.opcode))
        RISCV32I_OPCODE_OP: op_required = '{rs1_valid: 'b1, rs2_valid: 'b1, rd_valid: 'b1};
        RISCV32I_OPCODE_IMM,
        RISCV32I_OPCODE_LOAD, 
        RISCV32I_OPCODE_JALR: op_required = '{rs1_valid: 'b1, rs2_valid: 'b0, rd_valid: 'b1};
        RISCV32I_OPCODE_STORE, 
        RISCV32I_OPCODE_BRANCH: op_required = '{rs1_valid: 'b1, rs2_valid: 'b1, rd_valid: 'b0};
        RISCV32I_OPCODE_LUI, 
        RISCV32I_OPCODE_AUIPC, 
        RISCV32I_OPCODE_JAL: op_required = '{rs1_valid: 'b0, rs2_valid: 'b0, rd_valid: 'b1};
        RISCV32I_OPCODE_SYSTEM: begin // rd, rs1
            case (riscv32i_funct3_sys_t'(instruction_fields.funct3))
            RISCV32I_FUNCT3_SYS_ENV: begin // a0, a1 (not from execute)
                return '{
                    rs1_valid: is_register_readable(rs1, 'b0, rs1_status), 
                    rs2_valid: is_register_readable(rs2, 'b0, rs2_status),
                    rd_valid: 'b1
                };
            end
            default: begin
                return '{
                    rs1_valid: is_register_readable(rs1, 'b0, rs1_status), 
                    rs2_valid: 'b1,
                    rd_valid: is_register_writeable(rd_status)
                };
            end
            endcase
        end
        endcase

        case (riscv32f_opcode_t'(instruction_fields.opcode))
        RISCV32F_OPCODE_FLW, RISCV32F_OPCODE_FSW: begin
            return '{
                rs1_valid: is_register_readable(rs1, 'b0, rs1_status), 
                rs2_valid: 'b1,
                rd_valid: 'b1
            };
        end
        RISCV32F_OPCODE_FP_OP_S: begin
            case (riscv32f_funct7_t'(instruction_fields.funct7))
            RISCV32F_FUNCT7_FCVT_W_S, RISCV32F_FUNCT7_FMV_X_W, RISCV32F_FUNCT7_FCMP_S: begin
                return '{
                    rs1_valid: 'b1, 
                    rs2_valid: 'b1,
                    rd_valid: is_register_writeable(rd_status)
                };
            end
            RISCV32F_FUNCT7_FCVT_S_W, RISCV32F_FUNCT7_FMV_W_X: begin
                return '{
                    rs1_valid: is_register_readable(rs1, 'b0, rs1_status), 
                    rs2_valid: 'b1,
                    rd_valid: 'b1
                };
            end
            endcase
        end
        endcase

        return '{
                rs1_valid: op_required.rs1_valid ? op_status.rs1_valid : 'b1,
                rs2_valid: op_required.rs2_valid ? op_status.rs2_valid : 'b1,
                rd_valid: op_required.rd_valid ? op_status.rd_valid : 'b1
        };
    endfunction

    function automatic gecko_execute_operation_t create_execute_op(
            input riscv32_fields_t instruction_fields,
            input gecko_instruction_operation_t instruction_op,
            input riscv32_reg_addr_t execute_saved_reg,
            input riscv32_reg_value_t rs1_value, rs2_value,
            input gecko_reg_status_t reg_status,
            input gecko_jump_flag_t jump_flag,
            input logic speculative_operation
    );
        gecko_execute_operation_t execute_op;
        execute_op.speculative = 'b0;
        execute_op.halt = 'b0;

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
        execute_op.jump_value = instruction_op.pc;

        execute_op.prediction = instruction_op.prediction;
        execute_op.next_pc = instruction_op.next_pc;
        execute_op.current_pc = instruction_op.pc;

        execute_op.reg_status = reg_status;
        execute_op.jump_flag = jump_flag;
        execute_op.speculative = speculative_operation;

        case (riscv32i_opcode_t'(instruction_fields.opcode))
        RISCV32I_OPCODE_OP: begin
            execute_op.op_type = (instruction_fields.funct7 == RISCV32M_FUNCT7_MUL_DIV) ? 
                    GECKO_EXECUTE_TYPE_MUL_DIV : GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = instruction_fields.funct3;
            execute_op.alu_alternate = (instruction_fields.funct7 == RISCV32I_FUNCT7_ALT_INT) ? 
                    GECKO_ALTERNATE : GECKO_NORMAL;
        end
        RISCV32I_OPCODE_IMM: begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = instruction_fields.funct3;
            // Only allow alternate modes for the ALU
            execute_op.alu_alternate = (instruction_fields.funct7 == RISCV32I_FUNCT7_ALT_INT && 
                    instruction_fields.funct3 == RISCV32I_FUNCT3_IR_SRL_SRA) ? GECKO_ALTERNATE : GECKO_NORMAL;
            
            execute_op.rs2_value = instruction_fields.imm;
            execute_op.reuse_rs2 = 'b0; // rs2 will be an immediate
        end
        RISCV32I_OPCODE_LUI: begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = RISCV32I_FUNCT3_IR_ADD_SUB;
            execute_op.alu_alternate = GECKO_NORMAL;
            
            execute_op.rs1_value = 'b0;
            execute_op.rs2_value = instruction_fields.imm;
            execute_op.reuse_rs1 = 'b0;
            execute_op.reuse_rs2 = 'b0;
        end
        RISCV32I_OPCODE_AUIPC: begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = RISCV32I_FUNCT3_IR_ADD_SUB;
            execute_op.alu_alternate = GECKO_NORMAL;

            execute_op.rs1_value = instruction_op.pc;
            execute_op.rs2_value = instruction_fields.imm;
            execute_op.reuse_rs1 = 'b0;
            execute_op.reuse_rs2 = 'b0;
        end
        RISCV32I_OPCODE_LOAD: begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_LOAD;
            execute_op.op = instruction_fields.funct3;
            execute_op.alu_alternate = GECKO_NORMAL;

            execute_op.rs2_value = instruction_fields.imm;
            execute_op.reuse_rs2 = 'b0; // rs2 will be an immediate
        end
        RISCV32I_OPCODE_STORE: begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_STORE;
            execute_op.op = instruction_fields.funct3;
            execute_op.alu_alternate = GECKO_NORMAL;

            execute_op.rs2_value = instruction_fields.imm;
            execute_op.reuse_rs2 = 'b0; // rs2 will be an immediate
        end
        RISCV32I_OPCODE_JAL: begin // Jump
            execute_op.op_type = GECKO_EXECUTE_TYPE_JUMP;
            execute_op.op = RISCV32I_FUNCT3_IR_ADD_SUB;
            execute_op.alu_alternate = GECKO_NORMAL;

            execute_op.rs1_value = instruction_op.pc;
            execute_op.rs2_value = 'd4;
            execute_op.reuse_rs1 = 'b0;
            execute_op.reuse_rs2 = 'b0;
        end
        RISCV32I_OPCODE_JALR: begin // Jump
            execute_op.op_type = GECKO_EXECUTE_TYPE_JUMP;
            execute_op.op = RISCV32I_FUNCT3_IR_ADD_SUB;
            execute_op.alu_alternate = GECKO_NORMAL;
            
            execute_op.jump_value = rs1_value;
            execute_op.reuse_jump = (execute_saved_reg != 'b0 && 
                    execute_saved_reg == instruction_fields.rs1);

            execute_op.rs1_value = instruction_op.pc;
            execute_op.rs2_value = 'd4;
            execute_op.reuse_rs1 = 'b0;
            execute_op.reuse_rs2 = 'b0;
        end
        RISCV32I_OPCODE_BRANCH: begin // Conditional Jump
            execute_op.op_type = GECKO_EXECUTE_TYPE_BRANCH;
            execute_op.op = instruction_fields.funct3;
            execute_op.alu_alternate = GECKO_NORMAL;
        end
        default: begin // Invalid instruction
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.op = RISCV32I_FUNCT3_IR_ADD_SUB;
            execute_op.alu_alternate = GECKO_NORMAL;

            execute_op.reg_addr = 'b0; // Write to x0, do nothing
        end
        endcase

        return execute_op;
    endfunction

    function automatic gecko_system_operation_t create_system_op(
            input riscv32_fields_t instruction_fields,
            input riscv32_reg_addr_t execute_saved_reg,
            input riscv32_reg_value_t rs1_value, rs2_value,
            input gecko_reg_status_t reg_status,
            input gecko_jump_flag_t jump_flag
    );
        gecko_system_operation_t system_op;

        system_op.imm_value = {{27{instruction_fields.rs1[4]}}, instruction_fields.rs1};
        system_op.rs1_value = rs1_value;
        system_op.reg_addr = instruction_fields.rd;
        system_op.sys_op = riscv32i_funct3_sys_t'(instruction_fields.funct3);
        system_op.csr = instruction_fields.funct12;
        system_op.reg_status = reg_status;
        system_op.jump_flag = jump_flag;

        return system_op;
    endfunction

    function automatic gecko_float_operation_t create_float_op(
            input riscv32_fields_t instruction_fields,
            input riscv32_reg_addr_t execute_saved_reg,
            input riscv32_reg_value_t rs1_value, rs2_value,
            input gecko_reg_status_t reg_status,
            input gecko_jump_flag_t jump_flag
    );
        gecko_float_operation_t float_op;

        float_op.instruction_fields = instruction_fields;
        float_op.dest_reg_addr = instruction_fields.rd;
        float_op.dest_reg_status = reg_status;
        float_op.jump_flag = jump_flag;
        float_op.rs1_value = rs1_value;
        float_op.enable_status_op = (instruction_fields.opcode == RISCV32I_OPCODE_SYSTEM);
        float_op.sys_op = riscv32i_funct3_sys_t'(instruction_fields.funct3);
        float_op.sys_imm = {{27{instruction_fields.rs1[4]}}, instruction_fields.rs1};
        float_op.sys_csr = instruction_fields.funct12;

        return float_op;
    endfunction

    function automatic gecko_ecall_operation_t create_ecall_op(
            input riscv32_fields_t instruction_fields,
            input riscv32_reg_addr_t execute_saved_reg,
            input riscv32_reg_value_t rs1_value, rs2_value,
            input gecko_reg_status_t reg_status,
            input gecko_jump_flag_t jump_flag
    );
        gecko_ecall_operation_t ecall_op;

        ecall_op.operation = rs1_value[7:0];
        ecall_op.data = rs2_value[7:0];

        return ecall_op;
    endfunction

endpackage
