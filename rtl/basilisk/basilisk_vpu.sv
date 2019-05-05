`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/gecko/gecko.svh"
`include "../../lib/basilisk/basilisk.svh"
`include "../../lib/basilisk/basilisk_decode_util.svh"
`include "../../lib/fpu/fpu.svh"

`else

`include "std_util.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32i.svh"
`include "rv32f.svh"
`include "gecko.svh"
`include "basilisk.svh"
`include "basilisk_decode_util.svh"
`include "fpu.svh"

`endif

module basilisk_vpu
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import rv32f::*;
    import gecko::*;
    import basilisk::*;
    import basilisk_decode_util::*;
    import fpu::*;
#(
    parameter int MEMORY_LATENCY = 1
)(
    input logic clk, rst,

    std_stream_intf.in float_command, // gecko_float_operation_t
    std_stream_intf.out float_result, // gecko_operation_t

    std_mem_intf.out float_mem_request,
    std_mem_intf.in float_mem_result
);

    function automatic fpu_result_t bits_to_result(
        input rv32_reg_value_t value
    );
        return '{
            sign: value[31],
            exponent: value[30:23],
            mantissa: value[22:0],
            nan: 'b0,
            inf: 'b0,
            zero: 'b0,
            guard: 'b0,
            mode: FPU_ROUND_MODE_EVEN
        };
    endfunction

    std_stream_intf #(.T(basilisk_encode_command_t)) encode_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_convert_command_t)) convert_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_memory_command_t)) memory_command (.clk, .rst);

    std_stream_intf #(.T(basilisk_mult_command_t)) mult_command [BASILISK_COMPUTE_WIDTH] (.clk, .rst);
    std_stream_intf #(.T(basilisk_add_command_t)) add_command [BASILISK_COMPUTE_WIDTH] (.clk, .rst);
    std_stream_intf #(.T(basilisk_sqrt_command_t)) sqrt_command [BASILISK_COMPUTE_WIDTH] (.clk, .rst);
    std_stream_intf #(.T(basilisk_divide_command_t)) divide_command [BASILISK_COMPUTE_WIDTH] (.clk, .rst);

    std_stream_intf #(.T(basilisk_result_t)) memory_result (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) convert_result (.clk, .rst);

    std_stream_intf #(.T(basilisk_result_t)) partial_memory_result_in (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) partial_memory_result_out (.clk, .rst);

    std_stream_intf #(.T(basilisk_writeback_result_t)) writeback_result [BASILISK_COMPUTE_WIDTH] (.clk, .rst);

    basilisk_decode #(
        .OUTPUT_REGISTER_MODE(2)
    ) basilisk_decode_inst (
        .clk, .rst,
        .float_command, .encode_command,
        .mult_command, .add_command, .sqrt_command, .divide_command,
        .convert_command, .memory_command,
        .writeback_result
    );

    basilisk_convert #(
        .OUTPUT_REGISTER_MODE(1)
    ) basilisk_convert_inst (
        .clk, .rst,
        .convert_command, .convert_result
    );

    basilisk_memory #(
        .OUTPUT_REGISTER_MODE(1)
    ) basilisk_memory_inst (
        .clk, .rst,
        .memory_command,
        .memory_request(float_mem_request),
        .partial_memory_result(partial_memory_result_in)
    );

    std_stream_stage #(
        .T(basilisk_result_t),
        .LATENCY(MEMORY_LATENCY)
    ) float_mem_stage_inst (
        .clk, .rst,
        .data_in(partial_memory_result_in),
        .data_out(partial_memory_result_out)
    );

    always_comb begin
        automatic fpu_result_t memory_result_value = bits_to_result(float_mem_result.data);

        memory_result.valid = float_mem_result.valid && partial_memory_result_out.valid;
        memory_result.payload = '{
            dest_reg_addr: partial_memory_result_out.payload.dest_reg_addr,
            dest_offset_addr: partial_memory_result_out.payload.dest_offset_addr,
            result: memory_result_value
        };
        float_mem_result.ready = memory_result.ready;
        partial_memory_result_out.ready = memory_result.ready;
    end

    generate
    genvar k;
    for (k = 0; k < BASILISK_COMPUTE_WIDTH; k++) begin
        basilisk_math_unit #(
            .OUTPUT_REGISTER_MODE(1),
            .ENABLE_MEMORY_CONVERT((k == 0) ? 1 : 0)
        ) basilisk_math_unit_inst (
            .clk, .rst,
            .add_command(add_command[k]),
            .mult_command(mult_command[k]),
            .divide_command(divide_command[k]),
            .sqrt_command(sqrt_command[k]),
            
            .memory_result, .convert_result,
            .writeback_result(writeback_result[k])
        );
    end
    endgenerate

    basilisk_encode #() basilisk_encode_inst (
        .clk, .rst,
        .encode_command, .float_result
    );

endmodule
