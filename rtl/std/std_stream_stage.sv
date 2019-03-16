`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

/*
 * Implements a variable length pipeline stage
 */
module std_stream_stage #(
    parameter int LATENCY = 1
)(
    input logic clk, rst,
    std_stream_intf.in data_in,
    std_stream_intf.out data_out
);

    `STATIC_ASSERT($size(data_in.payload) == $size(data_out.payload))
    localparam WIDTH = $bits(data_in.payload);
    typedef logic [WIDTH-1:0] data_t;

    logic data_in_valid [LATENCY];
    logic data_in_ready [LATENCY];
    data_t data_in_payload [LATENCY];

    logic data_out_valid [LATENCY];
    logic data_out_ready [LATENCY];
    data_t data_out_payload [LATENCY];

    genvar k;
    generate
    for (k = 0; k < LATENCY; k++) begin

        if (k == 0) begin
            assign data_in_valid[k] = data_in.valid;
            assign data_in.ready = data_in_ready[k];
            assign data_in_payload[k] = data_in.payload;
        end else begin
            assign data_in_valid[k] = data_out_valid[k-1];
            assign data_out_ready[k-1] = data_in_ready[k];
            assign data_in_payload[k] = data_out_payload[k-1];
        end

        if (k == LATENCY - 1) begin
            assign data_out.valid = data_out_valid[k];
            assign data_out_ready[k] = data_out.ready;
            assign data_out.payload = data_out_payload[k];
        end

        logic enable, enable_output_null;

        // Flow Controller
        std_flow #(
            .NUM_INPUTS(1),
            .NUM_OUTPUTS(1)
        ) std_flow_inst (
            .clk, .rst,

            .valid_input({data_in_valid[k]}),
            .ready_input({data_in_ready[k]}),
            
            .valid_output({data_out_valid[k]}),
            .ready_output({data_out_ready[k]}),

            .consume({1'b1}), .produce({1'b1}), .enable,
            .enable_output(enable_output_null)
        );

        always_ff @(posedge clk) begin
            if (enable) begin
                data_out_payload <= data_in_payload; 
            end
        end

    end
    endgenerate

endmodule
