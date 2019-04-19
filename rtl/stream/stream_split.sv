`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"

`else

`include "std_util.svh"

`endif

module stream_split #(
    parameter int PORTS = 2,
    parameter int ID_WIDTH = $clog2(PORTS),
    parameter int PIPELINE_MODE = 1
)(
    input logic clk, rst,

    std_stream_intf.in stream_in,
    input logic [ID_WIDTH-1:0] stream_in_id,
    std_stream_intf.out stream_out [PORTS]
);

    `STATIC_ASSERT(PORTS > 1)

    localparam PAYLOAD_WIDTH = $bits(stream_in.payload);
    typedef logic [PAYLOAD_WIDTH-1:0] payload_t;

    typedef logic [ID_WIDTH-1:0] index_t;

    logic [PORTS-1:0] stream_out_valid, stream_out_ready;
    payload_t         stream_out_payload [PORTS];

    // Copy interfaces into arrays
    generate
    genvar k;
    for (k = 0; k < PORTS; k++) begin

        `PROCEDURAL_ASSERT(PAYLOAD_WIDTH == $bits(stream_out[k].payload))

        std_stream_intf #(.T(payload_t)) stream_mid (.clk, .rst);

        always_comb begin
            stream_mid.valid = stream_out_valid[k];
            stream_mid.payload = stream_in.payload;
            stream_out_ready[k] = stream_mid.ready;
        end

        std_flow_stage #(
            .T(payload_t),
            .MODE(PIPELINE_MODE)
        ) std_flow_output_inst (
            .clk, .rst,

            .stream_in(stream_mid),
            .stream_out(stream_out[k])
        );
    end
    endgenerate

    logic enable;
    logic consume;
    logic [PORTS-1:0] produce;

    std_flow_lite #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(PORTS)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input(stream_in.valid),
        .ready_input(stream_in.ready),

        .valid_output(stream_out_valid),
        .ready_output(stream_out_ready),

        .consume, .produce, .enable
    );

    always_comb begin
        consume = 'b1;
        produce = 'b0;
        produce[stream_in_id] = 'b1;        
    end

endmodule
