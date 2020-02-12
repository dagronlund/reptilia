//!import std/std_pkg
//!import stream/stream_pkg
//!import stream/stream_stage
//!import axi/axi4_pkg

`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
`else
    `include "std_util.svh"
`endif

module axi4_ar_stage 
    import std_pkg::*;
    import stream_pkg::*;
    import axi4_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED
)(
    input logic clk, rst,
    axi4_ar_intf.in axi_ar_in,
    axi4_ar_intf.out axi_ar_out
);

    `STATIC_ASSERT($bits(axi_ar_in.addr) == $bits(axi_ar_out.addr))
    `STATIC_ASSERT($bits(axi_ar_in.user) == $bits(axi_ar_out.user))
    `STATIC_ASSERT($bits(axi_ar_in.id) == $bits(axi_ar_out.id))

    localparam ADDR_WIDTH = $bits(axi_ar_in.addr);
    localparam USER_WIDTH = $bits(axi_ar_in.user);
    localparam ID_WIDTH = $bits(axi_ar_in.id);

    typedef struct packed {
        logic [ADDR_WIDTH-1:0] addr;
        axi4_burst_t           burst;
        axi4_cache_t           cache;
        axi4_len_t             len;
        axi4_lock_t            lock;
        axi4_prot_t            prot;
        axi4_qos_t             qos;
        axi4_size_t            size;
        logic [USER_WIDTH-1:0] user;
        logic [ID_WIDTH-1:0]   id;
    } axi_ar_t;

    stream_intf #(.T(axi_ar_t)) stream_in (.clk, .rst);
    stream_intf #(.T(axi_ar_t)) stream_out (.clk, .rst);

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(axi_ar_t)
    ) stream_stage_inst (
        .clk, .rst,
        .stream_in, .stream_out
    );

    always_comb begin
        // Connect inputs
        stream_in.valid = axi_ar_in.valid;
        axi_ar_in.ready = stream_in.ready;
        stream_in.payload = '{
            addr: axi_ar_in.addr,
            burst: axi_ar_in.burst,
            cache: axi_ar_in.cache,
            len: axi_ar_in.len,
            lock: axi_ar_in.lock,
            prot: axi_ar_in.prot,
            qos: axi_ar_in.qos,
            size: axi_ar_in.size,
            user: axi_ar_in.user,
            id: axi_ar_in.id
        };
        
        // Connect outputs
        axi_ar_out.valid = stream_out.valid;
        stream_out.ready = axi_ar_out.ready;
        axi_ar_out.addr = stream_out.payload.addr;
        axi_ar_out.burst = stream_out.payload.burst;
        axi_ar_out.cache = stream_out.payload.cache;
        axi_ar_out.len = stream_out.payload.len;
        axi_ar_out.lock = stream_out.payload.lock;
        axi_ar_out.prot = stream_out.payload.prot;
        axi_ar_out.qos = stream_out.payload.qos;
        axi_ar_out.size = stream_out.payload.size;
        axi_ar_out.user = stream_out.payload.user;
        axi_ar_out.id = stream_out.payload.id;
    end

endmodule

module axi4_aw_stage 
    import std_pkg::*;
    import stream_pkg::*;
    import axi4_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED
)(
    input logic clk, rst,
    axi4_aw_intf.in axi_aw_in,
    axi4_aw_intf.out axi_aw_out
);

    `STATIC_ASSERT($bits(axi_aw_in.addr) == $bits(axi_aw_out.addr))
    `STATIC_ASSERT($bits(axi_aw_in.user) == $bits(axi_aw_out.user))
    `STATIC_ASSERT($bits(axi_aw_in.id) == $bits(axi_aw_out.id))

    localparam ADDR_WIDTH = $bits(axi_aw_in.addr);
    localparam USER_WIDTH = $bits(axi_aw_in.user);
    localparam ID_WIDTH = $bits(axi_aw_in.id);

    typedef struct packed {
        logic [ADDR_WIDTH-1:0] addr;
        axi4_burst_t           burst;
        axi4_cache_t           cache;
        axi4_len_t             len;
        axi4_lock_t            lock;
        axi4_prot_t            prot;
        axi4_qos_t             qos;
        axi4_size_t            size;
        logic [USER_WIDTH-1:0] user;
        logic [ID_WIDTH-1:0]   id;
    } axi_aw_t;

    stream_intf #(.T(axi_aw_t)) stream_in (.clk, .rst);
    stream_intf #(.T(axi_aw_t)) stream_out (.clk, .rst);

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(axi_aw_t)
    ) stream_stage_inst (
        .clk, .rst,
        .stream_in, .stream_out
    );

    always_comb begin
        // Connect inputs
        stream_in.valid = axi_aw_in.valid;
        axi_aw_in.ready = stream_in.ready;
        stream_in.payload = '{
            addr: axi_aw_in.addr,
            burst: axi_aw_in.burst,
            cache: axi_aw_in.cache,
            len: axi_aw_in.len,
            lock: axi_aw_in.lock,
            prot: axi_aw_in.prot,
            qos: axi_aw_in.qos,
            size: axi_aw_in.size,
            user: axi_aw_in.user,
            id: axi_aw_in.id
        };
        
        // Connect outputs
        axi_aw_out.valid = stream_out.valid;
        stream_out.ready = axi_aw_out.ready;
        axi_aw_out.addr = stream_out.payload.addr;
        axi_aw_out.burst = stream_out.payload.burst;
        axi_aw_out.cache = stream_out.payload.cache;
        axi_aw_out.len = stream_out.payload.len;
        axi_aw_out.lock = stream_out.payload.lock;
        axi_aw_out.prot = stream_out.payload.prot;
        axi_aw_out.qos = stream_out.payload.qos;
        axi_aw_out.size = stream_out.payload.size;
        axi_aw_out.user = stream_out.payload.user;
        axi_aw_out.id = stream_out.payload.id;
    end

