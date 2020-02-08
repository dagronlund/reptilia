//!import std/std_pkg
//!import std/std_register
//!import stream/stream_pkg

`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
`else
    `include "std_util.svh"
`endif

/*
 * Implements a valid/ready controlled pipeline stage
 *
 * MODE:
 *  0 - TRANSPARENT 
 *      No logic between input values and output
 *  1 - REGISTERED 
 *      A single register stage, ready logic is still combinational
 *  2 - BUFFERED
 *      A double buffered register stage, ready logic is registered
 *  3 - ELASTIC
 *      An insertable register stage, valid logic is combinational but ready is registered
 */
module stream_stage
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter type T = logic
)(
    input logic clk, rst,

    stream_intf.in stream_in,
    stream_intf.out stream_out
);

    `STATIC_ASSERT($bits(T) == $bits(stream_in.payload))
    `STATIC_ASSERT($bits(T) == $bits(stream_out.payload))
    // `STATIC_ASSERT(T == type(stream_in.payload))
    // `STATIC_ASSERT(T == type(stream_out.payload))

    generate
    if (PIPELINE_MODE == STREAM_PIPELINE_MODE_TRANSPARENT) begin

        // Combinationally connect everything
        always_comb begin
            stream_out.valid = stream_in.valid;
            stream_out.payload = stream_in.payload;
            stream_in.ready = stream_out.ready;
        end

    end else if (PIPELINE_MODE == STREAM_PIPELINE_MODE_REGISTERED) begin

        logic payload_enable, valid_enable;

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) valid_register_inst (
            .clk, .rst,
            .enable(valid_enable),
            .next(payload_enable),
            .value(stream_out.valid)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(T),
            .RESET_VECTOR('b0)
        ) payload_register_inst (
            .clk, .rst,
            .enable(payload_enable),
            .next(stream_in.payload),
            .value(stream_out.payload)
        );

        // Combinationally connect ready
        always_comb begin
            stream_in.ready = stream_out.ready || !stream_out.valid;
            payload_enable = stream_in.valid && stream_in.ready;
            valid_enable = payload_enable || stream_out.ready;
        end

    end else if (PIPELINE_MODE == STREAM_PIPELINE_MODE_BUFFERED) begin

        logic input_index_enable, output_index_enable;
        logic input_index, output_index;

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) input_index_register_inst (
            .clk, .rst,
            .enable(input_index_enable),
            .next(!input_index),
            .value(input_index)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) output_index_register_inst (
            .clk, .rst,
            .enable(output_index_enable),
            .next(!output_index),
            .value(output_index)
        );

        // logic input_index, output_index;
        logic valid0, valid1;
        logic next_valid0, next_valid1;
        logic enable_valid0, enable_valid1;

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) valid0_register_inst (
            .clk, .rst,
            .enable(enable_valid0),
            .next(next_valid0),
            .value(valid0)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) valid1_register_inst (
            .clk, .rst,
            .enable(enable_valid1),
            .next(next_valid1),
            .value(valid1)
        );

        logic buffer0_enable, buffer1_enable;
        T buffer0, buffer1;

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(T),
            .RESET_VECTOR('b0)
        ) buffer0_register_inst (
            .clk, .rst,
            .enable(buffer0_enable),
            .next(stream_in.payload),
            .value(buffer0)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(T),
            .RESET_VECTOR('b0)
        ) buffer1_register_inst (
            .clk, .rst,
            .enable(buffer1_enable),
            .next(stream_in.payload),
            .value(buffer1)
        );

        // Connect valid and ready through buffers
        always_comb begin
            stream_out.valid = output_index ? (valid1) : (valid0);
            stream_out.payload = output_index ? buffer1 : buffer0;
            stream_in.ready = input_index ? (!valid1) : (!valid0);
            
            input_index_enable = stream_in.valid && stream_in.ready;
            output_index_enable = stream_out.valid && stream_out.ready;

            buffer0_enable = input_index_enable && !input_index;
            buffer1_enable = input_index_enable && input_index;

            next_valid0 = input_index_enable && !input_index; 
            next_valid1 = input_index_enable && input_index;

            enable_valid0 = (input_index_enable && !input_index) || 
                    (output_index_enable && !output_index);
            enable_valid1 = (input_index_enable && input_index) || 
                    (output_index_enable && output_index);
        end

    end else if (PIPELINE_MODE == STREAM_PIPELINE_MODE_ELASTIC) begin

        logic payload_valid, payload_valid_next, payload_valid_enable;

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) ready_register_inst (
            .clk, .rst,
            .enable(payload_valid_enable),
            .next(payload_valid_next),
            .value(payload_valid)
        );

        logic payload_enable;
        T payload_buffer;

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(T),
            .RESET_VECTOR('b0)
        ) payload_register_inst (
            .clk, .rst,
            .enable(payload_enable),
            .next(stream_in.payload),
            .value(payload_buffer)
        );

        // Combinationally connect valid
        always_comb begin
            stream_in.ready = !payload_valid;
            stream_out.valid = stream_in.valid || payload_valid;

            payload_enable = stream_in.valid && !payload_valid && !stream_out.ready;
            payload_valid_next = payload_enable;
            payload_valid_enable = payload_enable || stream_out.ready;

            stream_out.payload = payload_valid ? payload_buffer : stream_in.payload;
        end

    end
    endgenerate

endmodule