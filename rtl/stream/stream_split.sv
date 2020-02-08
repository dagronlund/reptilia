//!import std/std_pkg
//!import std/stream_pkg
//!import stream/stream_intf
//!import stream/stream_stage

`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
`else
    `include "std_util.svh"
`endif

/*
A demultiplexer of sorts that merges multiple streams into a single stream, 
taking the stream id and using that to determine which output stream to send it
out to. The output stream id is simply a constant indicating what id was
assigned to that port.
*/
module stream_split 
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter stream_select_mode_t STREAM_SELECT_MODE = STREAM_SELECT_MODE_ROUND_ROBIN, // Unused
    parameter int PORTS = 2,
    parameter int ID_WIDTH = $clog2(PORTS)
)(
    input wire clk, rst,

    stream_intf.in          stream_in,
    input wire [ID_WIDTH-1:0]   stream_in_id,

    stream_intf.out         stream_out [PORTS],
    output logic [ID_WIDTH-1:0] stream_out_id [PORTS]
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

        stream_intf #(.T(payload_t)) stream_out_next (.clk, .rst);

        always_comb begin
            stream_out_next.valid = stream_out_valid[k];
            stream_out_next.payload = stream_in.payload;
            stream_out_ready[k] = stream_out_next.ready;
        end

        stream_stage #(
            .CLOCK_INFO(CLOCK_INFO),
            .PIPELINE_MODE(PIPELINE_MODE),
            .T(payload_t)
        ) stream_stage_inst (
            .clk, .rst,

            .stream_in(stream_out_next),
            .stream_out(stream_out[k])
        );
    end
    endgenerate

    logic enable;
    logic consume;
    logic [PORTS-1:0] produce;

    stream_controller #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(PORTS)
    ) stream_controller_inst (
        .clk, .rst,

        .valid_input(stream_in.valid),
        .ready_input(stream_in.ready),

        .valid_output(stream_out_valid),
        .ready_output(stream_out_ready),

        .consume, .produce, .enable
    );

    always_comb begin
        automatic int i;

        consume = 'b1;
        produce = 'b0;
        produce[stream_in_id] = 'b1;

        for (i = 0; i < PORTS; i++) begin
            stream_out_id[i] = i;
        end
    end

endmodule
