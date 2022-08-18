//!import stream/stream_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import riscv/riscv32i_pkg.sv
//!import riscv/riscv32m_pkg.sv
//!no_lint

package gecko_pkg;

    import stream_pkg::*;

    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import riscv32m_pkg::*;

    typedef riscv32_reg_value_t gecko_pc_t;

    typedef logic [1:0] gecko_byte_offset_t;
    typedef logic [3:0] gecko_store_mask_t;

    // Configurable Types
    typedef logic [1:0] gecko_jump_flag_t;
    typedef logic [2:0] gecko_reg_status_t;
    // typedef logic [2:0] gecko_inst_count_t;
    // typedef logic [4:0] gecko_retired_count_t;
    typedef logic [7:0] gecko_prediction_history_t;

    typedef enum logic [1:0] {
        GECKO_BRANCH_PREDICTOR_MODE_NONE = 'h0,
        GECKO_BRANCH_PREDICTOR_MODE_SIMPLE = 'h1,
        GECKO_BRANCH_PREDICTOR_MODE_GLOBAL = 'h2,
        GECKO_BRANCH_PREDICTOR_MODE_LOCAL = 'h3
    } gecko_branch_predictor_mode_t;

    typedef enum logic [1:0] {
        GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_TAKEN = 'h0,
        GECKO_BRANCH_PREDICTOR_HISTORY_TAKEN = 'h1,
        GECKO_BRANCH_PREDICTOR_HISTORY_NOT_TAKEN = 'h2,
        GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_NOT_TAKEN = 'h3
    } gecko_branch_predictor_history_t;

    function automatic logic gecko_branch_predictor_is_taken(
            input gecko_branch_predictor_history_t history
    );
        return history == GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_TAKEN || 
                history == GECKO_BRANCH_PREDICTOR_HISTORY_TAKEN;
    endfunction

    function automatic gecko_branch_predictor_history_t gecko_branch_predictor_update_history(
            input gecko_branch_predictor_history_t history,
            input logic took_branch
    );
        unique case (history)
        GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_TAKEN: return took_branch ? 
                GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_TAKEN : 
                GECKO_BRANCH_PREDICTOR_HISTORY_TAKEN;
        GECKO_BRANCH_PREDICTOR_HISTORY_TAKEN: return took_branch ? 
                GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_TAKEN : 
                GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_NOT_TAKEN;
        GECKO_BRANCH_PREDICTOR_HISTORY_NOT_TAKEN: return took_branch ? 
                GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_TAKEN : 
                GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_NOT_TAKEN;
        GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_NOT_TAKEN: return took_branch ? 
                GECKO_BRANCH_PREDICTOR_HISTORY_NOT_TAKEN : 
                GECKO_BRANCH_PREDICTOR_HISTORY_STRONG_NOT_TAKEN;
        endcase
    endfunction

    parameter gecko_reg_status_t GECKO_REG_STATUS_VALID = '0;
    parameter gecko_reg_status_t GECKO_REG_STATUS_FULL = '1;

    // parameter gecko_speculative_count_t GECKO_SPECULATIVE_FULL = '1;

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
        gecko_branch_predictor_history_t history;
    } gecko_prediction_t;

    // Internal Gecko Stream Datatypes -----------------------------------------

    typedef struct packed {
        riscv32_reg_addr_t addr;
        gecko_reg_status_t reg_status;
        gecko_jump_flag_t jump_flag;
        riscv32_reg_value_t value;
        logic mispredicted;
    } gecko_operation_t;

    typedef struct packed {
        logic valid;
        riscv32_reg_addr_t addr;
        gecko_jump_flag_t jump_flag;
        gecko_reg_status_t reg_status;
        riscv32_reg_value_t value;
        logic mispredicted;
    } gecko_forwarded_t;

    typedef struct packed {
        logic update_pc, branched, jumped;
        gecko_pc_t current_pc, actual_next_pc;
        gecko_prediction_t prediction;
        logic halt;
        logic mispredicted;
    } gecko_jump_operation_t;

    typedef struct packed {
        gecko_pc_t pc, next_pc;
        gecko_prediction_t prediction;
        logic pc_updated;
    } gecko_instruction_operation_t;

    typedef struct packed {
        riscv32_reg_addr_t addr;
        gecko_reg_status_t reg_status;
        gecko_jump_flag_t jump_flag;
        riscv32i_funct3_ls_t op;
        gecko_byte_offset_t offset;
        logic mispredicted;
    } gecko_mem_operation_t;

    typedef struct packed {
        riscv32_reg_addr_t reg_addr;
        gecko_reg_status_t reg_status;
        gecko_jump_flag_t jump_flag;
        riscv32_reg_value_t imm_value;
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
        logic pc_updated;
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
        riscv32_reg_value_t sys_imm;
        riscv32_funct12_t sys_csr;
    } gecko_float_operation_t;

    // Internal Gecko Helper Functions -----------------------------------------

    function automatic gecko_forwarded_t gecko_construct_forward(
        input logic valid,
        input gecko_operation_t op
    );
        return '{
            addr: op.addr,
            reg_status: op.reg_status,
            jump_flag: op.jump_flag,
            valid: valid,
            mispredicted: op.mispredicted,
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
        {result.carry, result.sum} = a + b_inv + {32'b0, sub};
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
            mispredicted: mem_op.mispredicted
        };
    endfunction

    // Gecko Integer Math Helpers ----------------------------------------------

    typedef struct packed {
        riscv32m_funct3_t math_op;
        riscv32_reg_value_t operand_value; // rs1, multiplicand, dividend
        riscv32_reg_value_t operator_value; // rs2, multiplier, divisor
        riscv32_reg_value_t result;
        logic flag;
        logic done;
    } gecko_math_operation_t;

    function automatic gecko_math_operation_t gecko_math_operation_step(
        input gecko_math_operation_t op_input,
        logic [5:0] current_iteration
    );
        gecko_math_operation_t op = op_input;
        logic carry = 1'b0;
        int i;

        unique case (op.math_op)
        RISCV32M_FUNCT3_MUL: begin
            if (current_iteration == 'b0) begin
                // Swap lesser value into operator_value to save cycles
                if (op.operand_value < op.operator_value) begin
                    op.operand_value = op.operator_value;
                    op.operator_value = op.operand_value;
                end
            end else begin
                if (op.operator_value[0]) begin
                    op.result = op.result + op.operand_value;
                end
                op.operand_value = {op.operand_value[30:0], 1'b0};
                op.operator_value = {1'b0, op.operator_value[31:1]};
                op.done = (op.operator_value == 'b0);
            end
        end
        RISCV32M_FUNCT3_MULH: begin
            // Use Booth's Algorithm
            if (!op.operator_value[0] && op.flag) begin
                op.result = op.result + op.operand_value;
            end else if (op.operator_value[0] && !op.flag) begin
                op.result = op.result - op.operand_value;
            end
            op.flag = op.operator_value[0];
            op.result = {op.result[31], op.result[31:1]};
            op.operator_value = {1'b0, op.operator_value[31:1]};
            op.done = (op.operator_value == 'b0);
        end
        // TODO: Fix performance of MULHSU (does not always need 34 cycles)
        RISCV32M_FUNCT3_MULHSU: begin
            if (current_iteration == 'b0) begin // ABS operand_value and record
                if (op.operand_value[31]) begin // Flip sign
                    op.flag = 'b1;
                    op.operand_value = 'b0 - op.operand_value;
                end
            end else if (current_iteration == 'd33) begin // Flip sign if necessary
                if (op.flag) begin
                    op.result = ~op.result;
                    // Only perform the increment if the zeros flag remained active,
                    // otherwise the addition would get "eaten" by LSBs
                    if (op.operator_value[31]) begin
                        op.result = op.result + 'b1;
                    end
                end
                op.done = 'b1;
            end else begin // iterations 1...31
                if (op.operator_value[0]) begin
                    {carry, op.result} = op.result + op.operand_value;
                end
                if (current_iteration == 'b1) begin
                    // Shift operator_value and use msb to store if the
                    // shifted out result was a zero
                    op.operator_value = {!op.result[0], op.operator_value[31:1]};
                end else begin
                    // Continue shifting operator_value and record if
                    // shifted out result was all zeros
                    op.operator_value = {!op.result[0] && op.operator_value[31], op.operator_value[31:1]};
                end
                op.result = {carry, op.result[31:1]};
            end
        end
        RISCV32M_FUNCT3_MULHU: begin
            if (op.operator_value[0]) begin
                {carry, op.result} = op.result + op.operand_value;
            end
            op.result = {carry, op.result[31:1]};
            op.operator_value = {1'b0, op.operator_value[31:1]};
            op.done = (op.operator_value == 'b0);
        end
        // TODO: CRITICAL: Support signed division (I hate thinking about it)
        RISCV32M_FUNCT3_DIV, RISCV32M_FUNCT3_REM,
        // : begin
        //     if (current_iteration == 'd0) begin // Find ABS of first arg
        //         if (op.operand_value[31]) begin
        //             op.flag = 'b1;
        //             op.operand_value = 'b0 - op.operand_value;
        //         end
        //     end else if (current_iteration == 'd1) begin // Find ABS of second arg
        //         if (op.operator_value[31]) begin
        //             op.flag = ~op.flag; // Make flag zero again if both negative
        //             op.operator_value = 'b0 = op.operator_value;
        //         end
        //     end else if (current_iteration == 'd34) begin // Invert result if necessary
        //         if (op.flag) begin

        //         end
        //     end else begin
        //         // Left shift remainder, fill in with numerator MSB
        //         op.result = {op.result[30:0], op.operand_value[31]};
        //         // If remainder >= divisor (or fills in ones if division by zero)
        //         if ((op.result >= op.operator_value) || (op.operator_value == 0)) begin
        //             // Subtract divisor from remainder
        //             op.result = op.result - op.operator_value;
        //             // Fill in quotient with one (replaces operand_value lsb)
        //             op.operand_value = {op.operand_value[30:0], 1'b1};
        //         end else begin
        //             // Fill in quotient with zero
        //             op.operand_value = {op.operand_value[30:0], 1'b0};
        //         end
        //     end
        // end
        RISCV32M_FUNCT3_DIVU, RISCV32M_FUNCT3_REMU: begin
            // Left shift remainder, fill in with numerator MSB
            op.result = {op.result[30:0], op.operand_value[31]};
            // If remainder >= divisor (or fills in ones if division by zero)
            if ((op.result >= op.operator_value) || (op.operator_value == 0)) begin
                // Subtract divisor from remainder
                op.result = op.result - op.operator_value;
                // Fill in quotient with one (replaces operand_value lsb)
                op.operand_value = {op.operand_value[30:0], 1'b1};
            end else begin
                // Fill in quotient with zero
                op.operand_value = {op.operand_value[30:0], 1'b0};
            end

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
        end
        endcase

        return op;
    endfunction

    // Gecko core configuration ------------------------------------------------

    typedef struct packed {
        gecko_branch_predictor_mode_t mode;
        int                           target_addr_width;
        int                           history_width;
        int                           local_addr_width;
    } gecko_branch_predictor_config_t;

    typedef struct packed {
        gecko_pc_t start_addr;
        // Internal pipeline
        stream_pipeline_mode_t fetch_pipeline_mode;
        stream_pipeline_mode_t imem_pipeline_mode;
        stream_pipeline_mode_t decode_pipeline_mode;
        stream_pipeline_mode_t execute_pipeline_mode;
        stream_pipeline_mode_t system_pipeline_mode;
        stream_pipeline_mode_t print_pipeline_mode;
        stream_pipeline_mode_t writeback_pipeline_mode;
        int                    instruction_memory_latency;
        int                    data_memory_latency;
        int                    float_memory_latency;
        // Branch predictor
        gecko_branch_predictor_config_t branch_predictor_config;
        // Features
        bit enable_performance_counters;
        bit enable_tty_io;
        // bit enable_print_out;
        bit enable_floating_point;
        bit enable_integer_math;
    } gecko_config_t;

    function automatic gecko_branch_predictor_config_t gecko_get_basic_branch_predictor_config();
        int addr_width = 5;
        return gecko_branch_predictor_config_t'{
            mode: GECKO_BRANCH_PREDICTOR_MODE_SIMPLE,
            target_addr_width: addr_width,
            history_width: addr_width,
            local_addr_width: addr_width
        };
    endfunction

    function automatic gecko_config_t gecko_get_basic_config(
        input int instruction_memory_latency,
        input int data_memory_latency,
        input int float_memory_latency
    );
        return gecko_config_t'{
            start_addr: 'b0,
            fetch_pipeline_mode: STREAM_PIPELINE_MODE_TRANSPARENT,
            imem_pipeline_mode: STREAM_PIPELINE_MODE_TRANSPARENT,
            decode_pipeline_mode: STREAM_PIPELINE_MODE_REGISTERED,
            execute_pipeline_mode: STREAM_PIPELINE_MODE_REGISTERED,
            system_pipeline_mode: STREAM_PIPELINE_MODE_REGISTERED,
            print_pipeline_mode: STREAM_PIPELINE_MODE_REGISTERED,
            writeback_pipeline_mode: STREAM_PIPELINE_MODE_REGISTERED,
            instruction_memory_latency: instruction_memory_latency,
            data_memory_latency: data_memory_latency,
            float_memory_latency: float_memory_latency,
            branch_predictor_config: gecko_get_basic_branch_predictor_config(),
            enable_performance_counters: 1,
            enable_tty_io: 1,
            enable_floating_point: 0,
            enable_integer_math: 0
        };
    endfunction    

    // Gecko performance metrics -----------------------------------------------

    typedef struct packed {
        logic instruction_mispredicted;
        logic instruction_data_stalled;
        logic instruction_control_stalled;
        logic frontend_stalled;
        logic backend_stalled;
    } gecko_performance_stats_t;

endpackage
