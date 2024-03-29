//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import stream/stream_intf.sv
//!import stream/stream_controller.sv
//!import stream/stream_stage.sv
//!wrapper stream/stream_merge_wrapper.sv

`include "std/std_util.svh"

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
    parameter int ID_WIDTH = (PORTS > 1) ? $clog2(PORTS) : 1,
    parameter bit USE_LAST = 0
)(
    input wire clk, 
    input wire rst,

    stream_intf.in            stream_in [PORTS],
    input wire [ID_WIDTH-1:0] stream_in_id [PORTS],
    input wire                stream_in_last [PORTS],

    stream_intf.out             stream_out,
    output logic [ID_WIDTH-1:0] stream_out_id,
    output logic                stream_out_last
);

    typedef bit [$bits(stream_out.T_LOGIC)-1:0] payload_width_temp_t;
    localparam int PAYLOAD_WIDTH = $bits(payload_width_temp_t);
    // localparam PAYLOAD_WIDTH = $bits(stream_out.payload);

    typedef logic [PAYLOAD_WIDTH-1:0] payload_t;
    typedef logic [ID_WIDTH-1:0] index_t;

    typedef struct packed {
        payload_t payload;
        index_t id;
        logic last;
    } payload_id_last_t;

    function automatic index_t get_next_priority(
            input index_t current_priority,
            input index_t incr
    );
        index_t incr_priority = current_priority;
        for (index_t i = 0; i < incr; i++) begin
            incr_priority += 'b1;
            if (int'(incr_priority) >= PORTS) begin
                incr_priority = 'b0;
            end
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

    stream_intf #(.T(payload_id_last_t)) stream_out_next (.clk, .rst);
    stream_intf #(.T(payload_id_last_t)) stream_out_complete (.clk, .rst);

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
        .T(payload_id_last_t)
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

    logic next_last_flag, last_flag;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic),
        .RESET_VECTOR('b1)
    ) last_flag_register_inst (
        .clk, .rst,
        .enable(enable_priority),
        .next(next_last_flag),
        .value(last_flag)
    );

    always_comb begin
        automatic payload_id_last_t stream_out_next_payload, stream_out_complete_payload;
        automatic index_t stream_in_index;
        automatic int i;

        consume = 'b0;
        produce = 'b0;
        enable_priority = 'b0;
        next_priority = current_priority;

        // Set default master payloads, better than just zeros
        stream_out_next_payload = '{
            payload: stream_in_payload[0],
            last: stream_in_last[0],
            id: 'b0            
        };
        next_last_flag = stream_in_last[0];

        if (STREAM_SELECT_MODE == STREAM_SELECT_MODE_ROUND_ROBIN) begin
            if (USE_LAST && !last_flag) begin
                // If we are locked into a stream just stall waiting on it
                consume[current_priority] = 'b1;
                produce = 'b1;
                enable_priority = enable;
                // Only use next stream if that was the last beat
                next_priority = stream_in_last[current_priority] ? 
                    get_next_priority(current_priority, 'b1) : current_priority;

                stream_out_next_payload = '{
                    payload: stream_in_payload[current_priority],
                    last: stream_in_last[current_priority],
                    id: current_priority
                };

                next_last_flag = stream_in_last[current_priority];
            end else begin
                // Go through input streams starting at current priority
                for (i = 'b0; i < PORTS; i++) begin
                    stream_in_index = get_next_priority(current_priority, index_t'(i));
                    
                    // Stream is valid and we haven't produced anything yet
                    if (stream_in_valid[stream_in_index] && !produce) begin
                        consume[stream_in_index] = 'b1;
                        produce = 'b1;
                        enable_priority = enable;
                        // Only use next stream if that was the last beat
                        next_priority = (USE_LAST && !stream_in_last[stream_in_index]) ? 
                                stream_in_index : get_next_priority(stream_in_index, 'b1);

                        stream_out_next_payload = '{
                            payload: stream_in_payload[current_priority],
                            last: stream_in_last[current_priority],
                            id: stream_in_index
                        };

                        next_last_flag = stream_in_last[stream_in_index];
                    end
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

                    stream_out_next_payload = '{
                        payload: stream_in_payload[i],
                        last: stream_in_last[i],
                        id: current_priority
                    };
                end
            end

        end

        /* verilator lint_off WIDTH */
        stream_out_next.payload = stream_out_next_payload;

        // Connect stream_out_id to stream_out
        stream_out_complete_payload = stream_out_complete.payload;
        stream_out.valid = stream_out_complete.valid;
        stream_out.payload = stream_out_complete_payload.payload;
        stream_out_id = stream_out_complete_payload.id;
        stream_out_last = stream_out_complete_payload.last;
        stream_out_complete.ready = stream_out.ready;
        /* verilator lint_on WIDTH */
    end

endmodule
