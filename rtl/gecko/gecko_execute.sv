//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import riscv/riscv32i_pkg.sv
//!import riscv/riscv32m_pkg.sv
//!import gecko/gecko_pkg.sv
//!import stream/stream_intf.sv
//!import mem/mem_intf.sv
//!import std/std_register.sv
//!import stream/stream_stage.sv
//!import stream/stream_controller.sv
//!import mem/mem_stage.sv
//!wrapper gecko/gecko_execute_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

module gecko_execute
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import riscv32m_pkg::*;
    import gecko_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter bit ENABLE_INTEGER_MATH = 0 // Supports iterative division and multiplication
)(
    input wire clk, 
    input wire rst,

    stream_intf.in execute_command, // gecko_execute_operation_t

    stream_intf.out mem_command, // gecko_mem_operation_t
    mem_intf.out mem_request,
    stream_intf.out execute_result, // gecko_operation_t
    stream_intf.out jump_command // gecko_jump_operation_t
);

    typedef logic [5:0] iteration_t;

    stream_intf #(.T(gecko_mem_operation_t)) next_mem_command (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) next_mem_request (.clk, .rst);
    stream_intf #(.T(gecko_operation_t)) next_execute_result (.clk, .rst);
    stream_intf #(.T(gecko_jump_operation_t)) next_jump_command (.clk, .rst);

    logic enable;
    logic consume;
    logic produce_mem_command, produce_mem_request, produce_execute, produce_jump; 

    stream_controller #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(4)
    ) stream_controller_inst (
        .clk, .rst,

        .valid_input({execute_command.valid}),
        .ready_input({execute_command.ready}),

        .valid_output({next_mem_command.valid, next_mem_request.valid, next_execute_result.valid, next_jump_command.valid}),
        .ready_output({next_mem_command.ready, next_mem_request.ready, next_execute_result.ready, next_jump_command.ready}),

        .consume, 
        .produce({produce_mem_command, produce_mem_request, produce_execute, produce_jump}),
        .enable
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(gecko_mem_operation_t)
    ) mem_command_output_stage (
        .clk, .rst,
        .stream_in(next_mem_command), 
        .stream_out(mem_command)
    );

    mem_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE)
    ) mem_request_output_stage (
        .clk, .rst,
        .mem_in(next_mem_request), 
        .mem_in_meta('b0),
        .mem_out(mem_request),
        .mem_out_meta()
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(gecko_operation_t)
    ) execute_result_output_stage (
        .clk, .rst,
        .stream_in(next_execute_result), 
        .stream_out(execute_result)
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(gecko_jump_operation_t)
    ) jump_command_output_stage (
        .clk, .rst,
        .stream_in(next_jump_command), 
        .stream_out(jump_command)
    );

    riscv32_reg_value_t current_execute_value;

    iteration_t current_iteration, next_iteration;
    gecko_math_operation_t current_math_op, next_math_op;

    logic mispredicted, mispredicted_next;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic),
        .RESET_VECTOR('b0)
    ) mispredicted_register (
        .clk, 
        .rst,
        .enable,
        .next(mispredicted_next),
        .value(mispredicted)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(riscv32_reg_value_t),
        .RESET_VECTOR('b0)
    ) execute_value_register (
        .clk, 
        .rst(std_get_reset(CLOCK_INFO, 0)), // No reset
        .enable(enable && produce_execute),
        .next(next_execute_result.payload.value),
        .value(current_execute_value)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(iteration_t),
        .RESET_VECTOR('b0)
    ) iteration_register (
        .clk, .rst,
        .enable,
        .next(next_iteration),
        .value(current_iteration)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(gecko_math_operation_t),
        .RESET_VECTOR('b0)
    ) math_op_register (
        .clk, 
        .rst(std_get_reset(CLOCK_INFO, 0)), // No reset
        .enable,
        .next(next_math_op),
        .value(current_math_op)
    );

    always_comb begin
        automatic riscv32_reg_value_t a, b, c, d;
        automatic gecko_execute_operation_t cmd_in;
        automatic gecko_alternate_t alt;
        automatic gecko_math_result_t alu_result;
        automatic gecko_store_result_t store_result;
        automatic gecko_math_operation_t math_op;

        cmd_in = gecko_execute_operation_t'(execute_command.payload);

        // Clear mispredicted if the instruction stream updated
        mispredicted_next = mispredicted;
        if (execute_command.payload.pc_updated) begin
            mispredicted_next = 'b0;
        end

        next_iteration = current_iteration;
        next_math_op = current_math_op;

        a = (cmd_in.reuse_rs1) ? current_execute_value : cmd_in.rs1_value;
        b = (cmd_in.reuse_rs2) ? current_execute_value : cmd_in.rs2_value;
        c = (cmd_in.reuse_mem) ? current_execute_value : cmd_in.mem_value;
        d = (cmd_in.reuse_jump) ? current_execute_value : cmd_in.jump_value;

        // Sort out math with alternate flags
        case (cmd_in.op_type)
        GECKO_EXECUTE_TYPE_EXECUTE: begin
            // Supports SLT and SLTU
            if (cmd_in.op.ir == RISCV32I_FUNCT3_IR_ADD_SUB || 
                    cmd_in.op.ir == RISCV32I_FUNCT3_IR_SRL_SRA) begin
                alt = cmd_in.alu_alternate;
            end else begin
                alt = GECKO_ALTERNATE;
            end
        end 
        GECKO_EXECUTE_TYPE_LOAD: alt = GECKO_NORMAL;
        GECKO_EXECUTE_TYPE_STORE: alt = GECKO_NORMAL;
        GECKO_EXECUTE_TYPE_BRANCH: alt = GECKO_ALTERNATE;
        GECKO_EXECUTE_TYPE_MUL_DIV: begin
            alt = GECKO_NORMAL;
        end
        default: alt = GECKO_NORMAL;
        endcase

        alu_result = gecko_get_full_math_result(a, b, alt);
        store_result = gecko_get_store_result(c, alu_result.add_sub_result[1:0], cmd_in.op.ls);

        next_execute_result.payload = '{default: 'b0};
        next_execute_result.payload.value = alu_result.add_sub_result;
        next_execute_result.payload.addr = cmd_in.reg_addr;
        next_execute_result.payload.reg_status = cmd_in.reg_status;
        next_execute_result.payload.jump_flag = cmd_in.jump_flag;

        next_mem_command.payload = '{default: 'b0};
        next_mem_command.payload.addr = cmd_in.reg_addr;
        next_mem_command.payload.op = cmd_in.op.ls;
        next_mem_command.payload.offset = 'b0;
        next_mem_command.payload.reg_status = cmd_in.reg_status;
        next_mem_command.payload.jump_flag = cmd_in.jump_flag;

        next_jump_command.payload = '{default: 'b0};
        next_jump_command.payload.current_pc = cmd_in.current_pc;
        next_jump_command.payload.prediction = cmd_in.prediction;

        next_mem_request.read_enable = 'b0;
        next_mem_request.write_enable = 'b0;
        next_mem_request.addr = 'b0;
        next_mem_request.data = 'b0;

        produce_mem_command = 'b0;
        produce_mem_request = 'b0;
        produce_execute = 'b0;
        produce_jump = 'b0;

        if ((current_iteration != 'b0) && ENABLE_INTEGER_MATH) begin // Math loop iterations

            // Perform math operation
            next_math_op = gecko_math_operation_step(current_math_op, current_iteration);

            // If operation signals it is done
            if (next_math_op.done) begin
                next_iteration = 'b0;
                produce_execute = 'b1;
                consume = 'b1;
            end else begin
                next_iteration = current_iteration + 'b1;
                consume = 'b0;
            end

            // Only for division is the result stored in the operand
            // Use the next values so we can fully run 32 cycles
            case (current_math_op.math_op)
            RISCV32M_FUNCT3_DIV, RISCV32M_FUNCT3_DIVU: next_execute_result.payload.value = next_math_op.operand_value;
            default: next_execute_result.payload.value = next_math_op.result;
            endcase

        end else begin // Normal ALU operations
            consume = 'b1;

            case (cmd_in.op_type)
            GECKO_EXECUTE_TYPE_EXECUTE: begin
                produce_execute = 'b1;

                case (cmd_in.op.ir)
                RISCV32I_FUNCT3_IR_ADD_SUB: next_execute_result.payload.value = alu_result.add_sub_result;
                RISCV32I_FUNCT3_IR_SLL: next_execute_result.payload.value = alu_result.lshift_result;
                RISCV32I_FUNCT3_IR_SLT: next_execute_result.payload.value = alu_result.lt ? 32'b1 : 32'b0;
                RISCV32I_FUNCT3_IR_SLTU: next_execute_result.payload.value = alu_result.ltu ? 32'b1 : 32'b0;
                RISCV32I_FUNCT3_IR_XOR: next_execute_result.payload.value = alu_result.xor_result;
                RISCV32I_FUNCT3_IR_SRL_SRA: next_execute_result.payload.value = alu_result.rshift_result;
                RISCV32I_FUNCT3_IR_OR: next_execute_result.payload.value = alu_result.or_result;
                RISCV32I_FUNCT3_IR_AND: next_execute_result.payload.value = alu_result.and_result;
                endcase
            end
            GECKO_EXECUTE_TYPE_LOAD: begin
                produce_mem_request = 'b1;
                produce_mem_command = 'b1;

                next_mem_request.addr = alu_result.add_sub_result;
                next_mem_request.read_enable = 'b1;

                next_mem_command.payload.offset = alu_result.add_sub_result[1:0];
            end
            GECKO_EXECUTE_TYPE_STORE: begin
                produce_mem_request = 'b1;

                next_mem_request.addr = alu_result.add_sub_result;
                next_mem_request.data = store_result.value;
                next_mem_request.write_enable = store_result.mask;
            end
            GECKO_EXECUTE_TYPE_BRANCH: begin
                produce_jump = 'b1;
                
                if (gecko_evaluate_branch(alu_result, cmd_in.op)) begin
                    next_jump_command.payload.branched = 'b1;
                    next_jump_command.payload.actual_next_pc = cmd_in.current_pc + cmd_in.immediate_value;
                end else begin
                    next_jump_command.payload.branched = 'b0;
                    next_jump_command.payload.actual_next_pc = cmd_in.current_pc + 'd4;
                end

                next_jump_command.payload.update_pc = (next_jump_command.payload.actual_next_pc != cmd_in.next_pc);

                mispredicted_next = next_jump_command.payload.update_pc;
            end
            GECKO_EXECUTE_TYPE_JUMP: begin
                produce_execute = (cmd_in.reg_addr != 'b0) && !cmd_in.halt;
                produce_jump = 'b1;

                next_jump_command.payload.halt = cmd_in.halt;
                next_jump_command.payload.actual_next_pc = d + cmd_in.immediate_value;
                next_jump_command.payload.jumped = 'b1;
                next_jump_command.payload.update_pc = (next_jump_command.payload.actual_next_pc != cmd_in.next_pc);

                mispredicted_next = next_jump_command.payload.update_pc;
            end
            GECKO_EXECUTE_TYPE_MUL_DIV: begin
                if (ENABLE_INTEGER_MATH) begin
                    // Do not consume the input stream until operation is done
                    consume = 'b0;

                    // Only start operation is the command is actually valid
                    if (execute_command.valid) begin

                        // Perform math operation
                        next_math_op = gecko_math_operation_step('{
                            math_op: riscv32m_funct3_t'(cmd_in.op),
                            operand_value: a,
                            operator_value: b,
                            flag: 'b0,
                            done: 'b0,
                            result: 'b0
                        }, current_iteration);

                        // Start iteration counter
                        next_iteration = 'b1;

                        // // TODO: Remove this, just for testing
                        // if (next_math_op.done) begin
                        //     next_iteration = 'b0;
                        //     produce_execute = 'b1;
                        //     consume = 'b1;

                        //     case (next_math_op.math_op)
                        //     RISCV32M_FUNCT3_DIV, RISCV32M_FUNCT3_DIVU: 
                        //         next_execute_result.payload.value = 
                        //             next_math_op.operand_value;
                        //     default: 
                        //         next_execute_result.payload.value = 
                        //             next_math_op.result;
                        //     endcase
                        // end
                    end
                end else begin
                    produce_execute = 'b1;
                    next_execute_result.payload.value = 'b0;
                end
            end
            default: begin end
            endcase

            if (mispredicted && !execute_command.payload.pc_updated) begin
                // Do not produce memory access if mispredicted
                produce_mem_request = 'b0;
                // Mark memory and execute instructions as mispredicted
                next_mem_command.payload.mispredicted = 'b1;
                next_execute_result.payload.mispredicted = 'b1;
                next_jump_command.payload.mispredicted = 'b1;
                // Do not clear the mispredicted register if an earlier jump was mispredicted
                mispredicted_next = mispredicted;
            end 
        end
    end

endmodule
