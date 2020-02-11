//!import std/std_pkg
//!import stream/stream_pkg
//!import stream/stream_stage

`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

module mem_stage 
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED
)(
    input logic clk, rst,
    mem_intf.in mem_in,
    mem_intf.out mem_out
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

    stream_intf #(.T(mem_t)) stream_in (.clk, .rst);
    stream_intf #(.T(mem_t)) stream_out (.clk, .rst);

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(mem_t)
    ) stream_stage_inst (
        .clk, .rst,
        .stream_in, .stream_out
    );

    always_comb begin
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
        mem_out.read_enable = stream_out.payload.read_enable;
        mem_out.write_enable = stream_out.payload.write_enable;
        mem_out.addr = stream_out.payload.addr;
        mem_out.data = stream_out.payload.data;
        mem_out.id = stream_out.payload.id;
        stream_out.ready = mem_out.ready;
    end

endmodule
