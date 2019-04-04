`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

/*
 * Implements a variable length pipeline stage
 */
module std_mem_stage #(
    parameter int LATENCY = 1
)(
    input logic clk, rst,
    std_mem_intf.in data_in,
    std_mem_intf.out data_out
);

    `STATIC_ASSERT($bits(data_in.addr) == $bits(data_out.addr))
    `STATIC_ASSERT($bits(data_in.data) == $bits(data_out.data))
    `STATIC_ASSERT($bits(data_in.id) == $bits(data_out.id))

    localparam ADDR_WIDTH = $bits(data_in.addr);
    localparam DATA_WIDTH = $bits(data_in.data);
    localparam MASK_WIDTH = $bits(data_in.write_enable);
    localparam ID_WIDTH = $bits(data_in.id);

    typedef struct packed {
        logic read_enable;
        logic [MASK_WIDTH-1:0] write_enable;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [ID_WIDTH-1:0] id;
    } mem_t;

    std_stream_intf #(.T(mem_t)) stream_in (.clk, .rst);
    std_stream_intf #(.T(mem_t)) stream_out (.clk, .rst);

    std_stream_stage #(
        .LATENCY(LATENCY)
    ) stream_stage_inst (
        .clk, .rst,
        .data_in(stream_in), .data_out(stream_out)
    );

    always_comb begin
        automatic mem_t payload = stream_out.payload;

        // Connect inputs
        stream_in.valid = data_in.valid;
        stream_in.payload = '{
            read_enable: data_in.read_enable,
            write_enable: data_in.write_enable,
            addr: data_in.addr,
            data: data_in.data,
            id: data_in.id
        };
        data_in.ready = stream_in.ready;

        // Connect outputs
        data_out.valid = stream_out.valid;
        data_out.read_enable = payload.read_enable;
        data_out.write_enable = payload.write_enable;
        data_out.addr = payload.addr;
        data_out.data = payload.data;
        data_out.id = payload.id;
        stream_out.ready = data_out.ready;
    end

endmodule
