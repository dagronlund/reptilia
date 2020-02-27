//!import riscv/riscv_pkg
//!import riscv/riscv32_pkg
//!import riscv/riscv32i_pkg

package gecko_pkg;

    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import riscv32m_pkg::*;

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
        GECKO_EXECUTE_TYPE_MUL_DIV = 3'b101
    } gecko_execute_type_t;

    typedef struct packed {
        riscv32_reg_addr_t reg_addr;
        gecko_reg_status_t reg_status;
        gecko_jump_flag_t jump_flag;
        logic speculative;
        logic halt;

        gecko_execute_type_t op_type;
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

    typedef struct packed {
        riscv32m_funct3_t math_op;
        riscv32_reg_value_t operand; // rs1, multiplicand, dividend
        riscv32_reg_value_t operator; // rs2, multiplier, divisor
        riscv32_reg_value_t result;
        logic flag;
        logic done;
    } gecko_math_operation_t;

    function automatic gecko_math_operation_t gecko_math_operation_step(
        input gecko_math_operation_t op,
        logic [5:0] current_iteration
    );
        logic carry = 1'b0;
        int i;

        unique case (op.math_op)
        RISCV32M_FUNCT3_MUL: begin

            // // Does single cycle multiplication change anything?
            // for (i = 0; i < 32; i++) begin
            //     if (op.operator[0]) begin
            //         op.result = op.result + op.operand;
            //     end
            //     op.operand = {op.operand[30:0], 1'b0};
            //     op.operator = {1'b0, op.operator[31:1]};
            // end
            // op.done = 'b1;

            if (current_iteration == 'b0) begin
                // Swap lesser value into operator to save cycles
                if (op.operand < op.operator) begin
                    {op.operand, op.operator} = {op.operator, op.operand};
                end
            end else begin
                if (op.operator[0]) begin
                    op.result = op.result + op.operand;
                end
                op.operand = {op.operand[30:0], 1'b0};
                op.operator = {1'b0, op.operator[31:1]};
                op.done = (op.operator == 'b0);
            end
            return op;
        end
        RISCV32M_FUNCT3_MULH: begin
            // Use Booth's Algorithm
            if (!op.operator[0] && op.flag) begin
                op.result = op.result + op.operand;
            end else if (op.operator[0] && !op.flag) begin
                op.result = op.result - op.operand;
            end
            op.flag = op.operator[0];
            op.result = {op.result[31], op.result[31:1]};
            op.operator = {1'b0, op.operator[31:1]};
            op.done = (op.operator == 'b0);
            return op;
        end
        // TODO: Fix performance of MULHSU (does not always need 34 cycles)
        RISCV32M_FUNCT3_MULHSU: begin
            if (current_iteration == 'b0) begin // ABS operand and record
                if (op.operand[31]) begin // Flip sign
                    op.flag = 'b1;
                    op.operand = 'b0 - op.operand;
                end
            end else if (current_iteration == 'd33) begin // Flip sign if necessary
                if (op.flag) begin
                    op.result = ~op.result;
                    // Only perform the increment if the zeros flag remained active,
                    // otherwise the addition would get "eaten" by LSBs
                    if (op.operator[31]) begin
                        op.result = op.result + 'b1;
                    end
                end
                op.done = 'b1;
            end else begin // iterations 1...31
                if (op.operator[0]) begin
                    {carry, op.result} = op.result + op.operand;
                end
                if (current_iteration == 'b1) begin
                    // Shift operator and use msb to store if the
                    // shifted out result was a zero
                    op.operator = {!op.result[0], op.operator[31:1]};
                end else begin
                    // Continue shifting operator and record if
                    // shifted out result was all zeros
                    op.operator = {!op.result[0] && op.operator[31], op.operator[31:1]};
                end
                op.result = {carry, op.result[31:1]};
            end
            return op;
        end
        RISCV32M_FUNCT3_MULHU: begin
            if (op.operator[0]) begin
                {carry, op.result} = op.result + op.operand;
            end
            op.result = {carry, op.result[31:1]};
            op.operator = {1'b0, op.operator[31:1]};
            op.done = (op.operator == 'b0);
            return op;
        end
        // TODO: CRITICAL: Support signed division (I hate thinking about it)
        RISCV32M_FUNCT3_DIV, RISCV32M_FUNCT3_REM,
        // : begin
        //     if (current_iteration == 'd0) begin // Find ABS of first arg
        //         if (op.operand[31]) begin
        //             op.flag = 'b1;
        //             op.operand = 'b0 - op.operand;
        //         end
        //     end else if (current_iteration == 'd1) begin // Find ABS of second arg
        //         if (op.operator[31]) begin
        //             op.flag = ~op.flag; // Make flag zero again if both negative
        //             op.operator = 'b0 = op.operator;
        //         end
        //     end else if (current_iteration == 'd34) begin // Invert result if necessary
        //         if (op.flag) begin

        //         end
        //     end else begin
        //         // Left shift remainder, fill in with numerator MSB
        //         op.result = {op.result[30:0], op.operand[31]};
        //         // If remainder >= divisor (or fills in ones if division by zero)
        //         if ((op.result >= op.operator) || (op.operator == 0)) begin
        //             // Subtract divisor from remainder
        //             op.result = op.result - op.operator;
        //             // Fill in quotient with one (replaces operand lsb)
        //             op.operand = {op.operand[30:0], 1'b1};
        //         end else begin
        //             // Fill in quotient with zero
        //             op.operand = {op.operand[30:0], 1'b0};
        //         end
        //     end
        // end
        RISCV32M_FUNCT3_DIVU, RISCV32M_FUNCT3_REMU: begin

            // // Does single cycle division change anything?
            // for (i = 0; i < 32; i++) begin

            // Left shift remainder, fill in with numerator MSB
            op.result = {op.result[30:0], op.operand[31]};
            // If remainder >= divisor (or fills in ones if division by zero)
            if ((op.result >= op.operator) || (op.operator == 0)) begin
                // Subtract divisor from remainder
                op.result = op.result - op.operator;
                // Fill in quotient with one (replaces operand lsb)
                op.operand = {op.operand[30:0], 1'b1};
            end else begin
                // Fill in quotient with zero
                op.operand = {op.operand[30:0], 1'b0};
            end

            // end
            // op.done = 'b1;

            // TODO: Fix division performance, does not have to run all cycles
            op.done = (current_iteration == 'd31);

            // Q := 0, R := 0
            // for i := n − 1 .. 0 do
            //     R := R << 1           -- Left-shift R by 1 bit
            //     R(0) := OPERAND(i)    -- Set the least-significant bit of R equal to bit i of the numerator
            //     if R ≥ OPERATOR then
            //         R := R − OPERATOR
            //         Q(i) := 1
            //     end
            // end

            return op;
        end
        endcase

    endfunction

endpackage
