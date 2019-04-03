`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"

module stream_split #(
    parameter int PORTS = 2,
    parameter int ID_WIDTH = $clog2(PORTS)
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

        always_comb begin
            stream_out[k].valid = stream_out_valid[k];
            stream_out[k].payload = stream_out_payload[k];
            stream_out_ready[k] = stream_out[k].ready;
        end
    end
    endgenerate

    logic enable;
    logic consume;
    logic [PORTS-1:0] produce, enable_output;
    
    std_flow #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(PORTS)
    ) std_flow_inst (
        .clk, .rst,

        .valid_input(stream_in.valid),
        .ready_input(stream_in.ready),

        .valid_output(stream_out_valid),
        .ready_output(stream_out_ready),

        .consume, .produce,
        .enable, .enable_output
    );

    always_ff @(posedge clk) begin
        for (int i = 0; i < PORTS; i++) begin
            if (enable_output[i]) begin
                stream_out_payload[i] <= stream_in.payload;
            end
        end
    end

    always_comb begin
        consume = 'b1;
        produce = 'b0;
        produce[stream_in_id] = 'b1;        
    end

endmodule
