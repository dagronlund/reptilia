`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/gecko/gecko.svh"

`else

`include "std_util.svh"
`include "std_mem.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32i.svh"
`include "rv32f.svh"
`include "gecko.svh"

`endif

module gecko_float_dummy
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import rv32f::*;
    import gecko::*;
#()(
    input logic clk, rst,

    std_stream_intf.in float_command, // gecko_float_operation_t
    std_stream_intf.out float_result // gecko_operation_t
);

    logic consume, produce, enable;

    std_stream_intf #(.T(gecko_operation_t)) next_float_result (.clk, .rst);

    std_flow_lite #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({float_command.valid}),
        .ready_input({float_command.ready}),

        .valid_output({next_float_result.valid}),
        .ready_output({next_float_result.ready}),

        .consume, .produce, .enable
    );

    std_flow_stage #(
        .T(gecko_operation_t),
        .MODE(1)
    ) system_operation_output_stage (
        .clk, .rst,
        .stream_in(next_float_result), .stream_out(float_result)
    );

    always_comb begin
        consume = 'b1;
        produce = 'b0;

        case (rv32f_opcode_t'(float_command.payload.instruction_fields.opcode))
        RV32F_OPCODE_FP_OP_S: begin
            case (rv32f_funct7_t'(float_command.payload.instruction_fields.funct7))
            RV32F_FUNCT7_FCVT_W_S, RV32F_FUNCT7_FMV_X_W, RV32F_FUNCT7_FCMP_S: begin
                produce = 'b1;
            end
            endcase
        end
        endcase

        next_float_result.payload.addr = float_command.payload.dest_reg_addr;
        next_float_result.payload.reg_status = float_command.payload.dest_reg_status;
        next_float_result.payload.jump_flag = float_command.payload.jump_flag;
        next_float_result.payload.speculative = 'b0;

        next_float_result.payload.value = float_command.payload.rs1_value;
    end

endmodule
