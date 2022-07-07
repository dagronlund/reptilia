//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv

package riscv32v_pkg;

    import riscv_pkg::*;
    import riscv32_pkg::*;

    parameter riscv32_funct12_t RISCV32V_CSR_VL = 12'hC20;

    typedef enum riscv32_opcode_t {
        RISCV32V_OPCODE_OP = 'b1010111
    } riscv32v_opcode_t;

    typedef enum riscv32_funct3_t {
        RISCV32V_FUNCT3_OP_IVV = 'b000,

        // DANGER: Swapping these to compensate for assembler bug
        RISCV32V_FUNCT3_OP_FVV = 'b010, // Floating Point Vector-Vector
        RISCV32V_FUNCT3_OP_MVV = 'b001,
        
        RISCV32V_FUNCT3_OP_IVI = 'b011, // Integer Vector-Immediate (Slideup/Slidedown)
        RISCV32V_FUNCT3_OP_IVX = 'b100, 
        RISCV32V_FUNCT3_OP_FVF = 'b101, // Floating Point Vector-Scalar
        RISCV32V_FUNCT3_OP_MVX = 'b110,
        RISCV32V_FUNCT3_OP_SETVL = 'b111
    } riscv32v_funct3_t;

    typedef enum riscv32_funct6_t {
        RISCV32V_FUNCT6_VFADD = 'b000000, // OP_FVV or OP_FVF
        RISCV32V_FUNCT6_VFSUB = 'b000010, // OP_FVV or OP_FVF
        RISCV32V_FUNCT6_VSLIDEUP = 'b001110, // OP_IVI only
        RISCV32V_FUNCT6_VSLIDEDOWN = 'b001111, // OP_IVI only
        RISCV32V_FUNCT6_VFDIV = 'b100000, // OP_FVV or OP_FVF
        RISCV32V_FUNCT6_VFSQRT = 'b100011, // OP_FVV or OP_FVF
        RISCV32V_FUNCT6_VFRDIV = 'b100001, // OP_FVF only
        RISCV32V_FUNCT6_VFMUL = 'b100100, // OP_FVV or OP_FVF
        RISCV32V_FUNCT6_VFMACC = 'b101100, // OP_FVV or OP_FVF
        RISCV32V_FUNCT6_VFNMACC = 'b101101, // OP_FVV or OP_FVF
        RISCV32V_FUNCT6_VFMSAC = 'b101110, // OP_FVV or OP_FVF
        RISCV32V_FUNCT6_VFNMSAC = 'b101111 // OP_FVV or OP_FVF
    } riscv32v_funct6_t;

    // RISCV32V_FUNCT6_VFMIN = 'b000100, // OP_FVV or OP_FVF
    // RISCV32V_FUNCT6_VFMAX = 'b000110, // OP_FVV or OP_FVF
    // RISCV32V_FUNCT6_VFSGNJ = 'b001000, // OP_FVV or OP_FVF
    // RISCV32V_FUNCT6_VFSGNN = 'b001001, // OP_FVV or OP_FVF
    // RISCV32V_FUNCT6_VFSGNX = 'b001010, // OP_FVV or OP_FVF

    // Integer Integer FP
    // funct3 funct3 funct3
    // OPIVV V   OPMVV V   OPFVV V
    // OPIVX  X  OPMVX  X  OPFVF  F
    // OPIVI   I

    // 000000 V F vfadd
    // 000010 V F vfsub

    // 000100 V F vfmin
    // 000110 V F vfmax

    // 001000 V F vfsgnj
    // 001001 V F vfsgnn
    // 001010 V F vfsgnx

    // 001110 X I vslideup
    // 001111 X I vslidedown

    // 100000 V F vfdiv
    // 100001 V F vfrdiv // vector-scalar only
    // 100100 V F vfmul

    // 101100 V F vfmacc
    // 101101 V F vfnmacc
    // 101110 V F vfmsac
    // 101111 V F vfnmsac

    // funct6 | vm | vs2 | vs1 | 0 0 0 | vd |1010111| OP-V (OPIVV)
    // funct6 | vm | vs2 | vs1 | 0 0 1 | vd |1010111| OP-V (OPFVV)
    // funct6 | vm | vs2 | vs1 | 0 1 0 | vd/rd |1010111| OP-V (OPMVV)
    // funct6 | vm | vs2 | imm | 0 1 1 | vd |1010111| OP-V (OPIVI)
    // funct6 | vm | vs2 | rs1 | 1 0 0 | vd |1010111| OP-V (OPIVX)
    // funct6 | vm | vs2 | rs1 | 1 0 1 | vd |1010111| OP-V (OPFVF)
    // funct6 | vm | vs2 | rs1 | 1 1 0 | vd/rd |1010111| OP-V (OPMVX)

endpackage
