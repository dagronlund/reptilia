`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"

/*
 * Implements a flow controlled pipeline stage
 *
 * MODE:
 *  0 - TRANSPARENT 
 *      No logic between input values and output
 *  1 - REGISTERED 
 *      A single register stage, ready logic is still combinational
 *  2 - BUFFERED
 *      A flexible latency register stage, ready logic is registered
 */
module std_flow_stage #(
    parameter type T = logic,
    parameter int MODE = 0
)(
    input logic clk, rst,

    std_stream_intf.in stream_in,
    std_stream_intf.out stream_out
);

    `STATIC_ASSERT($bits(T) == $bits(stream_in.payload))
    `STATIC_ASSERT($bits(T) == $bits(stream_out.payload))

    generate
    if (MODE == 0) begin

        // Combinationally connect everything
        always_comb begin
            stream_out.valid = stream_in.valid;
            stream_out.payload = stream_in.payload;
            stream_in.ready = stream_out.ready;
        end

    end else if (MODE == 1) begin

        // Synchronously connect valid
        always_ff @(posedge clk) begin
            if(rst) begin
                stream_out.valid <= 'b0;
            end else if (stream_in.valid && stream_in.ready) begin
                stream_out.valid <= 'b1;
            end else if (stream_out.ready) begin
                stream_out.valid <= 'b0;
            end

            if (stream_in.valid && stream_in.ready) begin
                stream_out.payload <= stream_in.payload;
            end
        end

        // Combinationally connect ready
        always_comb begin
            stream_in.ready = stream_out.ready || !stream_out.valid;
        end

    end else begin // MODE == 2

        logic input_index, output_index;
        logic valid_buffer [2];
        T payload_buffer [2];

        // Synchronously connect valid
        always_ff @(posedge clk) begin
            if (rst) begin
                input_index <= 'b0;
                output_index <= 'b0;
                valid_buffer <= '{'b0, 'b0};
            end else begin
                if (!valid_buffer[input_index] && stream_in.valid) begin
                    valid_buffer[input_index] <= 'b1;
                    input_index <= !input_index;
                end
                if (valid_buffer[output_index] && stream_out.ready) begin
                    valid_buffer[output_index] <= 'b0;
                    output_index <= !output_index;
                end
            end

            if (!valid_buffer[input_index] && stream_in.valid) begin
                payload_buffer[input_index] <= stream_in.payload;
            end
        end

        // Combinationally connect ready
        always_comb begin
            stream_out.valid = valid_buffer[output_index];
            stream_out.payload = payload_buffer[output_index];
            stream_in.ready = !valid_buffer[input_index];
        end        

    end
    endgenerate

endmodule