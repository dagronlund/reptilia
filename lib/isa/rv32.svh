`ifndef __RV32__
`define __RV32__

`ifdef _SIMULATION_
`include "rv.svh"
`endif

package rv32;

    import rv::*;
    
    typedef logic [31:0] rv32_inst_t;
    typedef logic [31:0] rv32_imm_t;
    typedef logic [6:0] rv32_opcode_t;
    typedef logic [4:0] rv32_reg_addr_t;
    typedef logic [31:0] rv32_reg_value_t;
    typedef logic signed [31:0] rv32_reg_signed_t;
    typedef logic [2:0] rv32_funct3_t;
    typedef logic [6:0] rv32_funct7_t;
    typedef logic [11:0] rv32_funct12_t;

    typedef struct packed {
        rv32_inst_t inst;
        rv32_opcode_t opcode;
        rv32_reg_addr_t rd, rs1, rs2;
        rv32_funct3_t funct3;
        rv32_funct7_t funct7;
        rv32_funct12_t funct12;
        rv32_imm_t imm;
        logic decode_error;
    } rv32_fields_t;

endpackage

`endif
