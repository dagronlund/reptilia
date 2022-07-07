//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import stream/stream_intf.sv
//!import stream/stream_stage.sv
//!import stream/stream_controller.sv
//!wrapper stream/stream_split_wrapper.sv

`include "std/std_util.svh"

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
    parameter int ID_WIDTH = (PORTS > 1) ? $clog2(PORTS) : 1,
    parameter int USE_LAST = 0
)(
    input wire clk, rst,

    stream_intf.in            stream_in,
    input wire [ID_WIDTH-1:0] stream_in_id,
    input wire                stream_in_last,

    stream_intf.out             stream_out [PORTS],
    output logic [ID_WIDTH-1:0] stream_out_id [PORTS],
    output logic                stream_out_last [PORTS]
);

    typedef bit [$bits(stream_in.T_LOGIC)-1:0] payload_width_temp_t;
    localparam int PAYLOAD_WIDTH = $bits(payload_width_temp_t);
    // localparam PAYLOAD_WIDTH = $bits(stream_in.payload);

    typedef logic [ID_WIDTH-1:0] index_t;
    typedef struct packed {
        logic [PAYLOAD_WIDTH-1:0] payload;
        logic                     last;
    } payload_last_t;

    logic [PORTS-1:0] stream_out_valid, stream_out_ready;

    // Copy interfaces into arrays
    generate
    genvar k;
    for (k = 0; k < PORTS; k++) begin

        `PROCEDURAL_ASSERT(PAYLOAD_WIDTH == $bits(stream_out[k].payload))

        stream_intf #(.T(payload_last_t)) stream_out_next (.clk, .rst);
        stream_intf #(.T(payload_last_t)) stream_out_temp (.clk, .rst);

        always_comb begin
            automatic payload_last_t stream_out_next_payload, stream_out_temp_payload;

            /* verilator lint_off WIDTH */
            stream_out_next.valid = stream_out_valid[k];
            stream_out_ready[k] = stream_out_next.ready;
            stream_out_next_payload = '{
                payload: stream_in.payload,
                last: stream_in_last
            };
            stream_out_next.payload = stream_out_next_payload;

            stream_out_temp_payload = stream_out_temp.payload;

            stream_out[k].valid = stream_out_temp.valid;
            stream_out_temp.ready = stream_out[k].ready;
            stream_out[k].payload = stream_out_temp_payload.payload;
            stream_out_last[k] = stream_out_temp_payload.last;
            /* verilator lint_on WIDTH */
        end

        stream_stage #(
            .CLOCK_INFO(CLOCK_INFO),
            .PIPELINE_MODE(PIPELINE_MODE),
            .T(payload_last_t)
        ) stream_stage_inst (
            .clk, .rst,

            .stream_in(stream_out_next),
            .stream_out(stream_out_temp)
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
        produce[(PORTS > 1) ? stream_in_id : 'b0] = 'b1;

        for (i = 0; i < PORTS; i++) begin
            stream_out_id[i] = index_t'(i);
        end
    end

endmodule
