`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"

`else

`include "std_util.svh"

`endif

module stream_merge #(
    parameter int PORTS = 2,
    parameter int ID_WIDTH = $clog2(PORTS),
    parameter int PIPELINE_MODE = 1
)(
    input logic clk, rst,

    std_stream_intf.in stream_in [PORTS],
    std_stream_intf.out stream_out,
    output logic [ID_WIDTH-1:0] stream_out_id
);

    `STATIC_ASSERT(PORTS > 1)

    localparam PAYLOAD_WIDTH = $bits(stream_out.payload);
    typedef logic [PAYLOAD_WIDTH-1:0] payload_t;

    typedef logic [ID_WIDTH-1:0] index_t;

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

    typedef struct packed {
        payload_t payload;
        index_t id;
    } payload_id_t;

    std_stream_intf #(.T(payload_id_t)) stream_mid (.clk, .rst);
    std_stream_intf #(.T(payload_id_t)) stream_out_packed (.clk, .rst);

    std_flow_lite #(
        .NUM_INPUTS(PORTS),
        .NUM_OUTPUTS(1)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input(stream_in_valid),
        .ready_input(stream_in_ready),

        .valid_output({stream_mid.valid}),
        .ready_output({stream_mid.ready}),

        .consume, .produce, .enable
    );

    payload_t stream_out_payload_next;
    index_t stream_out_id_next;
    index_t current_priority, next_priority;

    std_flow_stage #(
        .T(payload_id_t),
        .MODE(PIPELINE_MODE)
    ) std_flow_output_inst (
        .clk, .rst,

        .stream_in(stream_mid),
        .stream_out(stream_out_packed)
    );

    always_ff @(posedge clk) begin
        if(rst) begin
            current_priority <= 'b0;
        end else if (enable) begin
            current_priority <= next_priority;
        end
    end

    always_comb begin
        automatic payload_id_t next_output;
        automatic index_t stream_in_index;
        automatic int incr;

        consume = 'b0;
        produce = 'b0;
        next_priority = current_priority;

        // Set default master payloads, better than just zeros
        next_output.payload = stream_in_payload[0];
        next_output.id = 'b0;

        // Go through input streams starting at current priority
        for (incr = 'b0; incr < PORTS; incr++) begin
            stream_in_index = get_next_priority(current_priority, incr);
            
            // Master has not been written to
            if (stream_in_valid[stream_in_index] && !produce) begin
                consume[stream_in_index] = 'b1;
                produce = 'b1;
                next_output.payload = stream_in_payload[stream_in_index];
                next_priority = get_next_priority(stream_in_index, 'b1);
                next_output.id = stream_in_index;
            end
        end

        stream_mid.payload = next_output;

        // Connect stream_out_id to stream_out
        stream_out.valid = stream_out_packed.valid;
        stream_out.payload = stream_out_packed.payload.payload;
        stream_out_id = stream_out_packed.payload.id;
        stream_out_packed.ready = stream_out.ready;
    end

endmodule
