`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/gecko/gecko.svh"
`include "../../lib/basilisk/basilisk.svh"
`include "../../lib/fpu/fpu.svh"

`else

`include "std_util.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32i.svh"
`include "rv32f.svh"
`include "gecko.svh"
`include "basilisk.svh"
`include "fpu.svh"

`endif

module basilisk_encode
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import rv32f::*;
    import gecko::*;
    import basilisk::*;
    import fpu::*;
#()(
    input logic clk, rst,

    std_stream_intf.in encode_command, // basilisk_encode_command_t
    std_stream_intf.out float_result // gecko_operation_t
);

    logic consume, produce, enable;

    std_stream_intf #(.T(gecko_operation_t)) next_float_result (.clk, .rst);

    std_flow_lite #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({encode_command.valid}),
        .ready_input({encode_command.ready}),

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
        automatic rv32_reg_value_t a, b;
        automatic logic a_lt_b, a_eq_b;

        consume = 'b1;
        produce = 'b1;

        a = {encode_command.payload.a.sign, encode_command.payload.a.exponent, encode_command.payload.a.mantissa};
        b = {encode_command.payload.b.sign, encode_command.payload.b.exponent, encode_command.payload.b.mantissa};

        a_lt_b = (a < b);
        a_eq_b = (a == b);

        next_float_result.payload.addr = encode_command.payload.dest_reg_addr;
        next_float_result.payload.reg_status = encode_command.payload.dest_reg_status;
        next_float_result.payload.jump_flag = encode_command.payload.jump_flag;
        next_float_result.payload.speculative = 'b0;

        // Default to raw encoding
        next_float_result.payload.value = a;

        case (encode_command.payload.op)
        BASILISK_ENCODE_OP_CONVERT: begin
            next_float_result.payload.value = fpu_float2int(encode_command.payload.a, encode_command.payload.signed_integer);
        end
        BASILISK_ENCODE_OP_EQUAL: begin
            next_float_result.payload.value = {31'b0, a_eq_b};
        end
        BASILISK_ENCODE_OP_LT: begin
            next_float_result.payload.value = {31'b0, a_lt_b};
        end
        BASILISK_ENCODE_OP_LE: begin
            next_float_result.payload.value = {31'b0, a_lt_b | a_eq_b};
        end
        BASILISK_ENCODE_OP_CLASS: begin
            next_float_result.payload.value = {22'b0, 
                    encode_command.payload.conditions_a.nan,
                    encode_command.payload.conditions_a.nan,
                    ~encode_command.payload.a.sign & encode_command.payload.conditions_a.inf,
                    ~encode_command.payload.a.sign & encode_command.payload.conditions_a.norm,
                    ~encode_command.payload.a.sign & ~encode_command.payload.conditions_a.norm,
                    ~encode_command.payload.a.sign & ~encode_command.payload.conditions_a.zero,
                    encode_command.payload.a.sign & ~encode_command.payload.conditions_a.zero,
                    encode_command.payload.a.sign & ~encode_command.payload.conditions_a.norm,
                    encode_command.payload.a.sign & encode_command.payload.conditions_a.norm,
                    encode_command.payload.a.sign & encode_command.payload.conditions_a.inf
            }; 
        end
        endcase
    end

endmodule
