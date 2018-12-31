`include "rv_inst.svh"

`ifndef __RV_32I_REF__
`define __RV_32I_REF__

/*
Implements reference behavior for RISC-V 32I instructions
*/
package rv_32i_ref;

    import rv_inst::*;

    /*
    Type-I Instructions
    */

    // Add Immediate
    function automatic bit [31:0] rv_32i_ADDI(bit signed [31:0] imm, bit signed [31:0] rs1);
        return imm + rs1;
    endfunction

    // Set Less Than Immediate
    function automatic bit [31:0] rv_32i_SLTI(bit signed [31:0] imm, bit signed [31:0] rs1);
        return (rs1 < imm) ? 32'b1 : 32'b0;
    endfunction

    // Set Less Than Unsigned Immediate
    function automatic bit [31:0] rv_32i_SLTIU(bit signed [31:0] imm, bit signed [31:0] rs1);
        return ($unsigned(rs1) < $unsigned(imm)) ? 32'b1 : 32'b0;
    endfunction

    // And Immediate
    function automatic bit [31:0] rv_32i_ANDI(bit signed [31:0] imm, bit signed [31:0] rs1);
        return imm & rs1;
    endfunction

    // Or Immediate
    function automatic bit [31:0] rv_32i_ORI(bit signed [31:0] imm, bit signed [31:0] rs1);
        return imm | rs1;
    endfunction

    // Xor Immediate
    function automatic bit [31:0] rv_32i_XORI(bit signed [31:0] imm, bit signed [31:0] rs1);
        return imm ^ rs1;
    endfunction

    // Shift Left Logical Immediate
    function automatic bit [31:0] rv_32i_SLLI(bit [4:0] shift_amount, bit signed [31:0] rs1);
        return $unsigned(rs1) << shift_amount;
    endfunction

    // Shift Right Logical Immediate
    function automatic bit [31:0] rv_32i_SRLI(bit [4:0] shift_amount, bit signed [31:0] rs1);
        return $unsigned(rs1) >> shift_amount;
    endfunction

    // Shift Right Arithmetic Immediate
    function automatic bit [31:0] rv_32i_SRAI(bit [4:0] shift_amount, bit signed [31:0] rs1);
        return rs1 >>> shift_amount;
    endfunction

    /*
    Type-U Instructions
    */

    imm[31:12] rd 0010111 AUIPC

    // Load Upper Immediate
    function automatic bit [31:0] rv_32i_LUI(bit signed [31:0] imm);
        return imm;
    endfunction

    // Add Upper Immediate to PC
    function automatic bit [31:0] rv_32i_AUIPC(bit signed [31:0] imm, bit [31:0] pc);
        return imm + pc;
    endfunction

    /*
    Type-R Instructions
    */

    // Add
    function automatic bit [31:0] rv_32i_ADD(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return rs1 + rs2;
    endfunction

    // Subtract
    function automatic bit [31:0] rv_32i_SUB(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return rs1 - rs2;
    endfunction

    // Set Less Than
    function automatic bit [31:0] rv_32i_SLT(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return (rs1 < rs2) ? 32'b1 : 32'b0;
    endfunction

    // Set Less Than Unsigned
    function automatic bit [31:0] rv_32i_SLTU(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return ($unsigned(rs1) < $unsigned(rs2)) ? 32'b1 : 32'b0;
    endfunction

    // And
    function automatic bit [31:0] rv_32i_AND(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return rs1 & rs2;
    endfunction

    // Or
    function automatic bit [31:0] rv_32i_OR(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return rs1 | rs2;
    endfunction

    // Xor
    function automatic bit [31:0] rv_32i_XOR(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return rs1 ^ rs2;
    endfunction

    // Shift Left Logical
    function automatic bit [31:0] rv_32i_SLL(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return $unsigned(rs1) << rs2[4:0];
    endfunction

    // Shift Right Logical
    function automatic bit [31:0] rv_32i_SRL(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return $unsigned(rs1) >> rs2[4:0];
    endfunction

    // Shift Right Arithmetic
    function automatic bit [31:0] rv_32i_SRA(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return rs1 >>> rs2[4:0];
    endfunction

    /*
    Type-J Instructions
    */

    // Jump and Link
    //      rd=pc+4, pc=pc+imm; 
    function automatic bit [31:0] rv_32i_JAL(bit signed [31:0] imm, bit signed [31:0] pc);
        return imm + pc;
    endfunction

    /*
    Type-I Instructions
    */

    // Jump and Link Register
    //      rd=pc+4, pc=rs1+imm (also zeroing lower order bit)
    function automatic bit [31:0] rv_32i_JAL(bit signed [31:0] imm, bit signed [31:0] rs1);
        bit [31:0] result = imm + rs1;
        return {result[31:1], 1'b0};
    endfunction

    /*
    Type-B Instructions, returns if branch was taken
    */

    // Branch Equal
    function automatic bit [31:0] rv_32i_BEQ(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return (rs1 == rs2);
    endfunction

    // Branch Not Equal
    function automatic bit [31:0] rv_32i_BNE(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return (rs1 != rs2);
    endfunction

    // Branch Less Than
    function automatic bit [31:0] rv_32i_BLT(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return rs1 < rs2;
    endfunction

    // Branch Less Than Unsigned
    function automatic bit [31:0] rv_32i_BLTU(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return $unsigned(rs1) < $unsigned(rs2);
    endfunction

    // Branch Greater Than Equal
    function automatic bit [31:0] rv_32i_BGE(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return rs1 >= rs2;
    endfunction

    // Branch Greater Than Equal Unsigned
    function automatic bit [31:0] rv_32i_BGEU(bit signed [31:0] rs1, bit signed [31:0] rs2);
        return $unsigned(rs1) >= $unsigned(rs2);
    endfunction


    

endpackage

`endif