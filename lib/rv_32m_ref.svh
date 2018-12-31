`include "rv_inst.svh"

`ifndef __RV_32M_REF__
`define __RV_32M_REF__

/*
Implements reference behavior for RISC-V 32M instructions
*/
package rv_32m_ref;

    import rv_inst::*;

    parameter bit [31:0] RV_32M_ZERO = 32'b0;
    parameter bit [31:0] RV_32M_NEGATIVE_ONE = {32{1'b1}};
    parameter bit [31:0] RV_32M_MIN = {1'b1, 31'b0};

    // Multiply, lower order bits
    function automatic bit [31:0] rv_32m_MUL(bit signed [31:0] rs1, bit signed [31:0] rs2);
        bit [63:0] result = rs1 * rs2;
        return result[31:0];
    endfunction

    // Multiply signed*signed, higher order bits
    function automatic bit [31:0] rv_32m_MULH(bit signed [31:0] rs1, bit signed [31:0] rs2);
        bit [63:0] result = rs1 * rs2;
        return result[63:32];
    endfunction

    // Multiply unsigned*unsigned, higher order bits
    function automatic bit [31:0] rv_32m_MULHU(bit signed [31:0] rs1, bit signed [31:0] rs2);
        bit [63:0] result = $unsigned(rs1) * $unsigned(rs2);
        return result[63:32];
    endfunction

    // Multiply signed*unsigned, higher order bits
    function automatic bit [31:0] rv_32m_MULHU(bit signed [31:0] rs1, bit signed [31:0] rs2);
        bit [63:0] result = rs1 * $unsigned(rs2);
        return result[63:32];
    endfunction

    // Signed Division
    function automatic bit [31:0] rv_32m_DIV(bit signed [31:0] rs1, bit signed [31:0] rs2);
        if (rs2 == 0) begin
            return RV_32M_NEGATIVE_ONE;
        end else if (rs1 == RV_32M_MIN && rs2 == RV_32M_NEGATIVE_ONE) begin
            return RV_32M_MIN;
        end else begin
            return rs1 / rs2;
        end
    endfunction

    // Signed Remainder
    function automatic bit [31:0] rv_32m_REM(bit signed [31:0] rs1, bit signed [31:0] rs2);
        if (rs2 == 32'b0) begin
            return rs1;
        end else if (rs1 == RV_32M_MIN && rs2 == RV_32M_NEGATIVE_ONE) begin
            return 32'b0;
        end else begin
            return rs1 % rs2;
        end
    endfunction

    // Unsigned Division
    function automatic bit [31:0] rv_32m_DIVU(bit signed [31:0] rs1, bit signed [31:0] rs2);
        if (rs2 == 0) begin
            return RV_32M_NEGATIVE_ONE;
        end else begin
            return $unsigned(rs1) / $unsigned(rs2);
        end
    endfunction

    // Unsigned Remainder
    function automatic bit [31:0] rv_32m_DIVU(bit signed [31:0] rs1, bit signed [31:0] rs2);
        if (rs2 == 32'b0) begin
            return rs1;
        end else begin
            return $unsigned(rs1) % $unsigned(rs2);
        end
    endfunction

endpackage

`endif
