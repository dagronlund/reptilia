//!import stream/stream_intf.sv
//!import stream/stream_split.sv
//!import mem/mem_intf.sv
//!wrapper mem/mem_split_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

module mem_split
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter stream_select_mode_t STREAM_SELECT_MODE = STREAM_SELECT_MODE_ROUND_ROBIN,
    parameter int PORTS = 2,
    parameter int META_WIDTH = 1,
    parameter bit USE_LAST = 0
)(
    input wire clk, rst,

    mem_intf.in                 mem_in,
    input wire [META_WIDTH-1:0] mem_in_meta,

    mem_intf.out                  mem_out [PORTS],
    output logic [META_WIDTH-1:0] mem_out_meta [PORTS]
);

    typedef bit [mem_in.ADDR_WIDTH-1:0] addr_width_temp_t;
    localparam int ADDR_WIDTH = $bits(addr_width_temp_t);
    typedef bit [mem_in.DATA_WIDTH-1:0] data_width_temp_t;
    localparam int DATA_WIDTH = $bits(data_width_temp_t);
    typedef bit [mem_in.MASK_WIDTH-1:0] mask_width_temp_t;
    localparam int MASK_WIDTH = $bits(mask_width_temp_t);
    typedef bit [mem_in.ID_WIDTH-1:0] id_width_temp_t;
    localparam int ID_WIDTH = $bits(id_width_temp_t);
    // typedef bit [mem_out[0].ID_WIDTH-1:0] OUTPUT_ID_WIDTH_temp_t;
    // localparam int OUTPUT_ID_WIDTH = $bits(OUTPUT_ID_WIDTH_temp_t);

    // localparam ADDR_WIDTH = $bits(mem_in.addr);
    // localparam DATA_WIDTH = $bits(mem_in.data);
    // localparam MASK_WIDTH = $bits(mem_in.write_enable);
    // localparam ID_WIDTH = $bits(mem_in.id);
    // localparam OUTPUT_ID_WIDTH = $bits(mem_out[0].id);
    localparam int INTERNAL_ID_WIDTH = (PORTS > 1) ? $clog2(PORTS) : 1;
    // TODO: Actually check in and out ID widths against PORT count
    localparam int OUTPUT_ID_WIDTH = (PORTS > 1) ? (ID_WIDTH - INTERNAL_ID_WIDTH) : ID_WIDTH; // ID_WIDTH - INTERNAL_ID_WIDTH;
    // `STATIC_ASSERT((PORTS > 1) ? (ID_WIDTH == (OUTPUT_ID_WIDTH + INTERNAL_ID_WIDTH)) : (ID_WIDTH == OUTPUT_ID_WIDTH))

    typedef struct packed {
        logic read_enable;
        logic [MASK_WIDTH-1:0] write_enable;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [ID_WIDTH-1:0] id;
        logic [META_WIDTH-1:0] meta;
    } mem_t;

    logic [INTERNAL_ID_WIDTH-1:0] stream_in_id;
    stream_intf #(.T(mem_t)) stream_in (.clk, .rst);

    stream_intf #(.T(mem_t)) stream_out [PORTS] (.clk, .rst);
    logic stream_out_last [PORTS];

    generate
    genvar k;
    for (k = 0; k < PORTS; k++) begin

        `PROCEDURAL_ASSERT(ADDR_WIDTH == $bits(mem_out[k].addr))
        `PROCEDURAL_ASSERT(MASK_WIDTH == $bits(mem_out[k].write_enable))
        `PROCEDURAL_ASSERT(DATA_WIDTH == $bits(mem_out[k].data))
        `PROCEDURAL_ASSERT(OUTPUT_ID_WIDTH == $bits(mem_out[k].id))

        always_comb begin
            automatic mem_t payload = stream_out[k].payload;

            mem_out[k].valid = stream_out[k].valid;
            mem_out[k].read_enable = payload.read_enable;
            mem_out[k].write_enable = payload.write_enable;
            mem_out[k].addr = payload.addr;
            mem_out[k].data = payload.data;
            mem_out[k].id = payload.id[OUTPUT_ID_WIDTH-1:0];
            mem_out[k].last = stream_out_last[k];
            mem_out_meta[k] = payload.meta;
            stream_out[k].ready = mem_out[k].ready;
        end
    end
    endgenerate

    always_comb begin
        stream_in.valid = mem_in.valid;
        stream_in.payload = '{
            read_enable: mem_in.read_enable,
            write_enable: mem_in.write_enable,
            addr: mem_in.addr,
            data: mem_in.data,
            id: mem_in.id,
            meta: mem_in_meta
        };
        mem_in.ready = stream_in.ready;

        stream_in_id = mem_in.id[ID_WIDTH-1:OUTPUT_ID_WIDTH];
    end

    stream_split #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .STREAM_SELECT_MODE(STREAM_SELECT_MODE),
        .PORTS(PORTS),
        .ID_WIDTH(OUTPUT_ID_WIDTH)
    ) stream_split_inst (
        .clk, 
        .rst,
        .stream_in, 
        .stream_in_id, 
        .stream_in_last(mem_in.last),
        .stream_out,
        .stream_out_id(), 
        .stream_out_last
    );

endmodule
