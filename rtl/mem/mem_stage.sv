//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import stream/stream_stage.sv
//!import mem/mem_intf.sv
//!wrapper mem/mem_stage_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

module mem_stage 
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter int ADDR_WIDTH_OVERRIDE = 0, // Use these for overriding the interface widths
    parameter int DATA_WIDTH_OVERRIDE = 0,
    parameter int ID_WIDTH_OVERRIDE = 0,
    parameter int META_WIDTH = 1
)(
    input logic clk, rst,
    mem_intf.in                   mem_in,
    input logic [META_WIDTH-1:0]  mem_in_meta,
    mem_intf.out                  mem_out,
    output logic [META_WIDTH-1:0] mem_out_meta
);

    typedef bit [mem_in.ADDR_WIDTH-1:0] addr_width_temp_t;
    localparam int ADDR_WIDTH_INTERNAL = $bits(addr_width_temp_t);
    typedef bit [mem_in.DATA_WIDTH-1:0] data_width_temp_t;
    localparam int DATA_WIDTH_INTERNAL = $bits(data_width_temp_t);
    typedef bit [mem_in.MASK_WIDTH-1:0] mask_width_temp_t;
    localparam int MASK_WIDTH_INTERNAL = $bits(mask_width_temp_t);
    typedef bit [mem_in.ID_WIDTH-1:0] id_width_temp_t;
    localparam int ID_WIDTH_INTERNAL = $bits(id_width_temp_t);

    `STATIC_MATCH_MEM(mem_in, mem_out)

    localparam ADDR_WIDTH = (ADDR_WIDTH_OVERRIDE != 0) ? ADDR_WIDTH_OVERRIDE : ADDR_WIDTH_INTERNAL;
    localparam DATA_WIDTH = (DATA_WIDTH_OVERRIDE != 0) ? DATA_WIDTH_OVERRIDE : DATA_WIDTH_INTERNAL;
    localparam MASK_WIDTH = (ADDR_WIDTH_OVERRIDE != 0) ? (ADDR_WIDTH_OVERRIDE/8) : MASK_WIDTH_INTERNAL;
    localparam ID_WIDTH = (ID_WIDTH_OVERRIDE != 0) ? ID_WIDTH_OVERRIDE : ID_WIDTH_INTERNAL;

    typedef struct packed {
        logic read_enable;
        logic [MASK_WIDTH-1:0] write_enable;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [ID_WIDTH-1:0] id;
        logic last;
        logic [META_WIDTH-1:0] meta;
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
            id: mem_in.id,
            last: mem_in.last,
            meta: mem_in_meta
        };
        mem_in.ready = stream_in.ready;

        // Connect outputs
        mem_out.valid = stream_out.valid;
        mem_out.read_enable = stream_out.payload.read_enable;
        mem_out.write_enable = stream_out.payload.write_enable;
        mem_out.addr = stream_out.payload.addr;
        mem_out.data = stream_out.payload.data;
        mem_out.id = stream_out.payload.id;
        mem_out.last = stream_out.payload.last;
        mem_out_meta = stream_out.payload.meta;
        stream_out.ready = mem_out.ready;
    end

endmodule