endmodule

module axi4_w_stage 
    import std_pkg::*;
    import stream_pkg::*;
    import axi4_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED
)(
    input logic clk, rst,
    axi4_w_intf.in axi_w_in,
    axi4_w_intf.out axi_w_out
);

    `STATIC_ASSERT($bits(axi_w_in.data) == $bits(axi_w_out.data))
    `STATIC_ASSERT($bits(axi_w_in.strb) == $bits(axi_w_out.strb))

    localparam DATA_WIDTH = $bits(axi_w_in.data);
    localparam STROBE_WIDTH = $bits(axi_w_in.strb);

    typedef struct packed {
        logic [DATA_WIDTH-1:0]   data;
        logic [STROBE_WIDTH-1:0] strb;
        logic                    last;
    } axi_w_t;

    stream_intf #(.T(axi_w_t)) stream_in (.clk, .rst);
    stream_intf #(.T(axi_w_t)) stream_out (.clk, .rst);

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(axi_w_t)
    ) stream_stage_inst (
        .clk, .rst,
        .stream_in, .stream_out
    );

    always_comb begin
        // Connect inputs
        stream_in.valid = axi_w_in.valid;
        axi_w_in.ready = stream_in.ready;
        stream_in.payload = '{
            data: axi_w_in.data,
            strb: axi_w_in.strb,
            last: axi_w_in.last
        };
        
        // Connect outputs
        axi_w_out.valid = stream_out.valid;
        stream_out.ready = axi_w_out.ready;
        axi_w_out.data = stream_out.payload.data;
        axi_w_out.strb = stream_out.payload.strb;
        axi_w_out.last = stream_out.payload.last;
    end

endmodule

module axi4_r_stage 
    import std_pkg::*;
    import stream_pkg::*;
    import axi4_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED
)(
    input logic clk, rst,
    axi4_r_intf.in axi_r_in,
    axi4_r_intf.out axi_r_out
);

    `STATIC_ASSERT($bits(axi_r_in.data) == $bits(axi_r_out.data))
    `STATIC_ASSERT($bits(axi_r_in.id) == $bits(axi_r_out.id))

    localparam DATA_WIDTH = $bits(axi_r_in.data);
    localparam ID_WIDTH = $bits(axi_r_in.id);

    typedef struct packed {
        logic [DATA_WIDTH-1:0]   data;
        logic                    last;
        axi4_resp_t              resp;
        logic [ID_WIDTH-1:0]     id;
    } axi_r_t;

    stream_intf #(.T(axi_r_t)) stream_in (.clk, .rst);
    stream_intf #(.T(axi_r_t)) stream_out (.clk, .rst);

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(axi_r_t)
    ) stream_stage_inst (
        .clk, .rst,
        .stream_in, .stream_out
    );

    always_comb begin
        // Connect inputs
        stream_in.valid = axi_r_in.valid;
        axi_r_in.ready = stream_in.ready;
        stream_in.payload = '{
            data: axi_r_in.data,
            last: axi_r_in.last,
            resp: axi_r_in.resp,
            id: axi_r_in.id
        };
        
        // Connect outputs
        axi_r_out.valid = stream_out.valid;
        stream_out.ready = axi_r_out.ready;
        axi_r_out.data = stream_out.payload.data;
        axi_r_out.last = stream_out.payload.last;
        axi_r_out.resp = stream_out.payload.resp;
        axi_r_out.id = stream_out.payload.id;
    end

endmodule

module axi4_b_stage 
    import std_pkg::*;
    import stream_pkg::*;
    import axi4_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED
)(
    input logic clk, rst,
    axi4_b_intf.in axi_b_in,
    axi4_b_intf.out axi_b_out
);

    `STATIC_ASSERT($bits(axi_b_in.id) == $bits(axi_b_out.id))

    localparam ID_WIDTH = $bits(axi_b_in.id);

    typedef struct packed {
        axi4_resp_t              resp;
        logic [ID_WIDTH-1:0]     id;
    } axi_b_t;

    stream_intf #(.T(axi_b_t)) stream_in (.clk, .rst);
    stream_intf #(.T(axi_b_t)) stream_out (.clk, .rst);

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(axi_b_t)
    ) stream_stage_inst (
        .clk, .rst,
        .stream_in, .stream_out
    );

    always_comb begin
        // Connect inputs
        stream_in.valid = axi_b_in.valid;
        axi_b_in.ready = stream_in.ready;
        stream_in.payload = '{
            resp: axi_b_in.resp,
            id: axi_b_in.id
        };
        
        // Connect outputs
        axi_b_out.valid = stream_out.valid;
        stream_out.ready = axi_b_out.ready;
        axi_b_out.resp = stream_out.payload.resp;
        axi_b_out.id = stream_out.payload.id;
    end

endmodule
