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

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    std_stream_intf #(.T(basilisk_mult_command_t)) mult_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) mult_result_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_add_command_t)) mult_add_command (.clk, .rst);

    basilisk_mult #(
        .OUTPUT_REGISTER_MODE(1)
    ) basilisk_mult_inst (
        .clk, .rst,
        .mult_command, .mult_result_command, .mult_add_command
    );

    std_stream_intf #(.T(basilisk_add_command_t)) add_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) add_result_command (.clk, .rst);

    basilisk_add #(
        .OUTPUT_REGISTER_MODE(1)
    ) basilisk_add_inst (
            .clk, .rst,
            .add_command, .mult_add_command, .add_result_command
    );

    std_stream_intf #(.T(basilisk_sqrt_command_t)) sqrt_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) sqrt_result_command (.clk, .rst);

    basilisk_sqrt #(
        .OUTPUT_REGISTER_MODE(1)
    ) basilisk_sqrt_inst (
        .clk, .rst,
        .sqrt_command, .sqrt_result_command
    );

    std_stream_intf #(.T(basilisk_divide_command_t)) divide_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_result_t)) divide_result_command (.clk, .rst);

    basilisk_divide #(
        .OUTPUT_REGISTER_MODE(1)
    ) basilisk_divide_inst (
        .clk, .rst,
        .divide_command, .divide_result_command
    );

    fpu_float_fields_t input_fields [5];
    fpu_float_conditions_t input_conditions [5];


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
        sqrt_result_command.ready = 'b0;

        divide_command.valid = 'b0;
        divide_result_command.valid = 'b0;
        
        add_command.valid = 'b0;
        add_result_command.ready = 'b0;

        mult_command.valid = 'b0;
        mult_result_command.ready = 'b0;
        while (rst) @ (posedge clk);

        fork
        begin    
            sqrt_command.send('{
                dest_reg_addr: 'h5,
                a: input_fields[2],
                conditions_a: input_conditions[2],
                mode: FPU_ROUND_MODE_EVEN
            });
        end
        begin
            sqrt_result_command.recv(result);
            $display("Sqrt Result Dest: %h Value %f", result.dest_reg_addr, result_to_float(result));
        end
        begin
            divide_command.send('{
                dest_reg_addr: 'h6,
                a: input_fields[3],
                conditions_a: input_conditions[3],
                b: input_fields[2],
                conditions_b: input_conditions[2],
                mode: FPU_ROUND_MODE_EVEN
            });
        end
        begin
            divide_result_command.recv(result);
            $display("Divide Result Dest: %h Value %f", result.dest_reg_addr, result_to_float(result));
        end
        begin
            @ (posedge clk);
            @ (posedge clk);
            @ (posedge clk);
            @ (posedge clk);
            @ (posedge clk);
            add_command.send('{
                dest_reg_addr: 'h8,
                a: input_fields[4],
                conditions_a: input_conditions[4],
                b: input_fields[4],
                conditions_b: input_conditions[4],
                mode: FPU_ROUND_MODE_EVEN
            });
        end
        begin
            add_result_command.recv(result);
            $display("Add Result Dest: %h Value %f", result.dest_reg_addr, result_to_float(result));
            add_result_command.recv(result);
            $display("Macc Result Dest: %h Value %f", result.dest_reg_addr, result_to_float(result));
        end
        begin
            mult_command.send('{
                dest_reg_addr: 'h8,
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
                dest_reg_addr: 'h8,
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
            mult_result_command.recv(result);
            $display("Mult Result Dest: %h Value %f", result.dest_reg_addr, result_to_float(result));
        end

        join
    end

endmodule
