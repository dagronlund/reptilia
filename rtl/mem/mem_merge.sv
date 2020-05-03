`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "../mem/mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

module mem_merge 
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter stream_select_mode_t STREAM_SELECT_MODE = STREAM_SELECT_MODE_ROUND_ROBIN,
    parameter int PORTS = 2
)(
    input wire clk, rst,

    mem_intf.in mem_in [PORTS],
    mem_intf.out mem_out
);

    localparam ADDR_WIDTH = $bits(mem_out.addr);
    localparam DATA_WIDTH = $bits(mem_out.data);
    localparam MASK_WIDTH = $bits(mem_out.write_enable);

    localparam ID_WIDTH = $bits(mem_out.id);
    localparam SUB_ID_WIDTH = (PORTS > 1) ? $clog2(PORTS) : 1;
    localparam PRE_ID_WIDTH = $bits(mem_in[0].id);

    `STATIC_ASSERT((PORTS > 1) ? (ID_WIDTH == (PRE_ID_WIDTH + SUB_ID_WIDTH)) : (ID_WIDTH == PRE_ID_WIDTH))

    typedef struct packed {
        logic read_enable;
        logic [MASK_WIDTH-1:0] write_enable;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [PRE_ID_WIDTH-1:0] id;
    } mem_t;

    stream_intf #(.T(mem_t)) stream_in [PORTS] (.clk, .rst);

    logic [SUB_ID_WIDTH-1:0] stream_out_id;
    stream_intf #(.T(mem_t)) stream_out (.clk, .rst);

    generate
    genvar k;
    for (k = 0; k < PORTS; k++) begin

        `PROCEDURAL_ASSERT(ADDR_WIDTH == $bits(mem_in[k].addr))
        `PROCEDURAL_ASSERT(MASK_WIDTH == $bits(mem_in[k].write_enable))
        `PROCEDURAL_ASSERT(DATA_WIDTH == $bits(mem_in[k].data))
        `PROCEDURAL_ASSERT(PRE_ID_WIDTH == $bits(mem_in[k].id))

        always_comb begin
            automatic mem_t payload = '{
                read_enable: mem_in[k].read_enable,
                write_enable: mem_in[k].write_enable,
                addr: mem_in[k].addr,
                data: mem_in[k].data,
                id: mem_in[k].id
            };

            stream_in[k].valid = mem_in[k].valid;
            stream_in[k].payload = payload;
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
        mem_out.id = (PORTS > 1) ? {stream_out_id, payload.id} : payload.id;
    end

    stream_merge #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .STREAM_SELECT_MODE(STREAM_SELECT_MODE),
        .PORTS(PORTS),
        .ID_WIDTH(ID_WIDTH)
    ) stream_merge_inst (
        .clk, .rst,
        .stream_in, .stream_out, .stream_out_id
    );

endmodule
