//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv

package riscv32f_pkg;

    import riscv_pkg::*;
    import riscv32_pkg::*;

    parameter riscv32_funct12_t RISCV32F_CSR_FFLAGS = 12'h001;
    parameter riscv32_funct12_t RISCV32F_CSR_FRM = 12'h002;
    parameter riscv32_funct12_t RISCV32F_CSR_FCSR = 12'h003; // (FRM + FLAGS)

    typedef enum riscv32_opcode_t {
        RISCV32F_OPCODE_FLW = 7'b0000111,
        RISCV32F_OPCODE_FSW = 7'b0100111,
        RISCV32F_OPCODE_FMADD_S = 7'b1000011,
        RISCV32F_OPCODE_FMSUB_S = 7'b1000111,
        RISCV32F_OPCODE_FNMSUB_S = 7'b1001011,
        RISCV32F_OPCODE_FNMADD_S = 7'b1001111,
        RISCV32F_OPCODE_FP_OP_S = 7'b1010011
    } riscv32f_opcode_t;

    typedef enum riscv32_funct7_t {
        RISCV32F_FUNCT7_FADD_S = 7'b0000000,
        RISCV32F_FUNCT7_FSUB_S = 7'b0000100,
        RISCV32F_FUNCT7_FMUL_S = 7'b0001000,
        RISCV32F_FUNCT7_FDIV_S = 7'b0001100,
        RISCV32F_FUNCT7_FSQRT_S = 7'b0101100,
        RISCV32F_FUNCT7_FSGNJ_S = 7'b0010000, // 3 funct3 options
        RISCV32F_FUNCT7_FMIN_MAX_S = 7'b0010100, // 2 funct3
        RISCV32F_FUNCT7_FCVT_W_S = 7'b1100000, // 2 funct5
        RISCV32F_FUNCT7_FMV_X_W = 7'b1110000, // 2 funct3s
        RISCV32F_FUNCT7_FCMP_S = 7'b1010000, // 3 funct3
        RISCV32F_FUNCT7_FCVT_S_W = 7'b1101000, // 2 funct5s
        RISCV32F_FUNCT7_FMV_W_X = 7'b1111000
    } riscv32f_funct7_t;

    typedef enum riscv32_funct3_t {
        RISCV32F_FUNCT3_FSGNJ_S = 3'b000,
        RISCV32F_FUNCT3_FSGNJN_S = 3'b001,
        RISCV32F_FUNCT3_FSGNJX_S = 3'b010
    } riscv32f_funct3_fsgnj_t;

    typedef enum riscv32_funct3_t {
        RISCV32F_FUNCT3_FMIN_S = 3'b000,
        RISCV32F_FUNCT3_FMAX_S = 3'b001
    } riscv32f_funct3_min_max_t;

    typedef enum riscv32_funct5_t {
        RISCV32F_FUNCT5_FCVT_W = 5'b00000,
        RISCV32F_FUNCT5_FCVT_WU = 5'b00001
    } riscv32f_funct5_fcvt_t;

    typedef enum riscv32_funct3_t {
        RISCV32F_FUNCT3_FMV_X_W = 3'b000,
        RISCV32F_FUNCT3_FCLASS_S = 3'b001
    } riscv32f_funct3_class_t;

    typedef enum riscv32_funct3_t {
        RISCV32F_FUNCT3_ROUND_EVEN = 3'b000,
        RISCV32F_FUNCT3_ROUND_ZERO = 3'b001,
        RISCV32F_FUNCT3_ROUND_DOWN = 3'b010,
        RISCV32F_FUNCT3_ROUND_UP = 3'b011,
        RISCV32F_FUNCT3_ROUND_MAX = 3'b100,
        RISCV32F_FUNCT3_ROUND_DYNAMIC = 3'b111
    } riscv32f_funct3_round_t;

    typedef enum riscv32_funct3_t {
        RISCV32F_FUNCT3_FLE_S = 3'b000,
        RISCV32F_FUNCT3_FLT_S = 3'b001,
        RISCV32F_FUNCT3_FEQ_S = 3'b010
    } riscv32f_funct3_compare_t;

endpackage
