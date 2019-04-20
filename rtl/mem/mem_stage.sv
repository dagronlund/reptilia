`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`else

`include "std_util.svh"
`include "std_mem.svh"

`endif

module mem_stage #(
    parameter int MODE = 0
)(
    input logic clk, rst,
    std_mem_intf.in mem_in,
    std_mem_intf.out mem_out
);

    `STATIC_ASSERT($bits(mem_in.addr) == $bits(mem_out.addr))
    `STATIC_ASSERT($bits(mem_in.data) == $bits(mem_out.data))
    `STATIC_ASSERT($bits(mem_in.id) == $bits(mem_out.id))

    localparam ADDR_WIDTH = $bits(mem_in.addr);
    localparam DATA_WIDTH = $bits(mem_in.data);
    localparam MASK_WIDTH = $bits(mem_in.write_enable);
    localparam ID_WIDTH = $bits(mem_in.id);

    typedef struct packed {
        logic read_enable;
        logic [MASK_WIDTH-1:0] write_enable;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [ID_WIDTH-1:0] id;
    } mem_t;

    std_stream_intf #(.T(mem_t)) stream_in (.clk, .rst);
    std_stream_intf #(.T(mem_t)) stream_out (.clk, .rst);

    std_flow_stage #(
        .T(mem_t),
        .MODE(MODE)
    ) std_flow_stage_inst (
        .clk, .rst,
        .stream_in, .stream_out
    );

    always_comb begin
        automatic mem_t payload = stream_out.payload;

        // Connect inputs
        stream_in.valid = mem_in.valid;
        stream_in.payload = '{
            read_enable: mem_in.read_enable,
            write_enable: mem_in.write_enable,
            addr: mem_in.addr,
            data: mem_in.data,
            id: mem_in.id
        };
        mem_in.ready = stream_in.ready;

        // Connect outputs
        mem_out.valid = stream_out.valid;
        mem_out.read_enable = payload.read_enable;
        mem_out.write_enable = payload.write_enable;
        mem_out.addr = payload.addr;
        mem_out.data = payload.data;
        mem_out.id = payload.id;
        stream_out.ready = mem_out.ready;
    end

endmodule
