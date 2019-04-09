`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

module mem_split #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int MASK_WIDTH = DATA_WIDTH / 8,
    parameter int ID_WIDTH = 1,
    parameter int PORTS = 2,
    parameter int PIPELINE_MODE = 1
)(
    input logic clk, rst,

    std_mem_intf.in mem_in,
    std_mem_intf.out mem_out [PORTS]
);

    `STATIC_ASSERT(PORTS > 1)
    `STATIC_ASSERT(ID_WIDTH >= $clog2(PORTS))

    `STATIC_ASSERT(ADDR_WIDTH == $bits(mem_in.addr))
    `STATIC_ASSERT(MASK_WIDTH == $bits(mem_in.write_enable))
    `STATIC_ASSERT(DATA_WIDTH == $bits(mem_in.data))
    `STATIC_ASSERT(ID_WIDTH == $bits(mem_in.id))

    typedef struct packed {
        logic read_enable;
        logic [MASK_WIDTH-1:0] write_enable;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [ID_WIDTH-1:0] id;
    } mem_t;

    logic [ID_WIDTH-1:0] stream_in_id;
    std_stream_intf #(.T(mem_t)) stream_in (.clk, .rst);

    std_stream_intf #(.T(mem_t)) stream_out [PORTS] (.clk, .rst);

    generate
    genvar k;
    for (k = 0; k < PORTS; k++) begin

        `PROCEDURAL_ASSERT(ADDR_WIDTH == $bits(mem_out[k].addr))
        `PROCEDURAL_ASSERT(MASK_WIDTH == $bits(mem_out[k].write_enable))
        `PROCEDURAL_ASSERT(DATA_WIDTH == $bits(mem_out[k].data))
        `PROCEDURAL_ASSERT(ID_WIDTH == $bits(mem_out[k].id))

        always_comb begin
            automatic mem_t payload = stream_out[k].payload;

            mem_out[k].valid = stream_out[k].valid;
            mem_out[k].read_enable = payload.read_enable;
            mem_out[k].write_enable = payload.write_enable;
            mem_out[k].addr = payload.addr;
            mem_out[k].data = payload.data;
            mem_out[k].id = payload.id;
            stream_out[k].ready = mem_out[k].ready;
        end
    end
    always_comb begin
        stream_in.valid = mem_in.valid;
        stream_in.payload = '{
            read_enable: mem_in.read_enable,
            write_enable: mem_in.write_enable,
            addr: mem_in.addr,
            data: mem_in.data,
            id: mem_in.id
        };
        mem_in.ready = stream_in.ready;

        stream_in_id = mem_in.id;
    end
    endgenerate

    stream_split #(
        .PORTS(PORTS),
        .ID_WIDTH(ID_WIDTH),
        .PIPELINE_MODE(PIPELINE_MODE)
    ) stream_split_inst (
        .clk, .rst,

        .stream_in, .stream_out,
        .stream_in_id
    );

endmodule
