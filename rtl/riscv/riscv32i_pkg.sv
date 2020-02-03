//!import riscv/riscv_pkg
//!import riscv/riscv32_pkg

package riscv32i_pkg;

    import riscv_pkg::*;
    import riscv32_pkg::*;

    parameter riscv32_funct12_t RISCV32I_CSR_CYCLE = 12'hC00;
    parameter riscv32_funct12_t RISCV32I_CSR_TIME = 12'hC01;
    parameter riscv32_funct12_t RISCV32I_CSR_INSTRET = 12'hC02;
    parameter riscv32_funct12_t RISCV32I_CSR_CYCLEH = 12'hC80;
    parameter riscv32_funct12_t RISCV32I_CSR_TIMEH = 12'hC81;
    parameter riscv32_funct12_t RISCV32I_CSR_INSTRETH = 12'hC82;

    parameter riscv32_funct12_t RISCV32I_CSR_ECALL = 12'h000;
    parameter riscv32_funct12_t RISCV32I_CSR_EBREAK = 12'h001;

    typedef enum riscv32_opcode_t {
        RISCV32I_OPCODE_OP = 'h33, // Register (R-Type)
        RISCV32I_OPCODE_IMM = 'h13, // Immediate (I-Type)
        RISCV32I_OPCODE_LOAD = 'h03, // Load (I-Type)
        RISCV32I_OPCODE_STORE = 'h23, // Store (S-Type)
        RISCV32I_OPCODE_LUI = 'h37, // Upper Immediate (U-Type)
        RISCV32I_OPCODE_AUIPC = 'h17, // PC Immediate (U-Type)
        RISCV32I_OPCODE_JAL = 'h6F, // Jump/Link (J-Type)
        RISCV32I_OPCODE_JALR = 'h67, // Jump/Link/Register (I-Type)
        RISCV32I_OPCODE_BRANCH = 'h63, // Branch (B-Type)
        RISCV32I_OPCODE_SYSTEM = 'h73, // System (I-Type)
        RISCV32I_OPCODE_FENCE = 'h0F, // Fence (I-Type)
        RISCV32I_OPCODE_UNDEF
    } riscv32i_opcode_t;

    typedef enum riscv32_funct3_t {
        RISCV32I_FUNCT3_IR_ADD_SUB = 'h0,
        RISCV32I_FUNCT3_IR_SLL = 'h1,
        RISCV32I_FUNCT3_IR_SLT = 'h2,
        RISCV32I_FUNCT3_IR_SLTU = 'h3,
        RISCV32I_FUNCT3_IR_XOR = 'h4,
        RISCV32I_FUNCT3_IR_SRL_SRA = 'h5,
        RISCV32I_FUNCT3_IR_OR = 'h6,
        RISCV32I_FUNCT3_IR_AND = 'h7
    } riscv32i_funct3_ir_t;

    typedef enum riscv32_funct3_t {
        RISCV32I_FUNCT3_LS_B = 'h0,
        RISCV32I_FUNCT3_LS_H = 'h1,
        RISCV32I_FUNCT3_LS_W = 'h2,
        RISCV32I_FUNCT3_LS_BU = 'h4,
        RISCV32I_FUNCT3_LS_HU = 'h5,
        RISCV32I_FUNCT3_LS_UNDEF = 'h6
    } riscv32i_funct3_ls_t;

    typedef enum riscv32_funct3_t {
        RISCV32I_FUNCT3_B_BEQ = 'h0,
        RISCV32I_FUNCT3_B_BNE = 'h1,
        RISCV32I_FUNCT3_B_BLT = 'h4,
        RISCV32I_FUNCT3_B_BGE = 'h5,
        RISCV32I_FUNCT3_B_BLTU = 'h6,
        RISCV32I_FUNCT3_B_BGEU = 'h7,
        RISCV32I_FUNCT3_B_UNDEF = 'h2
    } riscv32i_funct3_b_t;

    typedef enum riscv32_funct3_t {
        RISCV32I_FUNCT3_SYS_ENV = 'h0,
        RISCV32I_FUNCT3_SYS_CSRRW = 'h1,
        RISCV32I_FUNCT3_SYS_CSRRS = 'h2,
        RISCV32I_FUNCT3_SYS_CSRRC = 'h3,
        RISCV32I_FUNCT3_SYS_CSRRWI = 'h5,
        RISCV32I_FUNCT3_SYS_CSRRSI = 'h6,
        RISCV32I_FUNCT3_SYS_CSRRCI = 'h7,
        RISCV32I_FUNCT3_SYS_UNDEF = 'h4
    } riscv32i_funct3_sys_t;

    typedef union packed {
        riscv32i_funct3_ir_t ir;
        riscv32i_funct3_ls_t ls;
        riscv32i_funct3_b_t b;
        riscv32i_funct3_sys_t sys;
    } riscv32i_funct3_t;

    typedef enum riscv32_funct7_t {
        RISCV32I_FUNCT7_INT = 'h00,
        RISCV32I_FUNCT7_ALT_INT = 'h20,
        RISCV32I_FUNCT7_UNDEF
    } riscv32i_funct7_t;

    typedef enum riscv32_funct12_t {
        RISCV32I_FUNCT12_ECALL = 'h0,
        RISCV32I_FUNCT12_EBREAK = 'h1,
        RISCV32I_FUNCT12_UNDEF
    } riscv32i_funct12_t;

    function automatic riscv32_fields_t riscv32_get_fields(
        input riscv32_inst_t inst
    );
        riscv32_fields_t fields = '{
            inst: inst[31:0],
            opcode: inst[6:0],
            rd: inst[11:7],
            rs1: inst[19:15],
            rs2: inst[24:20],
            rs3: inst[31:27],
            funct3: inst[14:12],
            funct7: inst[31:25],
            funct5: inst[31:27],
            funct6: inst[31:26],
            funct12: inst[31:20],
            decode_error: 1'b0,
            default:'0
        };

        case (riscv32i_opcode_t'(fields.opcode))
        RISCV32I_OPCODE_STORE: 
            fields.imm = {{20{inst[31]}}, inst[31:25], inst[11:7]}; // S-Type
        RISCV32I_OPCODE_LUI, RISCV32I_OPCODE_AUIPC: 
            fields.imm = {inst[31:12], 12'b0}; // U-Type
        RISCV32I_OPCODE_JAL: 
            fields.imm = {{12{inst[19]}}, inst[19:12], inst[20], inst[30:21], 1'b0}; // J-Type
        RISCV32I_OPCODE_BRANCH: 
            fields.imm = {{20{inst[7]}}, inst[7], inst[30:25], inst[11:8], 1'b0}; // B-Type
        default: 
            fields.imm = {{20{inst[31]}}, inst[31:20]}; // IR-Type
        endcase

        return fields;
    endfunction

endpackage
