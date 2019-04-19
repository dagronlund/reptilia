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
(
    input logic clk, rst,

    std_stream_intf.in execute_command, // gecko_execute_operation_t

    std_stream_intf.out mem_command, // gecko_mem_operation_t
    std_mem_intf.out mem_request,

    std_stream_intf.out execute_result, // gecko_operation_t

    std_stream_intf.out jump_command // gecko_jump_operation_t
);

    logic enable, enable_mem_command, enable_mem_request, enable_execute, enable_jump;
    logic consume;
    logic produce_mem_command, produce_mem_request, produce_execute, produce_jump;

    // Flow Controller
    std_flow #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(4)
    ) std_flow_inst (
        .clk, .rst,

        .valid_input({execute_command.valid}),
        .ready_input({execute_command.ready}),
        
        .valid_output({mem_command.valid, mem_request.valid, execute_result.valid, jump_command.valid}),
        .ready_output({mem_command.ready, mem_request.ready, execute_result.ready, jump_command.ready}),

        .consume({consume}),
        .produce({produce_mem_command, produce_mem_request, produce_execute, produce_jump}),

        .enable,
        .enable_output({enable_mem_command, enable_mem_request, enable_execute, enable_jump})
    );

    gecko_operation_t next_execute_result;
    gecko_jump_operation_t next_jump_command;
    gecko_mem_operation_t next_mem_command;

    logic next_read_enable;
    logic [3:0] next_write_enable;
    logic [31:0] next_addr, next_data;

    always_ff @(posedge clk) begin
        if (enable_execute) begin
            execute_result.payload <= next_execute_result;
        end
        if (enable_jump) begin
            jump_command.payload <= next_jump_command;
        end
        if (enable_mem_command) begin
            mem_command.payload <= next_mem_command;
        end
        if (enable_mem_request) begin
            mem_request.read_enable <= next_read_enable;
            mem_request.write_enable <= next_write_enable;
            mem_request.addr <= next_addr;
            mem_request.data <= next_data;
        end
    end

    always_comb begin
        automatic gecko_operation_t current_execute_result;
        automatic rv32_reg_value_t a, b, c, d;
        automatic gecko_execute_operation_t cmd_in;
        automatic gecko_alternate_t alt;
        automatic gecko_math_result_t result;
        automatic gecko_store_result_t store_result;
        
        automatic logic take_branch;

        cmd_in = gecko_execute_operation_t'(execute_command.payload);
        current_execute_result = gecko_operation_t'(execute_result.payload);

        a = (cmd_in.reuse_rs1) ? current_execute_result.value : cmd_in.rs1_value;
        b = (cmd_in.reuse_rs2) ? current_execute_result.value : cmd_in.rs2_value;
        c = (cmd_in.reuse_mem) ? current_execute_result.value : cmd_in.mem_value;
        d = (cmd_in.reuse_jump) ? current_execute_result.value : cmd_in.jump_value;

        consume = 'b1;
        produce_mem_command = 'b0;
        produce_mem_request = 'b0;
        produce_execute = 'b0;
        produce_jump = 'b0;

        next_execute_result.value = 'b0;
        next_execute_result.addr = cmd_in.reg_addr;
        next_execute_result.speculative = cmd_in.speculative;
        next_execute_result.reg_status = cmd_in.reg_status;
        next_execute_result.jump_flag = cmd_in.jump_flag;

        next_mem_command.addr = cmd_in.reg_addr;
        next_mem_command.op = cmd_in.op.ls;
        next_mem_command.offset = 'b0;
        next_mem_command.reg_status = cmd_in.reg_status;
        next_mem_command.jump_flag = cmd_in.jump_flag;

        next_jump_command = '{default: 'b0};
        next_jump_command.current_pc = cmd_in.current_pc;
        next_jump_command.prediction = cmd_in.prediction;

        next_read_enable = 'b0;
        next_write_enable = 'b0;
        next_addr = 'b0;
        next_data = 'b0;

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

        case (cmd_in.op_type)
        GECKO_EXECUTE_TYPE_EXECUTE: begin
            produce_execute = 'b1;

            case (cmd_in.op.ir)
            RV32I_FUNCT3_IR_ADD_SUB: next_execute_result.value = result.add_sub_result;
            RV32I_FUNCT3_IR_SLL: next_execute_result.value = result.lshift_result;
            RV32I_FUNCT3_IR_SLT: next_execute_result.value = result.lt ? 32'b1 : 32'b0;
            RV32I_FUNCT3_IR_SLTU: next_execute_result.value = result.ltu ? 32'b1 : 32'b0;
            RV32I_FUNCT3_IR_XOR: next_execute_result.value = result.xor_result;
            RV32I_FUNCT3_IR_SRL_SRA: next_execute_result.value = result.rshift_result;
            RV32I_FUNCT3_IR_OR: next_execute_result.value = result.or_result;
            RV32I_FUNCT3_IR_AND: next_execute_result.value = result.and_result;
            endcase
        end
        GECKO_EXECUTE_TYPE_LOAD: begin
            produce_mem_request = 'b1;
            produce_mem_command = 'b1;

            next_addr = result.add_sub_result;
            next_read_enable = 'b1;

            next_mem_command.offset = next_addr[1:0];
        end
        GECKO_EXECUTE_TYPE_STORE: begin
            produce_mem_request = 'b1;

            store_result = gecko_get_store_result(c, result.add_sub_result[1:0], cmd_in.op.ls);

            next_addr = result.add_sub_result;
            next_data = store_result.value;
            next_write_enable = store_result.mask;
        end
        GECKO_EXECUTE_TYPE_BRANCH: begin
            produce_execute = 'b0;
            produce_jump = 'b1;

            next_execute_result.value = result.add_sub_result;
            
            take_branch = gecko_evaluate_branch(result, cmd_in.op);

            if (take_branch) begin
                next_jump_command.branched = 'b1;
                next_jump_command.actual_next_pc = cmd_in.current_pc + cmd_in.immediate_value;
            end else begin
                next_jump_command.branched = 'b0;
                next_jump_command.actual_next_pc = cmd_in.current_pc + 'd4;
            end

            if (next_jump_command.actual_next_pc != cmd_in.next_pc) begin
                next_jump_command.update_pc = 'b1;
            end
        end
        GECKO_EXECUTE_TYPE_JUMP: begin
            produce_execute = (cmd_in.reg_addr != 'b0);
            produce_jump = 'b1;

            next_execute_result.value = result.add_sub_result;

            next_jump_command.actual_next_pc = d + cmd_in.immediate_value;

            next_jump_command.jumped = 'b1;

            if (next_jump_command.actual_next_pc != cmd_in.next_pc) begin
                next_jump_command.update_pc = 'b1;
            end
        end
        endcase
    end

endmodule
