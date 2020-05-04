`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "../mem/mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

module mem_split
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter stream_select_mode_t STREAM_SELECT_MODE = STREAM_SELECT_MODE_ROUND_ROBIN,
    parameter int PORTS = 2,
    parameter int META_WIDTH = 1
)(
    input wire clk, rst,

    mem_intf.in                   mem_in,
    input wire [META_WIDTH-1:0]   mem_in_meta,
    mem_intf.out                  mem_out [PORTS],
    output logic [META_WIDTH-1:0] mem_out_meta [PORTS]
);

    localparam ADDR_WIDTH = $bits(mem_in.addr);
    localparam DATA_WIDTH = $bits(mem_in.data);
    localparam MASK_WIDTH = $bits(mem_in.write_enable);

    localparam ID_WIDTH = $bits(mem_in.id);
    localparam SUB_ID_WIDTH = (PORTS > 1) ? $clog2(PORTS) : 1;;
    localparam POST_ID_WIDTH = $bits(mem_out[0].id);

    `STATIC_ASSERT((PORTS > 1) ? (ID_WIDTH == (POST_ID_WIDTH + SUB_ID_WIDTH)) : (ID_WIDTH == POST_ID_WIDTH))

    typedef struct packed {
        logic read_enable;
        logic [MASK_WIDTH-1:0] write_enable;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [ID_WIDTH-1:0] id;
        logic [META_WIDTH-1:0] meta;
    } mem_t;

    logic [SUB_ID_WIDTH-1:0] stream_in_id;
    stream_intf #(.T(mem_t)) stream_in (.clk, .rst);

    stream_intf #(.T(mem_t)) stream_out [PORTS] (.clk, .rst);

    generate
    genvar k;
    for (k = 0; k < PORTS; k++) begin

        `PROCEDURAL_ASSERT(ADDR_WIDTH == $bits(mem_out[k].addr))
        `PROCEDURAL_ASSERT(MASK_WIDTH == $bits(mem_out[k].write_enable))
        `PROCEDURAL_ASSERT(DATA_WIDTH == $bits(mem_out[k].data))
        `PROCEDURAL_ASSERT(POST_ID_WIDTH == $bits(mem_out[k].id))

        always_comb begin
            automatic mem_t payload = stream_out[k].payload;

            mem_out[k].valid = stream_out[k].valid;
            mem_out[k].read_enable = payload.read_enable;
            mem_out[k].write_enable = payload.write_enable;
            mem_out[k].addr = payload.addr;
            mem_out[k].data = payload.data;
            mem_out[k].id = payload.id[POST_ID_WIDTH-1:0];
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

        stream_in_id = (PORTS > 1) ? mem_in.id[SUB_ID_WIDTH+POST_ID_WIDTH-1:POST_ID_WIDTH] : 'b0;
    end

    stream_split #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .STREAM_SELECT_MODE(STREAM_SELECT_MODE),
        .PORTS(PORTS),
        .ID_WIDTH(ID_WIDTH)
    ) stream_split_inst (
        .clk, .rst,
        .stream_in, .stream_in_id, .stream_out
    );

endmodule
