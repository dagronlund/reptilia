//!import riscv/riscv_pkg
//!import riscv/riscv32_pkg

package riscv32m_pkg;

    import riscv_pkg::*;
    import riscv32_pkg::*;

    typedef enum riscv32_funct3_t {
        RISCV32M_FUNCT3_MUL = 'h0,
        RISCV32M_FUNCT3_MULH = 'h1,
        RISCV32M_FUNCT3_MULHSU = 'h2,
        RISCV32M_FUNCT3_MULHU = 'h3,
        RISCV32M_FUNCT3_DIV = 'h4,
        RISCV32M_FUNCT3_DIVU = 'h5,
        RISCV32M_FUNCT3_REM = 'h6,
        RISCV32M_FUNCT3_REMU = 'h7
    } riscv32m_funct3_t;

    typedef enum riscv32_funct7_t {
        RISCV32M_FUNCT7_MUL_DIV = 'h01,
        RISCV32M_FUNCT7_UNDEF
    } riscv32m_funct7_t;

endpackage
