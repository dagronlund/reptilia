`ifndef __BASILISK_DECODE_UTIL__
`define __BASILISK_DECODE_UTIL__

`ifdef __LINTER__

`include "../isa/rv32.svh"
`include "../isa/rv32f.svh"
`include "../isa/rv32v.svh"
`include "../fpu/fpu.svh"
`include "../fpu/fpu_add.svh"
`include "../fpu/fpu_mult.svh"
`include "../fpu/fpu_divide.svh"
`include "../fpu/fpu_sqrt.svh"
`include "../gecko/gecko.svh"
`include "basilisk.svh"

`else

`include "rv32.svh"
`include "rv32f.svh"
`include "rv32v.svh"
`include "fpu.svh"
`include "fpu_add.svh"
`include "fpu_mult.svh"
`include "fpu_divide.svh"
`include "fpu_sqrt.svh"
`include "gecko.svh"
`include "basilisk.svh"

`endif

package basilisk_decode_util;

    import rv32::*;
    import rv32f::*;
    import rv32v::*;
    import fpu::*;
    import fpu_add::*;
    import fpu_mult::*;
    import fpu_divide::*;
    import fpu_sqrt::*;
    import gecko::*;
    import basilisk::*;

    typedef enum logic [1:0] {
        BASILISK_DECODE_REG_STATUS_VALID = 'b00,
        BASILISK_DECODE_REG_STATUS_INVALID = 'b01,
        BASILISK_DECODE_REG_STATUS_SLIDEUP = 'b10,
        BASILISK_DECODE_REG_STATUS_SLIDEDOWN = 'b11
    } basilisk_decode_reg_status_t;

    function automatic logic basilisk_decode_depend_rd(
            input rv32_fields_t inst_fields
    );
        case (rv32f_opcode_t'(inst_fields.opcode))
        RV32F_OPCODE_FLW: return 'b1;
        RV32F_OPCODE_FSW: return 'b0;
        RV32F_OPCODE_FMADD_S, RV32F_OPCODE_FMSUB_S,
        RV32F_OPCODE_FNMSUB_S, RV32F_OPCODE_FNMADD_S: return 'b1;
        RV32F_OPCODE_FP_OP_S: begin
            case (rv32f_funct7_t'(inst_fields.funct7))
            RV32F_FUNCT7_FADD_S, RV32F_FUNCT7_FSUB_S, 
            RV32F_FUNCT7_FMUL_S, RV32F_FUNCT7_FDIV_S, 
            RV32F_FUNCT7_FSQRT_S, RV32F_FUNCT7_FSGNJ_S, 
            RV32F_FUNCT7_FMIN_MAX_S: return 'b1;
            RV32F_FUNCT7_FCVT_S_W, RV32F_FUNCT7_FMV_W_X: return 'b1;
            RV32F_FUNCT7_FCVT_W_S, RV32F_FUNCT7_FMV_X_W, RV32F_FUNCT7_FCMP_S: return 'b0;
            endcase
        end
        endcase
        
        case (rv32v_opcode_t'(inst_fields.opcode))
        RV32V_OPCODE_OP: begin
            case (rv32v_funct3_t'(inst_fields.funct3))
            RV32V_FUNCT3_OP_FVV, RV32V_FUNCT3_OP_FVF, RV32V_FUNCT3_OP_IVI: return 'b1;
            endcase
        end
        endcase
        
        return 'b0;
    endfunction

    function automatic logic basilisk_decode_depend_rs1(
            input rv32_fields_t inst_fields
    );
        case (rv32f_opcode_t'(inst_fields.opcode))
        RV32F_OPCODE_FLW: return 'b0;
        RV32F_OPCODE_FSW: return 'b0;
        RV32F_OPCODE_FMADD_S, RV32F_OPCODE_FMSUB_S,
        RV32F_OPCODE_FNMSUB_S, RV32F_OPCODE_FNMADD_S: return 'b1;
        RV32F_OPCODE_FP_OP_S: begin
            case (rv32f_funct7_t'(inst_fields.funct7))
            RV32F_FUNCT7_FADD_S, RV32F_FUNCT7_FSUB_S, 
            RV32F_FUNCT7_FMUL_S, RV32F_FUNCT7_FDIV_S, 
            RV32F_FUNCT7_FSQRT_S, RV32F_FUNCT7_FSGNJ_S, 
            RV32F_FUNCT7_FMIN_MAX_S: return 'b1;
            RV32F_FUNCT7_FCVT_S_W, RV32F_FUNCT7_FMV_W_X: return 'b0;
            RV32F_FUNCT7_FCVT_W_S, RV32F_FUNCT7_FMV_X_W, RV32F_FUNCT7_FCMP_S: return 'b1;
            endcase
        end
        endcase

        case (rv32v_opcode_t'(inst_fields.opcode))
        RV32V_FUNCT3_OP_FVV, RV32V_FUNCT3_OP_FVF, RV32V_FUNCT3_OP_IVI: return 'b1;
        endcase

        case (rv32v_opcode_t'(inst_fields.opcode))
        RV32V_OPCODE_OP: begin
            case (rv32v_funct3_t'(inst_fields.funct3))
            RV32V_FUNCT3_OP_FVV, RV32V_FUNCT3_OP_FVF: begin
                case (rv32v_funct6_t'(inst_fields.funct6))
                RV32V_FUNCT6_VFSQRT: return 'b0;
                default: return 'b1;
                endcase
            end
            RV32V_FUNCT3_OP_IVI: return 'b0;
            endcase
        end
        endcase

        return 'b0;
    endfunction

    function automatic logic basilisk_decode_depend_rs2(
            input rv32_fields_t inst_fields
    );
        case (rv32f_opcode_t'(inst_fields.opcode))
        RV32F_OPCODE_FLW: return 'b0;
        RV32F_OPCODE_FSW: return 'b1;
        RV32F_OPCODE_FMADD_S, RV32F_OPCODE_FMSUB_S,
        RV32F_OPCODE_FNMSUB_S, RV32F_OPCODE_FNMADD_S: return 'b1;
        RV32F_OPCODE_FP_OP_S: begin
            case (rv32f_funct7_t'(inst_fields.funct7))
            RV32F_FUNCT7_FADD_S, RV32F_FUNCT7_FSUB_S, 
            RV32F_FUNCT7_FMUL_S, RV32F_FUNCT7_FDIV_S, 
            RV32F_FUNCT7_FSGNJ_S, RV32F_FUNCT7_FMIN_MAX_S: return 'b1;
            RV32F_FUNCT7_FSQRT_S: return 'b0;
            RV32F_FUNCT7_FCVT_S_W, RV32F_FUNCT7_FMV_W_X: return 'b0;
            RV32F_FUNCT7_FCVT_W_S, RV32F_FUNCT7_FMV_X_W: return 'b0;
            RV32F_FUNCT7_FCMP_S: return 'b1;
            endcase
        end
        endcase

        case (rv32v_opcode_t'(inst_fields.opcode))
        RV32V_OPCODE_OP: begin
            case (rv32v_funct3_t'(inst_fields.funct3))
            RV32V_FUNCT3_OP_FVV, RV32V_FUNCT3_OP_FVF, RV32V_FUNCT3_OP_IVI: return 'b1;
            endcase
        end
        endcase

        return 'b0;
    endfunction

    function automatic logic basilisk_decode_depend_rs3(
            input rv32_fields_t inst_fields
    );
        case (rv32f_opcode_t'(inst_fields.opcode))
        RV32F_OPCODE_FMADD_S, RV32F_OPCODE_FMSUB_S,
        RV32F_OPCODE_FNMSUB_S, RV32F_OPCODE_FNMADD_S: return 'b1;
        endcase

        case (rv32v_opcode_t'(inst_fields.opcode))
        RV32V_OPCODE_OP: begin
            case (rv32v_funct3_t'(inst_fields.funct3))
            RV32V_FUNCT3_OP_FVV, RV32V_FUNCT3_OP_FVF: begin
                case (rv32v_funct6_t'(inst_fields.funct6))
                RV32V_FUNCT6_VFMACC, RV32V_FUNCT6_VFNMACC,
                RV32V_FUNCT6_VFMSAC, RV32V_FUNCT6_VFNMSAC: return 'b1;
                default: return 'b0;
                endcase
            end
            RV32V_FUNCT3_OP_IVI: return 'b0;
            endcase
        end
        endcase

        return 'b0;
    endfunction

    function automatic logic basilisk_decode_depend_registers(
            input rv32_fields_t inst_fields,
            input logic rd_status, rs1_status, rs2_status, rs3_status
            // input basilisk_decode_reg_status_t reg_status [32]
    );
        if (basilisk_decode_depend_rd(inst_fields) && rd_status == 'b0) begin
            return 'b0;
        end
        if (basilisk_decode_depend_rs1(inst_fields) && rs1_status == 'b0) begin
            return 'b0;
        end
        if (basilisk_decode_depend_rs2(inst_fields) && rs2_status == 'b0) begin
            return 'b0;
        end
        if (basilisk_decode_depend_rs3(inst_fields) && rs3_status == 'b0) begin
            return 'b0;
        end
        return 'b1;
    endfunction

endpackage

`endif
