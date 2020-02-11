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
A multiplexer of sorts that merges multiple streams into a single stream, using
one of two operating modes.

STREAM_SELECT_MODE_ROUND_ROBIN:
    Simply selects the stream that is ready first or if multiple streams are
    ready, the stream that was read from the longest ago. The output id is
    simply the index of the stream that was read from that cycle.

STREAM_SELECT_MODE_ORDERED:
    Selects the stream whose input id is one greater (modulo) than the last 
    input id that was read. The first input id that this logic expects is zero. 
    If no stream currently posesses the correct id then no stream will be read. 
    This requires that whatever issues the packets has some level of ordering, 
    usually the complementary stream_split stage. The output id will just be the 
    input id of the accepted stream, or a modulo PORTS incrementing value.
*/
module stream_merge 
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter stream_select_mode_t STREAM_SELECT_MODE = STREAM_SELECT_MODE_ROUND_ROBIN,
    parameter int PORTS = 2,
    parameter int ID_WIDTH = $clog2(PORTS)
)(
    input wire clk, 
    input wire rst,

    stream_intf.in              stream_in [PORTS],
    input wire [ID_WIDTH-1:0]   stream_in_id [PORTS],

    stream_intf.out             stream_out,
    output logic [ID_WIDTH-1:0] stream_out_id
);

    `STATIC_ASSERT(PORTS > 1)

    localparam PAYLOAD_WIDTH = $bits(stream_out.payload);

    typedef logic [PAYLOAD_WIDTH-1:0] payload_t;
    typedef logic [ID_WIDTH-1:0] index_t;

    typedef struct packed {
        payload_t payload;
        index_t id;
    } payload_id_t;

    function automatic index_t get_next_priority(
            input index_t current_priority,
            input index_t incr
    );
        index_t incr_priority = current_priority + incr;
        if (incr_priority >= PORTS) begin
            return 'b0;
        end
        return incr_priority;
    endfunction

    logic [PORTS-1:0] stream_in_valid, stream_in_ready;
    payload_t         stream_in_payload [PORTS];

    // Copy interfaces into arrays
    generate
    genvar k;
    for (k = 0; k < PORTS; k++) begin

        `PROCEDURAL_ASSERT(PAYLOAD_WIDTH == $bits(stream_in[k].payload))

        always_comb begin
            stream_in_valid[k] = stream_in[k].valid;
            stream_in_payload[k] = stream_in[k].payload;
            stream_in[k].ready = stream_in_ready[k];
        end
    end
    endgenerate

    logic enable;
    logic [PORTS-1:0] consume;
    logic produce;

    stream_intf #(.T(payload_id_t)) stream_out_next (.clk, .rst);
    stream_intf #(.T(payload_id_t)) stream_out_complete (.clk, .rst);

    stream_controller #(
        .NUM_INPUTS(PORTS),
        .NUM_OUTPUTS(1)
    ) stream_controller_inst (
        .clk, .rst,

        .valid_input(stream_in_valid),
        .ready_input(stream_in_ready),

        .valid_output({stream_out_next.valid}),
        .ready_output({stream_out_next.ready}),

        .consume, .produce, .enable
    );

    payload_t stream_out_payload_next;
    index_t stream_out_id_next;
    index_t current_priority, next_priority;

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(payload_id_t)
    ) stream_stage_inst (
        .clk, .rst,

        .stream_in(stream_out_next),
        .stream_out(stream_out_complete)
    );

    logic enable_priority;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(index_t),
        .RESET_VECTOR('b0)
    ) valid_register_inst (
        .clk, .rst,
        .enable(enable_priority),
        .next(next_priority),
        .value(current_priority)
    );

    always_comb begin
        automatic index_t stream_in_index;
        automatic int i;

        consume = 'b0;
        produce = 'b0;
        enable_priority = 'b0;
        next_priority = current_priority;

        // Set default master payloads, better than just zeros
        stream_out_next.payload.payload = stream_in_payload[0];
        stream_out_next.payload.id = 'b0;

        if (STREAM_SELECT_MODE == STREAM_SELECT_MODE_ROUND_ROBIN) begin

            // Go through input streams starting at current priority
            for (i = 'b0; i < PORTS; i++) begin
                stream_in_index = get_next_priority(current_priority, i);
                
                // Stream is valid and we haven't produced anything yet
                if (stream_in_valid[stream_in_index] && !produce) begin
                    consume[stream_in_index] = 'b1;
                    produce = 'b1;
                    enable_priority = enable;
                    next_priority = get_next_priority(stream_in_index, 'b1);

                    stream_out_next.payload.payload = stream_in_payload[stream_in_index];
                    stream_out_next.payload.id = stream_in_index;
                end
            end

        end else begin // STREAM_SELECT_MODE_ORDERED

            // Go through input streams looking for matching id
            for (i = 'b0; i < PORTS; i++) begin
                
                // ID matches and we haven't produced anything yet
                if ((stream_in_id[i] == current_priority) && !produce) begin
                    consume[i] = 'b1;
                    produce = 'b1;
                    enable_priority = enable;
                    next_priority = current_priority + 'b1;

                    stream_out_next.payload.payload = stream_in_payload[i];
                    stream_out_next.payload.id = current_priority;
                end
            end

        end

        // Connect stream_out_id to stream_out
        stream_out.valid = stream_out_complete.valid;
        stream_out.payload = stream_out_complete.payload.payload;
        stream_out_id = stream_out_complete.payload.id;
        stream_out_complete.ready = stream_out.ready;
    end

endmodule
