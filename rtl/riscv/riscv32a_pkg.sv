//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv

package riscv32a_pkg;

    import riscv_pkg::*;
    import riscv32_pkg::*;

    typedef enum riscv32_funct5_t {
        RISCV32A_FUNCT5_LR_W = 5'b00010,
        RISCV32A_FUNCT5_SC_W = 5'b00011,
        RISCV32A_FUNCT5_AMOSWAP_W = 5'b00001,
        RISCV32A_FUNCT5_AMOADD_W = 5'b00000,
        RISCV32A_FUNCT5_AMOXOR_W = 5'b00100,
        RISCV32A_FUNCT5_AMOAND_W = 5'b01100,
        RISCV32A_FUNCT5_AMOOR_W = 5'b01000,
        RISCV32A_FUNCT5_AMOMIN_W = 5'b10000,
        RISCV32A_FUNCT5_AMOMAX_W = 5'b10100,
        RISCV32A_FUNCT5_AMOMINU_W = 5'b11000,
        RISCV32A_FUNCT5_AMOMAXU_W = 5'b11100,
        RISCV32A_FUNCT5_UNDEF = 5'bXXXXX
    } riscv32a_funct5_t;

endpackage
