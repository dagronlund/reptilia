`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/gecko/gecko.svh"

`else

`include "std_util.svh"
`include "std_mem.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32i.svh"
`include "gecko.svh"

`endif

module gecko_execute
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#(
    parameter int OUTPUT_REGISTER_MODE = 1
)(
    input logic clk, rst,

    std_stream_intf.in execute_command, // gecko_execute_operation_t

    std_stream_intf.out mem_command, // gecko_mem_operation_t
    std_mem_intf.out mem_request,
    std_stream_intf.out execute_result, // gecko_operation_t
    std_stream_intf.out jump_command // gecko_jump_operation_t
);

    std_stream_intf #(.T(gecko_mem_operation_t)) next_mem_command (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) next_mem_request (.clk, .rst);
    std_stream_intf #(.T(gecko_operation_t)) next_execute_result (.clk, .rst);
    std_stream_intf #(.T(gecko_jump_operation_t)) next_jump_command (.clk, .rst);

    logic enable;
    logic consume;
    logic produce_mem_command, produce_mem_request, produce_execute, produce_jump; 

    std_flow_lite #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(4)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({execute_command.valid}),
        .ready_input({execute_command.ready}),

        .valid_output({next_mem_command.valid, next_mem_request.valid, next_execute_result.valid, next_jump_command.valid}),
        .ready_output({next_mem_command.ready, next_mem_request.ready, next_execute_result.ready, next_jump_command.ready}),

        .consume, 
        .produce({produce_mem_command, produce_mem_request, produce_execute, produce_jump}),
        .enable
    );

    std_flow_stage #(
        .T(gecko_mem_operation_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) mem_command_output_stage (
        .clk, .rst,
        .stream_in(next_mem_command), .stream_out(mem_command)
    );

    mem_stage #(
        .MODE(OUTPUT_REGISTER_MODE)
    ) mem_request_output_stage (
        .clk, .rst,
        .mem_in(next_mem_request), .mem_out(mem_request)
    );

    std_flow_stage #(
        .T(gecko_operation_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) execute_result_output_stage (
        .clk, .rst,
        .stream_in(next_execute_result), .stream_out(execute_result)
    );

    std_flow_stage #(
        .T(gecko_jump_operation_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) jump_command_output_stage (
        .clk, .rst,
        .stream_in(next_jump_command), .stream_out(jump_command)
    );

    rv32_reg_value_t current_execute_value;

    always_ff @(posedge clk) begin
        if (enable && produce_execute) begin
            current_execute_value <= next_execute_result.payload.value;
        end
    end

    always_comb begin
        automatic rv32_reg_value_t a, b, c, d;
        automatic gecko_execute_operation_t cmd_in;
        automatic gecko_alternate_t alt;
        automatic gecko_math_result_t result;
        automatic gecko_store_result_t store_result;
        
        automatic logic take_branch;

        cmd_in = gecko_execute_operation_t'(execute_command.payload);

        a = (cmd_in.reuse_rs1) ? current_execute_value : cmd_in.rs1_value;
        b = (cmd_in.reuse_rs2) ? current_execute_value : cmd_in.rs2_value;
        c = (cmd_in.reuse_mem) ? current_execute_value : cmd_in.mem_value;
        d = (cmd_in.reuse_jump) ? current_execute_value : cmd_in.jump_value;

        consume = 'b1;
        produce_mem_command = 'b0;
        produce_mem_request = 'b0;
        produce_execute = 'b0;
        produce_jump = 'b0;

        // Sort out math with alternate flags
        case (cmd_in.op_type)
        GECKO_EXECUTE_TYPE_EXECUTE: begin
            // Supports SLT and SLTU
            if (cmd_in.op.ir == RV32I_FUNCT3_IR_ADD_SUB || 
                    cmd_in.op.ir == RV32I_FUNCT3_IR_SRL_SRA) begin
                alt = cmd_in.alu_alternate;
            end else begin
                alt = GECKO_ALTERNATE;
            end
        end 
        GECKO_EXECUTE_TYPE_LOAD: alt = GECKO_NORMAL;
        GECKO_EXECUTE_TYPE_STORE: alt = GECKO_NORMAL;
        GECKO_EXECUTE_TYPE_BRANCH: alt = GECKO_ALTERNATE;
        default: alt = GECKO_NORMAL;
        endcase

        result = gecko_get_full_math_result(a, b, alt);

        next_execute_result.payload.value = result.add_sub_result;
        next_execute_result.payload.addr = cmd_in.reg_addr;
        next_execute_result.payload.speculative = cmd_in.speculative;
        next_execute_result.payload.reg_status = cmd_in.reg_status;
        next_execute_result.payload.jump_flag = cmd_in.jump_flag;

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

        case (cmd_in.op_type)
        GECKO_EXECUTE_TYPE_EXECUTE: begin
            produce_execute = 'b1;

            case (cmd_in.op.ir)
            RV32I_FUNCT3_IR_ADD_SUB: next_execute_result.payload.value = result.add_sub_result;
            RV32I_FUNCT3_IR_SLL: next_execute_result.payload.value = result.lshift_result;
            RV32I_FUNCT3_IR_SLT: next_execute_result.payload.value = result.lt ? 32'b1 : 32'b0;
            RV32I_FUNCT3_IR_SLTU: next_execute_result.payload.value = result.ltu ? 32'b1 : 32'b0;
            RV32I_FUNCT3_IR_XOR: next_execute_result.payload.value = result.xor_result;
            RV32I_FUNCT3_IR_SRL_SRA: next_execute_result.payload.value = result.rshift_result;
            RV32I_FUNCT3_IR_OR: next_execute_result.payload.value = result.or_result;
            RV32I_FUNCT3_IR_AND: next_execute_result.payload.value = result.and_result;
            endcase
        end
        GECKO_EXECUTE_TYPE_LOAD: begin
            produce_mem_request = 'b1;
            produce_mem_command = 'b1;

            next_mem_request.addr = result.add_sub_result;
            next_mem_request.read_enable = 'b1;

            next_mem_command.payload.offset = result.add_sub_result[1:0];
        end
        GECKO_EXECUTE_TYPE_STORE: begin
            produce_mem_request = 'b1;

            store_result = gecko_get_store_result(c, result.add_sub_result[1:0], cmd_in.op.ls);

            next_mem_request.addr = result.add_sub_result;
            next_mem_request.data = store_result.value;
            next_mem_request.write_enable = store_result.mask;
        end
        GECKO_EXECUTE_TYPE_BRANCH: begin
            produce_jump = 'b1;
            
            take_branch = gecko_evaluate_branch(result, cmd_in.op);

            if (take_branch) begin
                next_jump_command.payload.branched = 'b1;
                next_jump_command.payload.actual_next_pc = cmd_in.current_pc + cmd_in.immediate_value;
            end else begin
                next_jump_command.payload.branched = 'b0;
                next_jump_command.payload.actual_next_pc = cmd_in.current_pc + 'd4;
            end

            next_jump_command.payload.update_pc = (next_jump_command.payload.actual_next_pc != cmd_in.next_pc);
        end
        GECKO_EXECUTE_TYPE_JUMP: begin
            produce_execute = (cmd_in.reg_addr != 'b0) && !cmd_in.halt;
            produce_jump = 'b1;

            next_jump_command.payload.halt = cmd_in.halt;
            next_jump_command.payload.actual_next_pc = d + cmd_in.immediate_value;
            next_jump_command.payload.jumped = 'b1;
            next_jump_command.payload.update_pc = (next_jump_command.payload.actual_next_pc != cmd_in.next_pc);
        end
        endcase
    end

endmodule
