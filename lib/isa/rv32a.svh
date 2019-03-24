`ifndef __RV32A__
`define __RV32A__

`ifdef __SIMULATION__
`include "rv32.svh"
`endif

package rv32a;

    import rv::*;
    import rv32::*;

    typedef enum rv32_funct5_t {
        RV32A_FUNCT5_LR_W = 5'b00010,
        RV32A_FUNCT5_SC_W = 5'b00011,
        RV32A_FUNCT5_AMOSWAP_W = 5'b00001,
        RV32A_FUNCT5_AMOADD_W = 5'b00000,
        RV32A_FUNCT5_AMOXOR_W = 5'b00100,
        RV32A_FUNCT5_AMOAND_W = 5'b01100,
        RV32A_FUNCT5_AMOOR_W = 5'b01000,
        RV32A_FUNCT5_AMOMIN_W = 5'b10000,
        RV32A_FUNCT5_AMOMAX_W = 5'b10100,
        RV32A_FUNCT5_AMOMINU_W = 5'b11000,
        RV32A_FUNCT5_AMOMAXU_W = 5'b11100,
        RV32A_FUNCT5_UNDEF = 5'bXXXXX
    } rv32a_funct5_t;

endpackage

`endif
