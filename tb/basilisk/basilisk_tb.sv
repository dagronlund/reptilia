`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/fpu/fpu.svh"
`include "../../lib/fpu/fpu_operations.svh"
`include "../../lib/fpu/fpu_add.svh"
`include "../../lib/fpu/fpu_mult.svh"
`include "../../lib/fpu/fpu_divide.svh"
`include "../../lib/fpu/fpu_sqrt.svh"
`include "../../lib/basilisk/basilisk.svh"

module basilisk_tb
    import rv::*;
    import rv32::*;
    import rv32f::*;
    import fpu::*;
    import fpu_operations::*;
    import fpu_add::*;
    import fpu_mult::*;
    import fpu_divide::*;
    import fpu_sqrt::*;
    import basilisk::*;
#()();

    function automatic shortreal bitstoshortreal(
        input logic [31:0] bits
    );
        logic sign;
        logic [7:0] exp;
        logic [22:0] frac;
        shortreal sr;
        logic [23:0] xfrac;

        sign = bits[31];
        exp  = bits[30:23];
        frac = bits[22: 0];

        xfrac = {1'b1, frac};
        sr = 1.0 * xfrac;
        sr = sr / 8388608.0;
        if (exp >= 8'h7F) begin
            exp  = bits[30:23] - 8'h7F;
            sr = sr * (1 << exp);
        end else begin
            exp = 8'h7F - bits[30:23];
            sr = sr / (1 << exp);
        end

        return bits == 0 ? 0 : (sign ? -1.0 * sr : sr);
    endfunction

    function automatic logic [31:0] shortrealtobits(
        input shortreal r
    );
        logic sign;
        integer iexp;
        logic [7:0] exp;
        logic [22:0] frac;
        shortreal abs, ffrac;

        sign = r < 0.0 ? 1 : 0;
        abs = sign ? -1.0*r : r;
        iexp  = $floor($ln(abs) / $ln(2));
        ffrac = abs / $pow(2, iexp);
        ffrac = ffrac - 1.0;
        frac = ffrac * 8388608.0;
        exp = (r==0) ? 0 : 127 + iexp;

        return {sign, exp, frac};
    endfunction

    function automatic shortreal result_to_float(
        input basilisk_result_t result
    );
        fpu_float_fields_t f = fpu_operations_round(result.result);
        return bitstoshortreal({f.sign, f.exponent, f.mantissa});
    endfunction

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

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    std_stream_intf #(.T(basilisk_mult_command_t)) mult_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_add_command_t)) add_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_sqrt_command_t)) sqrt_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_divide_command_t)) divide_command (.clk, .rst);
    
    std_stream_intf #(.T(basilisk_convert_command_t)) convert_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_memory_command_t)) memory_command (.clk, .rst);

    std_stream_intf #(.T(basilisk_result_t)) memory_result (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) convert_result (.clk, .rst);

    std_mem_intf #(.ADDR_WIDTH(32)) memory_request (.clk, .rst);
    std_mem_intf #(.ADDR_WIDTH(32)) memory_request_out (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) partial_memory_result (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) pipelined_memory_result (.clk, .rst);

    std_stream_intf #(.T(basilisk_writeback_result_t)) writeback_result (.clk, .rst);

    basilisk_convert #(
        .OUTPUT_REGISTER_MODE(1)
    ) basilisk_convert_inst (
        .clk, .rst,
        .convert_command, .convert_result
        // std_stream_intf.in convert_command, // basilisk_convert_command_t
        // std_stream_intf.out convert_result // basilisk_result_t
    );

    basilisk_memory #(
        .OUTPUT_REGISTER_MODE(1)
    ) basilisk_memory_inst (
        .clk, .rst,
        .memory_command, .memory_request, .partial_memory_result
    );

    std_mem_single #(
        .MANUAL_ADDR_WIDTH(12),
        .ENABLE_OUTPUT_REG(1)
    ) std_mem_single_inst (
        .clk, .rst,
        .command(memory_request), .result(memory_request_out)
    );

    std_stream_stage #(
        .T(basilisk_result_t),
        .LATENCY(2)
    ) gecko_data_stage_inst (
        .clk, .rst,
        .data_in(partial_memory_result),
        .data_out(pipelined_memory_result)
    );

    // typedef struct packed {
    //     rv32_reg_addr_t dest_reg_addr;
    //     basilisk_offset_addr_t dest_offset_addr;
    //     rv32_reg_value_t result;
    // } basilisk_writeback_result_t;

    always_comb begin
        automatic fpu_result_t memory_result_value = bits_to_result(memory_request_out.data);

        memory_result.valid = memory_request_out.valid && pipelined_memory_result.valid;
        memory_result.payload = '{
            dest_reg_addr: pipelined_memory_result.payload.dest_reg_addr,
            dest_offset_addr: pipelined_memory_result.payload.dest_offset_addr,
            result: memory_result_value
        };
        memory_request_out.ready = memory_result.ready;
        pipelined_memory_result.ready = memory_result.ready;
    end

    basilisk_math_unit #(
        .OUTPUT_REGISTER_MODE(1),
        .ENABLE_MEMORY_CONVERT(1)
    ) basilisk_math_unit_inst (
        .clk, .rst,
        .add_command, .mult_command, .divide_command, .sqrt_command,

        .memory_result, .convert_result,
        .writeback_result
    );

    fpu_float_fields_t input_fields [5];
    fpu_float_conditions_t input_conditions [5];

    basilisk_writeback_result_t writeback_result_value;

    basilisk_result_t result;
    fpu_float_fields_t result_fields;
    logic [31:0] result_bits;
    shortreal result_float;
    rv32_reg_addr_t sqrt_dest;

    initial begin
        for (int i = 0; i < 5; i++) begin
            input_fields[i] = fpu_decode_float(shortrealtobits(shortreal'(i)));
            input_conditions[i] = fpu_get_conditions(input_fields[i]);
        end

        sqrt_command.valid = 'b0;
        divide_command.valid = 'b0;
        add_command.valid = 'b0;
        mult_command.valid = 'b0;
        writeback_result.ready = 'b0;

        convert_command.valid = 'b0;
        memory_command.valid = 'b0;
        while (rst) @ (posedge clk);

        fork
        begin    
            sqrt_command.send('{
                dest_reg_addr: 'h14,
                dest_offset_addr: 'h14,
                a: input_fields[2],
                conditions_a: input_conditions[2],
                mode: FPU_ROUND_MODE_EVEN
            });
        end
        begin
            divide_command.send('{
                dest_reg_addr: 'h15,
                dest_offset_addr: 'h15,
                a: input_fields[3],
                conditions_a: input_conditions[3],
                b: input_fields[2],
                conditions_b: input_conditions[2],
                mode: FPU_ROUND_MODE_EVEN
            });
        end
        begin
            @ (posedge clk);
            @ (posedge clk);
            @ (posedge clk);
            @ (posedge clk);
            @ (posedge clk);
            add_command.send('{
                dest_reg_addr: 'h8,
                dest_offset_addr: 'h8,
                a: input_fields[4],
                conditions_a: input_conditions[4],
                b: input_fields[4],
                conditions_b: input_conditions[4],
                mode: FPU_ROUND_MODE_EVEN
            });
        end
        begin
            mult_command.send('{
                dest_reg_addr: 'h16,
                dest_offset_addr: 'h16,
                enable_macc: 'b0,
                a: input_fields[4],
                conditions_a: input_conditions[4],
                b: input_fields[4],
                conditions_b: input_conditions[4],
                c: input_fields[1],
                conditions_c: input_conditions[1],
                mode: FPU_ROUND_MODE_EVEN
            });
            mult_command.send('{
                dest_reg_addr: 'h17,
                dest_offset_addr: 'h17,
                enable_macc: 'b1,
                a: input_fields[4],
                conditions_a: input_conditions[4],
                b: input_fields[4],
                conditions_b: input_conditions[4],
                c: input_fields[1],
                conditions_c: input_conditions[1],
                mode: FPU_ROUND_MODE_EVEN
            });
        end
        begin
            memory_command.send('{
                dest_reg_addr: 'b0,
                dest_offset_addr: 'b0,
                a: 'h7f80_0000,
                op: BASILISK_MEMORY_OP_STORE,
                mem_base_addr: 'h0,
                mem_offset_addr: 'h0
            });
            memory_command.send('{
                dest_reg_addr: 'b0,
                dest_offset_addr: 'b1,
                a: 'hffff_0000,
                op: BASILISK_MEMORY_OP_LOAD,
                mem_base_addr: 'h0,
                mem_offset_addr: 'h0
            });
        end
        begin
            convert_command.send('{
                dest_reg_addr: 'b1,
                dest_offset_addr: 'b1,
                a: input_fields[1],
                conditions_a: input_conditions[1],
                b: input_fields[2],
                conditions_b: input_conditions[2],
                op: BASILISK_CONVERT_OP_MAX,
                signed_integer: 'b0
            });
            convert_command.send('{
                dest_reg_addr: 'b1,
                dest_offset_addr: 'h2,
                a: input_fields[1],
                conditions_a: input_conditions[1],
                b: input_fields[2],
                conditions_b: input_conditions[2],
                op: BASILISK_CONVERT_OP_MIN,
                signed_integer: 'b0
            });
            convert_command.send('{
                dest_reg_addr: 'b1,
                dest_offset_addr: 'h3,
                a: 'd23,
                conditions_a: 'b0,
                b: input_fields[2],
                conditions_b: input_conditions[2],
                op: BASILISK_CONVERT_OP_CNV,
                signed_integer: 'b0
            });
            convert_command.send('{
                dest_reg_addr: 'b1,
                dest_offset_addr: 'h3,
                a: 'd1000000001,
                conditions_a: 'b0,
                b: input_fields[2],
                conditions_b: input_conditions[2],
                op: BASILISK_CONVERT_OP_CNV,
                signed_integer: 'b0
            });
        end
        begin

    //             typedef enum logic [1:0] {
    //     BASILISK_CONVERT_OP_MIN = 'b00,
    //     BASILISK_CONVERT_OP_MAX = 'b01,
    //     BASILISK_CONVERT_OP_RAW = 'b10,
    //     BASILISK_CONVERT_OP_CNV = 'b11
    // } basilisk_convert_op_t;

    // typedef struct packed {
    //     rv32_reg_addr_t dest_reg_addr;
    //     basilisk_offset_addr_t dest_offset_addr;
    //     rv32_reg_value_t a, b;
    //     fpu_float_conditions_t conditions_a, conditions_b;
    //     basilisk_convert_op_t op;
    //     logic signed_integer;
    // } basilisk_convert_command_t;

    // typedef enum logic {
    //     BASILISK_MEMORY_OP_LOAD = 'b0,
    //     BASILISK_MEMORY_OP_STORE = 'b1
    // } basilisk_memory_op_t;

    // typedef struct packed {
    //     rv32_reg_addr_t dest_reg_addr;
    //     basilisk_offset_addr_t dest_offset_addr;
    //     rv32_reg_value_t a;
    //     basilisk_memory_op_t op;
    //     rv32_reg_value_t rs1_value;
    //     rv32_reg_value_t immediate_value;
    // } basilisk_memory_command_t;

        end
        begin
            while ('b1) begin
                writeback_result.recv(writeback_result_value);
                $display("Result Dest: %h, Offset: %h, Value: %f, Raw: %h",
                        writeback_result_value.dest_reg_addr,
                        writeback_result_value.dest_offset_addr,
                        bitstoshortreal(writeback_result_value.result),
                        writeback_result_value.result);
            end
        end

        join
    end

endmodule
