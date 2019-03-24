`ifndef __RV32M__
`define __RV32M__

`ifdef __SIMULATION__
`include "rv32.svh"
`endif

package rv32m;

    import rv::*;
    import rv32::*;

    typedef enum rv32_funct3_t {
        RV32M_FUNCT3_MUL = 'h0,
        RV32M_FUNCT3_MULH = 'h1,
        RV32M_FUNCT3_MULHSU = 'h2,
        RV32M_FUNCT3_MULHU = 'h3,
        RV32M_FUNCT3_DIV = 'h4,
        RV32M_FUNCT3_DIVU = 'h5,
        RV32M_FUNCT3_REM = 'h6,
        RV32M_FUNCT3_REMU = 'h7
    } rv32m_funct3_t;

    typedef enum rv32_funct7_t {
        RV32M_FUNCT7_MUL_DIV = 'h01,
        RV32M_FUNCT7_UNDEF = 'hXX
    } rv32m_funct7_t;

endpackage

`endif
