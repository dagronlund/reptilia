`ifndef __GECKO__
`define __GECKO__

`ifdef __SIMULATION__
`include "../isa/rv32.svh"
`include "../isa/rv32i.svh"
`endif

package gecko;

    import rv32::*;
    import rv32i::*;

    typedef rv32_reg_value_t gecko_pc_t;

    typedef logic [1:0] gecko_byte_offset_t;
    typedef logic [3:0] gecko_store_mask_t;

    // Configurable Types
    typedef logic gecko_jump_flag_t;
    typedef logic [2:0] gecko_reg_status_t;
    typedef logic [2:0] gecko_speculative_count_t;
    typedef logic [4:0] gecko_retired_count_t;
    typedef logic [7:0] gecko_prediction_history_t;

    parameter gecko_reg_status_t GECKO_REG_STATUS_VALID = 'b0;
    parameter gecko_reg_status_t GECKO_REG_STATUS_FULL = (-1);

    parameter gecko_speculative_count_t GECKO_SPECULATIVE_FULL = (-1);

    typedef enum logic {
        GECKO_NORMAL = 'h0,
        GECKO_ALTERNATE = 'h1
    } gecko_alternate_t;

    typedef struct packed {
        rv32_reg_value_t add_sub_result;
        rv32_reg_value_t or_result;
        rv32_reg_value_t and_result;
        rv32_reg_value_t xor_result;
        rv32_reg_value_t lshift_result;
        rv32_reg_value_t rshift_result;
        logic eq;
        logic lt;
        logic ltu;
    } gecko_math_result_t;

    typedef struct packed {
        rv32_reg_value_t sum;
        logic carry;
    } gecko_add_sub_result_t;

    typedef struct packed {
        rv32_reg_value_t value;
        gecko_store_mask_t mask;
    } gecko_store_result_t;

    typedef struct packed {
        logic miss;
        gecko_prediction_history_t history;
    } gecko_prediction_t;

    /*************************************************************************
     * Internal Gecko Stream Datatypes                                       *
     *************************************************************************/

    typedef struct packed {
        rv32_reg_addr_t addr;
        gecko_reg_status_t reg_status;
        gecko_jump_flag_t jump_flag;
        logic speculative;
        rv32_reg_value_t value;
    } gecko_operation_t;

    typedef struct packed {
        rv32_reg_addr_t addr;
        logic valid, speculative;
        gecko_jump_flag_t jump_flag;
        gecko_reg_status_t reg_status;
        rv32_reg_value_t value;
    } gecko_forwarded_t;

    typedef struct packed {
        logic update_pc, branched, jumped;
        gecko_pc_t current_pc, actual_next_pc;
        gecko_prediction_t prediction;
    } gecko_jump_operation_t;

    typedef struct packed {
        gecko_pc_t pc, next_pc;
        gecko_prediction_t prediction;
        gecko_jump_flag_t jump_flag;
    } gecko_instruction_operation_t;

    typedef struct packed {
        rv32_reg_addr_t addr;
        gecko_reg_status_t reg_status;
        gecko_jump_flag_t jump_flag;
        rv32i_funct3_ls_t op;
        gecko_byte_offset_t offset;
    } gecko_mem_operation_t;

    typedef struct packed {
        rv32_reg_addr_t reg_addr;
        gecko_reg_status_t reg_status;
        gecko_jump_flag_t jump_flag;
        rv32_reg_addr_t imm_value;
        rv32_reg_value_t rs1_value;
        rv32i_funct3_sys_t sys_op;
        rv32_funct12_t csr;
    } gecko_system_operation_t;

    typedef enum logic [2:0] {
        GECKO_EXECUTE_TYPE_EXECUTE = 3'b000,
        GECKO_EXECUTE_TYPE_LOAD = 3'b001,
        GECKO_EXECUTE_TYPE_STORE = 3'b010,
        GECKO_EXECUTE_TYPE_BRANCH = 3'b011,
        GECKO_EXECUTE_TYPE_JUMP = 3'b100,
        GECKO_EXECUTE_TYPE_UNDEF // = 3'bXXX
    } gecko_execute_type_t;

    typedef struct packed {
        rv32_reg_addr_t reg_addr;
        gecko_reg_status_t reg_status;
        gecko_jump_flag_t jump_flag;
        logic speculative;

        gecko_execute_type_t op_type;
        rv32i_funct3_t op;
        gecko_alternate_t alu_alternate;

        logic reuse_rs1, reuse_rs2, reuse_mem, reuse_jump;
        rv32_reg_value_t rs1_value, rs2_value, mem_value, jump_value;
        rv32_reg_value_t immediate_value;
        rv32_reg_value_t current_pc, next_pc;
        gecko_prediction_t prediction;
    } gecko_execute_operation_t;

    /*************************************************************************
     * Internal Gecko Helper Functions                                       *
     *************************************************************************/

    function automatic gecko_forwarded_t gecko_construct_forward(
        input logic valid,
        input gecko_operation_t op
    );
        return '{
            addr: op.addr,
            reg_status: op.reg_status,
            jump_flag: op.jump_flag,
            valid: valid,
            speculative: op.speculative,
            value: op.value
        };
    endfunction

    // Adds or subtracts with a carry bit
    function automatic gecko_add_sub_result_t gecko_add_sub(
        input rv32_reg_value_t a,
        input rv32_reg_value_t b,
        input logic sub
    );
        gecko_add_sub_result_t result;
        rv32_reg_value_t b_inv;
        b_inv = sub ? (~b) : (b);
        {result.carry, result.sum} = a + b_inv + sub;
        return result;
    endfunction

    // Performs all ALU operations
    function automatic gecko_math_result_t gecko_get_full_math_result(
        input rv32_reg_value_t a, b,
        input logic alt
    );
        logic sub_overflow;
        rv32_reg_signed_t a_signed = a;
        gecko_math_result_t math_result;
        gecko_add_sub_result_t add_sub_result = gecko_add_sub(a, b, alt);

        sub_overflow = (a[31] != b[31]) && (a[31] != add_sub_result.sum[31]);

        math_result.or_result = a | b;
        math_result.and_result = a & b;
        math_result.xor_result = a ^ b;

        math_result.eq = !(|math_result.xor_result);
        math_result.lt = add_sub_result.sum[31] ^ sub_overflow;
        math_result.ltu = !add_sub_result.carry && !math_result.eq;

        math_result.add_sub_result = add_sub_result.sum;

        // TODO: Test if shift helpers are better
        math_result.lshift_result = a << b[4:0];
        if (alt) begin
            math_result.rshift_result = a_signed >>> b[4:0];
        end else begin
            math_result.rshift_result = a >> b[4:0];
        end

        return math_result;
    endfunction

    function automatic logic gecko_evaluate_branch(
            input gecko_math_result_t result,
            input rv32i_funct3_t op
    );
        case (op.b)
        RV32I_FUNCT3_B_BEQ: return result.eq;
        RV32I_FUNCT3_B_BNE: return !result.eq;
        RV32I_FUNCT3_B_BLT: return result.lt;
        RV32I_FUNCT3_B_BGE: return !result.lt;
        RV32I_FUNCT3_B_BLTU: return result.ltu;
        RV32I_FUNCT3_B_BGEU: return !result.ltu;
        default: return 'b0;
        endcase
    endfunction

    function automatic gecko_store_result_t gecko_get_store_result(
        input rv32_reg_value_t value,
        input gecko_byte_offset_t byte_offset,
        input rv32i_funct3_ls_t mem_op
    );
        unique case (mem_op)
        RV32I_FUNCT3_LS_B, RV32I_FUNCT3_LS_BU: begin
            return '{
                value: {value[7:0], value[7:0], value[7:0], value[7:0]}, 
                mask: 4'b1 << byte_offset
            };
        end
        RV32I_FUNCT3_LS_H, RV32I_FUNCT3_LS_HU: begin
            return '{
                value: {value[15:0], value[15:0]},
                mask: 4'b11 << {byte_offset[1], 1'b0}
            };
        end
        default: begin // RV32I_FUNCT3_LS_W
            return '{
                value: value,
                mask: 4'b1111
            };
        end
        endcase
    endfunction

    function automatic rv32_reg_value_t gecko_get_load_result(
        input rv32_reg_value_t value,
        input gecko_byte_offset_t byte_offset,
        input rv32i_funct3_ls_t mem_op
    );
        rv32_reg_value_t bshifted_value = value >> {byte_offset, 3'b0};
        rv32_reg_value_t hshifted_value = value >> {byte_offset[1], 4'b0};;

        unique case (mem_op)
        RV32I_FUNCT3_LS_B: return {{24{bshifted_value[7]}}, bshifted_value[7:0]};
        RV32I_FUNCT3_LS_H: return {{16{hshifted_value[15]}}, hshifted_value[15:0]};
        RV32I_FUNCT3_LS_BU: return {24'b0, bshifted_value[7:0]};
        RV32I_FUNCT3_LS_HU: return {16'b0, hshifted_value[15:0]};
        default: return value; // RV32I_FUNCT3_LS_W
        endcase
    endfunction

    function automatic gecko_operation_t gecko_get_load_operation(
        input gecko_mem_operation_t mem_op,
        input rv32_reg_value_t mem_data
    );
        return '{
            value: gecko_get_load_result(mem_data, mem_op.offset, mem_op.op),
            addr: mem_op.addr,
            reg_status: mem_op.reg_status,
            jump_flag: mem_op.jump_flag,
            speculative: 'b0
        };
    endfunction

    /*************************************************************************
     * Gecko Shift Helper Functions                                          *
     *************************************************************************/    

    typedef logic [4:0] gecko_shift_amount_t;

    typedef enum logic [2:0] {
        GECKO_SHIFT_STRIDE_1 = 'h0,
        GECKO_SHIFT_STRIDE_2 = 'h1,
        GECKO_SHIFT_STRIDE_4 = 'h2,
        GECKO_SHIFT_STRIDE_8 = 'h3,
        GECKO_SHIFT_STRIDE_16 = 'h4,
        GECKO_SHIFT_STRIDE_UNDEF
    } gecko_shift_stride_t;

    typedef enum logic [1:0] {
        GECKO_SHIFT_LL = 'h0, // Left Logical
        GECKO_SHIFT_RL = 'h1, // Right Logical
        GECKO_SHIFT_RA = 'h2, // Right Arithmetic
        GECKO_SHIFT_UNDEF
    } gecko_shift_type_t;

    typedef struct packed {
        gecko_shift_type_t shift_type;
        gecko_shift_amount_t shift;
        gecko_shift_stride_t stride;
    } gecko_shift_command_t;

    function automatic rv32_reg_value_t gecko_reverse_bits(
        input rv32_reg_value_t value
    );
        int i;
        rv32_reg_value_t reversed;
        for (i = 0; i < 32; i++) begin
            reversed[i] = value[31 - i];
        end
        return reversed;
    endfunction

    function automatic gecko_shift_amount_t gecko_get_actual_shift(
        input gecko_shift_command_t cmd
    );
        unique case (cmd.stride)
        GECKO_SHIFT_STRIDE_1: return cmd.shift;
        GECKO_SHIFT_STRIDE_2: return {cmd.shift[3:0], 1'b0};
        GECKO_SHIFT_STRIDE_4: return {cmd.shift[2:0], 2'b0};
        GECKO_SHIFT_STRIDE_8: return {cmd.shift[1:0], 3'b0};
        GECKO_SHIFT_STRIDE_16: return {cmd.shift[0], 4'b0};
        default: return cmd.shift;
        endcase
    endfunction

    function automatic rv32_reg_value_t gecko_full_shift(
        input rv32_reg_value_t value,
        input gecko_shift_command_t cmd
    );
        int i;
        gecko_shift_amount_t actual_shift;
        rv32_reg_value_t oriented_value, shifted_value;

        // Reverse bits if doing right shift
        case (cmd.shift_type)
        GECKO_SHIFT_RL, GECKO_SHIFT_RA: oriented_value = gecko_reverse_bits(value);
        default: oriented_value = value; // GECKO_SHIFT_LL
        endcase

        // Get corrected shift value
        actual_shift = gecko_get_actual_shift(cmd);

        // Perform left shift
        shifted_value = oriented_value << actual_shift;

        // Perform arithmetic correction from the left
        if (cmd.shift_type == GECKO_SHIFT_RA) begin
            for (i = 0; i < actual_shift; i++) begin
                shifted_value[i] |= oriented_value[0];
            end
        end

        // Unreverse the bits when doing right shifts
        case (cmd.shift_type)
        GECKO_SHIFT_RL, GECKO_SHIFT_RA: return gecko_reverse_bits(value);
        default: return value; // GECKO_SHIFT_LL
        endcase
    endfunction

endpackage

`endif
