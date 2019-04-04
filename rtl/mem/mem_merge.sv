`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

module mem_merge #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int MASK_WIDTH = DATA_WIDTH / 8,
    parameter int ID_WIDTH = 1,
    parameter int PORTS = 2
)(
    input logic clk, rst,

    std_mem_intf.in mem_in [PORTS],
    std_mem_intf.out mem_out
);

    `STATIC_ASSERT(PORTS > 1)
    `STATIC_ASSERT(ID_WIDTH >= $clog2(PORTS))

    `STATIC_ASSERT(ADDR_WIDTH == $bits(mem_out.addr))
    `STATIC_ASSERT(MASK_WIDTH == $bits(mem_out.write_enable))
    `STATIC_ASSERT(DATA_WIDTH == $bits(mem_out.data))
    `STATIC_ASSERT(ID_WIDTH == $bits(mem_out.id))

    typedef struct packed {
        logic read_enable;
        logic [MASK_WIDTH-1:0] write_enable;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [ID_WIDTH-1:0] id;
    } mem_t;

    std_stream_intf #(.T(mem_t)) stream_in [PORTS] (.clk, .rst);

    logic [ID_WIDTH-1:0] stream_out_id;
    std_stream_intf #(.T(mem_t)) stream_out (.clk, .rst);

    generate
    genvar k;
    for (k = 0; k < PORTS; k++) begin

        `PROCEDURAL_ASSERT(ADDR_WIDTH == $bits(mem_in[k].addr))
        `PROCEDURAL_ASSERT(MASK_WIDTH == $bits(mem_in[k].write_enable))
        `PROCEDURAL_ASSERT(DATA_WIDTH == $bits(mem_in[k].data))
        `PROCEDURAL_ASSERT(ID_WIDTH == $bits(mem_in[k].id))

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
    always_comb begin
        automatic mem_t payload = stream_out.payload;
        mem_out.valid = stream_out.valid;
        stream_out.ready = mem_out.ready;

        mem_out.read_enable = payload.read_enable;
        mem_out.write_enable = payload.write_enable;
        mem_out.addr = payload.addr;
        mem_out.data = payload.data;
        mem_out.id = stream_out_id;
    end
    endgenerate

    stream_merge #(
        .PORTS(PORTS),
        .ID_WIDTH(ID_WIDTH)
    ) stream_merge_inst (
        .clk, .rst,

        .stream_in, .stream_out,
        .stream_out_id
    );

endmodule
