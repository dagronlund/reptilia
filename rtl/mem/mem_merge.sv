//!import stream/stream_intf.sv
//!import stream/stream_merge.sv
//!import mem/mem_intf.sv
//!wrapper mem/mem_merge_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

module mem_merge 
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

    mem_intf.in                 mem_in [PORTS],
    input wire [META_WIDTH-1:0] mem_in_meta [PORTS],

    mem_intf.out                  mem_out,
    output logic [META_WIDTH-1:0] mem_out_meta
);

    typedef bit [mem_out.ADDR_WIDTH-1:0] addr_width_temp_t;
    localparam int ADDR_WIDTH = $bits(addr_width_temp_t);
    typedef bit [mem_out.DATA_WIDTH-1:0] data_width_temp_t;
    localparam int DATA_WIDTH = $bits(data_width_temp_t);
    typedef bit [mem_out.MASK_WIDTH-1:0] mask_width_temp_t;
    localparam int MASK_WIDTH = $bits(mask_width_temp_t);
    typedef bit [mem_out.ID_WIDTH-1:0] id_width_temp_t;
    localparam int ID_WIDTH = $bits(id_width_temp_t);
    // typedef bit [mem_in[0].ID_WIDTH-1:0] input_id_width_temp_t;
    // localparam int INPUT_ID_WIDTH = $bits(input_id_width_temp_t);

    // localparam ADDR_WIDTH = $bits(mem_out.addr);
    // localparam DATA_WIDTH = $bits(mem_out.data);
    // localparam MASK_WIDTH = $bits(mem_out.write_enable);
    // localparam ID_WIDTH = $bits(mem_out.id);
    // localparam PRE_ID_WIDTH = $bits(mem_in[0].id);

    localparam int INTERNAL_ID_WIDTH = (PORTS > 1) ? $clog2(PORTS) : 1;
    // TODO: Actually check in and out ID widths against PORT count
    localparam int INPUT_ID_WIDTH = (PORTS > 1) ? (ID_WIDTH - INTERNAL_ID_WIDTH) : ID_WIDTH;
    // `STATIC_ASSERT((PORTS > 1) ? (ID_WIDTH == (PRE_ID_WIDTH + SUB_ID_WIDTH)) : (ID_WIDTH == PRE_ID_WIDTH))

    typedef struct packed {
        logic read_enable;
        logic [MASK_WIDTH-1:0] write_enable;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [INPUT_ID_WIDTH-1:0] id;
        logic [META_WIDTH-1:0] meta;
    } mem_t;

    stream_intf #(.T(mem_t)) stream_in [PORTS] (.clk, .rst);
    logic stream_in_last [PORTS];

    logic [INTERNAL_ID_WIDTH-1:0] stream_out_id;
    stream_intf #(.T(mem_t)) stream_out (.clk, .rst);

    generate
    genvar k;
    for (k = 0; k < PORTS; k++) begin

        `PROCEDURAL_ASSERT(ADDR_WIDTH == $bits(mem_in[k].addr))
        `PROCEDURAL_ASSERT(MASK_WIDTH == $bits(mem_in[k].write_enable))
        `PROCEDURAL_ASSERT(DATA_WIDTH == $bits(mem_in[k].data))
        `PROCEDURAL_ASSERT(INPUT_ID_WIDTH == $bits(mem_in[k].id))

        always_comb begin
            automatic mem_t payload = '{
                read_enable: mem_in[k].read_enable,
                write_enable: mem_in[k].write_enable,
                addr: mem_in[k].addr,
                data: mem_in[k].data,
                id: mem_in[k].id,
                meta: mem_in_meta[k]
            };

            stream_in[k].valid = mem_in[k].valid;
            stream_in[k].payload = payload;
            stream_in_last[k] = mem_in[k].last;
            mem_in[k].ready = stream_in[k].ready;
        end
    end
    endgenerate

    always_comb begin
        automatic mem_t payload = stream_out.payload;
        mem_out.valid = stream_out.valid;
        stream_out.ready = mem_out.ready;

        mem_out.read_enable = payload.read_enable;
        mem_out.write_enable = payload.write_enable;
        mem_out.addr = payload.addr;
        mem_out.data = payload.data;
        // Insert generated ID in MSB
        mem_out.id = {stream_out_id, payload.id}[ID_WIDTH-1:0];
        mem_out_meta = payload.meta;
    end

    stream_merge #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .STREAM_SELECT_MODE(STREAM_SELECT_MODE),
        .PORTS(PORTS),
        .ID_WIDTH(INPUT_ID_WIDTH),
        .USE_LAST(USE_LAST)
    ) stream_merge_inst (
        .clk, 
        .rst,
        .stream_in, 
        .stream_in_last,
        .stream_in_id('{default: 'b0}),
        .stream_out, 
        .stream_out_id, 
        .stream_out_last(mem_out.last)
    );

endmodule
