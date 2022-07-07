//!import riscv/riscv_pkg.sv

package riscv32_pkg;

    import riscv_pkg::*;
    
    typedef logic [31:0] riscv32_inst_t;
    typedef logic [31:0] riscv32_imm_t;
    typedef logic [6:0] riscv32_opcode_t;
    typedef logic [4:0] riscv32_reg_addr_t;
    typedef logic [31:0] riscv32_reg_value_t;
    typedef logic signed [31:0] riscv32_reg_signed_t;
    typedef logic [2:0] riscv32_funct3_t;
    typedef logic [4:0] riscv32_funct5_t;
    typedef logic [5:0] riscv32_funct6_t;
    typedef logic [6:0] riscv32_funct7_t;
    typedef logic [11:0] riscv32_funct12_t;

    typedef struct packed {
        riscv32_inst_t inst;
        riscv32_opcode_t opcode;
        riscv32_reg_addr_t rd, rs1, rs2, rs3;
        riscv32_funct3_t funct3;
        riscv32_funct5_t funct5;
        riscv32_funct6_t funct6;
        riscv32_funct7_t funct7;
        riscv32_funct12_t funct12;
        riscv32_imm_t imm;
        logic decode_error;
    } riscv32_fields_t;

endpackage
