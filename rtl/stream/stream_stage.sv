//!import std/std_pkg.sv
//!import std/std_register.sv
//!import stream/stream_pkg.sv
//!import stream/stream_intf.sv
//!wrapper stream/stream_stage_wrapper.sv

`include "std/std_util.svh"

/*
Implements a valid/ready controlled pipeline stage

PIPELINE_MODE:
    STREAM_PIPELINE_MODE_TRANSPARENT
        No logic between input values and output
    STREAM_PIPELINE_MODE_REGISTERED
        A single register stage, ready logic is still combinational
    STREAM_PIPELINE_MODE_BUFFERED
        A double buffered register stage, ready logic is registered
    STREAM_PIPELINE_MODE_ELASTIC
        An insertable register stage, valid logic is combinational but ready is 
        registered using an insertable register stage
*/
module stream_stage
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter type T = logic
)(
    input wire clk, 
    input wire rst,

    stream_intf.in stream_in,
    stream_intf.out stream_out
);

    `STATIC_ASSERT($bits(T) == $bits(stream_in.payload))
    `STATIC_ASSERT($bits(T) == $bits(stream_out.payload))

    typedef bit [$bits(stream_out.T_LOGIC)-1:0] payload_width_temp_t;
    localparam int PAYLOAD_WIDTH = $bits(payload_width_temp_t);
    typedef logic [PAYLOAD_WIDTH-1:0] payload_t;

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
            .T(payload_t),
            .RESET_VECTOR('b0)
        ) payload_register_inst (
            .clk, .rst(std_get_reset(CLOCK_INFO, 0)),
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
            .T(payload_t),
            .RESET_VECTOR('b0)
        ) buffer0_register_inst (
            .clk, .rst(std_get_reset(CLOCK_INFO, 0)),
            .enable(buffer0_enable),
            .next(stream_in.payload),
            .value(buffer0)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(payload_t),
            .RESET_VECTOR('b0)
        ) buffer1_register_inst (
            .clk, .rst(std_get_reset(CLOCK_INFO, 0)),
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
            .T(payload_t),
            .RESET_VECTOR('b0)
        ) payload_register_inst (
            .clk, .rst(std_get_reset(CLOCK_INFO, 0)),
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