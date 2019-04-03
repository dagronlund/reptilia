`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"

module stream_merge #(
    parameter int PORTS = 2,
    parameter int ID_WIDTH = $clog2(PORTS)
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
    logic produce, enable_output;
    
    std_flow #(
        .NUM_INPUTS(PORTS),
        .NUM_OUTPUTS(1)
    ) std_flow_inst (
        .clk, .rst,

        .valid_input(stream_in_valid),
        .ready_input(stream_in_ready),

        .valid_output(stream_out.valid),
        .ready_output(stream_out.ready),

        .consume, .produce,
        .enable, .enable_output
    );

    payload_t stream_out_payload_next;
    index_t stream_out_id_next;
    index_t current_priority, next_priority;

    always_ff @(posedge clk) begin
        if(rst) begin
            current_priority <= 'b0;
        end else if (enable) begin
            current_priority <= next_priority;
        end

        if (enable_output) begin
            stream_out.payload <= stream_out_payload_next;
            stream_out_id <= stream_out_id_next;
        end
    end

    always_comb begin
        automatic index_t stream_in_index;
        automatic int incr;

        consume = 'b0;
        produce = 'b0;
        next_priority = current_priority;

        // Set default master payloads, better than just zeros
        stream_out_payload_next = stream_in_payload[0];
        stream_out_id_next = 'b0;

        // Go through input streams starting at current priority
        for (incr = 'b0; incr < PORTS; incr++) begin
            stream_in_index = get_next_priority(current_priority, incr);
            
            // Master has not been written to
            if (stream_in_valid[stream_in_index] && !produce) begin
                consume[stream_in_index] = 'b1;
                produce = 'b1;
                stream_out_payload_next = stream_in_payload[stream_in_index];
                next_priority = get_next_priority(stream_in_index, 'b1);
                stream_out_id_next = stream_in_index;
            end
        end
    end

endmodule
