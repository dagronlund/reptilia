`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"

`else

`include "std_util.svh"

`endif

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
        logic valid_buffer0, valid_buffer1;
        T payload_buffer0, payload_buffer1;
        // logic [1:0] valid_buffer;
        // T [1:0] payload_buffer;

        // Synchronously connect valid
        always_ff @(posedge clk) begin
            if (rst) begin
                input_index <= 'b0;
                output_index <= 'b0;
                // valid_buffer <= '{'b0, 'b0};
                valid_buffer0 <= 'b0;
                valid_buffer1 <= 'b0;
            end else begin
                if (!(input_index ? valid_buffer1 : valid_buffer0) && stream_in.valid) begin
                    if (input_index) begin
                        valid_buffer1 <= 'b1;
                    end else begin
                        valid_buffer0 <= 'b1;
                    end
                    // valid_buffer[input_index] <= 'b1;
                    input_index <= input_index + 'b1;
                end
                if ((output_index ? valid_buffer1 : valid_buffer0) && stream_out.ready) begin
                    if (output_index) begin
                        valid_buffer1 <= 'b0;
                    end else begin
                        valid_buffer0 <= 'b0;
                    end
                    // valid_buffer[output_index] <= 'b0;
                    output_index <= output_index + 'b1;
                end
            end

            if (!(input_index ? valid_buffer1 : valid_buffer0) && stream_in.valid) begin
                if (input_index) begin
                    payload_buffer1 <= stream_in.payload;
                end else begin
                    payload_buffer0 <= stream_in.payload;
                end
                // payload_buffer[input_index] <= stream_in.payload;
            end
        end

        // Combinationally connect ready
        always_comb begin
            if (output_index) begin
                stream_out.valid = valid_buffer1;
                stream_out.payload = payload_buffer1;
            end else begin
                stream_out.valid = valid_buffer0;
                stream_out.payload = payload_buffer0;
            end
            if (input_index) begin
                stream_in.ready = !valid_buffer1;
            end else begin
                stream_in.ready = !valid_buffer0;
            end
            // stream_out.valid = valid_buffer[output_index];
            // stream_out.payload = payload_buffer[output_index];
            // stream_in.ready = !valid_buffer[input_index];
        end        

    end
    endgenerate

endmodule