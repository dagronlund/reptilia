//!import riscv/riscv_pkg
//!import riscv/riscv32_pkg
//!import riscv/riscv32i_pkg

package gecko_pkg;

    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;

    typedef riscv32_reg_value_t gecko_pc_t;

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
        riscv32_reg_value_t add_sub_result;
        riscv32_reg_value_t or_result;
        riscv32_reg_value_t and_result;
        riscv32_reg_value_t xor_result;
        riscv32_reg_value_t lshift_result;
        riscv32_reg_value_t rshift_result;
        logic eq;
        logic lt;
        logic ltu;
    } gecko_math_result_t;

    typedef struct packed {
        riscv32_reg_value_t sum;
        logic carry;
    } gecko_add_sub_result_t;

    typedef struct packed {
        riscv32_reg_value_t value;
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
        riscv32_reg_addr_t addr;
        gecko_reg_status_t reg_status;
        gecko_jump_flag_t jump_flag;
        logic speculative;
        riscv32_reg_value_t value;
    } gecko_operation_t;

    typedef struct packed {
        riscv32_reg_addr_t addr;
        logic valid, speculative;
        gecko_jump_flag_t jump_flag;
        gecko_reg_status_t reg_status;
        riscv32_reg_value_t value;
    } gecko_forwarded_t;

    typedef struct packed {
        logic update_pc, branched, jumped;
        gecko_pc_t current_pc, actual_next_pc;
        gecko_prediction_t prediction;
        logic halt;
    } gecko_jump_operation_t;

    typedef struct packed {
        gecko_pc_t pc, next_pc;
        gecko_prediction_t prediction;
        gecko_jump_flag_t jump_flag;
    } gecko_instruction_operation_t;

    typedef struct packed {
        riscv32_reg_addr_t addr;
        gecko_reg_status_t reg_status;
        gecko_jump_flag_t jump_flag;
        riscv32i_funct3_ls_t op;
        gecko_byte_offset_t offset;
    } gecko_mem_operation_t;

    typedef struct packed {
        riscv32_reg_addr_t reg_addr;
        gecko_reg_status_t reg_status;
        gecko_jump_flag_t jump_flag;
        riscv32_reg_addr_t imm_value;
        riscv32_reg_value_t rs1_value;
        riscv32i_funct3_sys_t sys_op;
        riscv32_funct12_t csr;
    } gecko_system_operation_t;

    typedef enum logic [2:0] {
        GECKO_EXECUTE_TYPE_EXECUTE = 3'b000,
        GECKO_EXECUTE_TYPE_LOAD = 3'b001,
        GECKO_EXECUTE_TYPE_STORE = 3'b010,
        GECKO_EXECUTE_TYPE_BRANCH = 3'b011,
        GECKO_EXECUTE_TYPE_JUMP = 3'b100,
        GECKO_EXECUTE_TYPE_MULT = 3'b101,
        GECKO_EXECUTE_TYPE_DIV = 3'b110
    } gecko_execute_type_t;

    typedef logic [1:0] gecko_execute_math_type_t;

    typedef enum gecko_execute_math_type_t {
        GECKO_EXECUTE_MULT_TYPE_MUL = 2'b00,
        GECKO_EXECUTE_MULT_TYPE_MULH = 2'b01,
        GECKO_EXECUTE_MULT_TYPE_MULHU = 2'b10,
        GECKO_EXECUTE_MULT_TYPE_MULHSU = 2'b11
    } gecko_execute_mult_type_t;

    typedef enum gecko_execute_math_type_t {
        GECKO_EXECUTE_DIV_TYPE_DIV = 2'b00,
        GECKO_EXECUTE_DIV_TYPE_DIVU = 2'b01,
        GECKO_EXECUTE_DIV_TYPE_REM = 2'b10,
        GECKO_EXECUTE_DIV_TYPE_REMU = 2'b11
    } gecko_execute_div_type_t;

    typedef struct packed {
        riscv32_reg_addr_t reg_addr;
        gecko_reg_status_t reg_status;
        gecko_jump_flag_t jump_flag;
        logic speculative;
        logic halt;

        gecko_execute_type_t op_type;
        gecko_execute_math_type_t math_type;
        riscv32i_funct3_t op;
        gecko_alternate_t alu_alternate;

        logic reuse_rs1, reuse_rs2, reuse_mem, reuse_jump;
        riscv32_reg_value_t rs1_value, rs2_value, mem_value, jump_value;
        riscv32_reg_value_t immediate_value;
        riscv32_reg_value_t current_pc, next_pc;
        gecko_prediction_t prediction;
    } gecko_execute_operation_t;

    typedef struct packed {
        riscv32_reg_addr_t dest_reg_addr;
        gecko_reg_status_t dest_reg_status;
        gecko_jump_flag_t jump_flag;        

        riscv32_fields_t instruction_fields;
        riscv32_reg_value_t rs1_value;
        
        logic enable_status_op;
        riscv32i_funct3_sys_t sys_op;
        riscv32_reg_addr_t sys_imm;
        riscv32_funct12_t sys_csr;
    } gecko_float_operation_t;

    typedef struct packed {
        logic [7:0] operation;
        logic [7:0] data;
    } gecko_ecall_operation_t;

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
        input riscv32_reg_value_t a,
        input riscv32_reg_value_t b,
        input logic sub
    );
        gecko_add_sub_result_t result;
        riscv32_reg_value_t b_inv;
        b_inv = sub ? (~b) : (b);
        {result.carry, result.sum} = a + b_inv + sub;
        return result;
    endfunction

    // Performs all ALU operations
    function automatic gecko_math_result_t gecko_get_full_math_result(
        input riscv32_reg_value_t a, b,
        input logic alt
    );
        logic sub_overflow;
        riscv32_reg_signed_t a_signed = a;
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
            input riscv32i_funct3_t op
    );
        case (op.b)
        RISCV32I_FUNCT3_B_BEQ: return result.eq;
        RISCV32I_FUNCT3_B_BNE: return !result.eq;
        RISCV32I_FUNCT3_B_BLT: return result.lt;
        RISCV32I_FUNCT3_B_BGE: return !result.lt;
        RISCV32I_FUNCT3_B_BLTU: return result.ltu;
        RISCV32I_FUNCT3_B_BGEU: return !result.ltu;
        default: return 'b0;
        endcase
    endfunction

    function automatic gecko_store_result_t gecko_get_store_result(
        input riscv32_reg_value_t value,
        input gecko_byte_offset_t byte_offset,
        input riscv32i_funct3_ls_t mem_op
    );
        unique case (mem_op)
        RISCV32I_FUNCT3_LS_B, RISCV32I_FUNCT3_LS_BU: begin
            return '{
                value: {value[7:0], value[7:0], value[7:0], value[7:0]}, 
                mask: 4'b1 << byte_offset
            };
        end
        RISCV32I_FUNCT3_LS_H, RISCV32I_FUNCT3_LS_HU: begin
            return '{
                value: {value[15:0], value[15:0]},
                mask: 4'b11 << {byte_offset[1], 1'b0}
            };
        end
        default: begin // RISCV32I_FUNCT3_LS_W
            return '{
                value: value,
                mask: 4'b1111
            };
        end
        endcase
    endfunction

    function automatic riscv32_reg_value_t gecko_get_load_result(
        input riscv32_reg_value_t value,
        input gecko_byte_offset_t byte_offset,
        input riscv32i_funct3_ls_t mem_op
    );
        riscv32_reg_value_t bshifted_value = value >> {byte_offset, 3'b0};
        riscv32_reg_value_t hshifted_value = value >> {byte_offset[1], 4'b0};;

        unique case (mem_op)
        RISCV32I_FUNCT3_LS_B: return {{24{bshifted_value[7]}}, bshifted_value[7:0]};
        RISCV32I_FUNCT3_LS_H: return {{16{hshifted_value[15]}}, hshifted_value[15:0]};
        RISCV32I_FUNCT3_LS_BU: return {24'b0, bshifted_value[7:0]};
        RISCV32I_FUNCT3_LS_HU: return {16'b0, hshifted_value[15:0]};
        default: return value; // RISCV32I_FUNCT3_LS_W
        endcase
    endfunction

    function automatic gecko_operation_t gecko_get_load_operation(
        input gecko_mem_operation_t mem_op,
        input riscv32_reg_value_t mem_data
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
     * Gecko Integer Math Helpers                                            *
     *************************************************************************/

    // typedef struct packed {
    //     riscv32_reg_value_t result;
    //     riscv32_reg_value_t partial;
    // } gecko_multiply_result_t;

    // function automatic riscv32_reg_value_t gecko_multiply_lower(
    //     input riscv32_reg_value_t current_result,
    //     input riscv32_reg_value_t 
    // );

    // endfunction

    // function automatic gecko_multiply_result_t gecko_multiply_upper(

    // );
    
    // endfunction

endpackage
