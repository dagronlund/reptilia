`timescale 1ns/1ps

`ifdef __LINTER__

`include "../lib/isa/rv.svh"
`include "../lib/isa/rv32.svh"
`include "../lib/isa/rv32i.svh"
`include "../lib/gecko/gecko.svh"
`include "../lib/axi/axi4.svh"

`else

`include "rv.svh"
`include "rv32.svh"
`include "rv32i.svh"
`include "gecko.svh"
`include "axi4.svh"

`endif

module gecko_compute_wrapper_sv #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int STROBE_WIDTH = DATA_WIDTH / 8,
    parameter int USER_WIDTH = 1,
    parameter int ID_WIDTH = 1,

    parameter int ADDR_SPACE_WIDTH = 13,
    parameter int INST_LATENCY = 2,
    parameter int DATA_LATENCY = 2,
    parameter logic [31:0] START_ADDR = 'h0,
    parameter int ENABLE_PERFORMANCE_COUNTERS = 1,
    parameter int ENABLE_PRINT = 1
)(
    input logic clk, rst,
    
    input logic                    axi_arvalid, 
    output logic                   axi_arready,
    input logic [ADDR_WIDTH-1:0]   axi_araddr,
    input logic [1:0]              axi_arburst,
    input logic [3:0]              axi_arcache,
    input logic [7:0]              axi_arlen,
    input logic                    axi_arlock,
    input logic [2:0]              axi_arprot,
    input logic [3:0]              axi_arqos,
    input logic [2:0]              axi_arsize,
    input logic [USER_WIDTH-1:0]   axi_aruser,
    input logic [ID_WIDTH-1:0]     axi_arid,
    input logic                    axi_awvalid,
    output logic                   axi_awready,
    input logic [ADDR_WIDTH-1:0]   axi_awaddr,
    input logic [1:0]              axi_awburst,
    input logic [3:0]              axi_awcache,
    input logic [7:0]              axi_awlen,
    input logic                    axi_awlock,
    input logic [2:0]              axi_awprot,
    input logic [3:0]              axi_awqos,
    input logic [2:0]              axi_awsize,
    input logic [USER_WIDTH-1:0]   axi_awuser,
    input logic [ID_WIDTH-1:0]     axi_awid,

    input logic                    axi_wvalid,
    output logic                   axi_wready,
    input logic [DATA_WIDTH-1:0]   axi_wdata,
    input logic [STROBE_WIDTH-1:0] axi_wstrb,
    input logic                    axi_wlast,
    
    output logic                   axi_bvalid,
    input logic                    axi_bready,
    output logic [1:0]             axi_bresp,
    output logic [ID_WIDTH-1:0]    axi_bid,
    
    output logic                   axi_rvalid,
    input logic                    axi_rready,
    output logic [DATA_WIDTH-1:0]  axi_rdata,
    output logic                   axi_rlast,
    output logic [1:0]             axi_rresp,
    output logic [ID_WIDTH-1:0]    axi_rid,

    output logic print_valid,
    input logic print_ready,
    output logic [7:0] print_data,

    output logic faulted_flag, finished_flag
);

    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
    import axi4::*;

    axi4_ar_intf #(.ID_WIDTH(ID_WIDTH)) axi_ar(.clk, .rst);
    axi4_aw_intf #(.ID_WIDTH(ID_WIDTH)) axi_aw(.clk, .rst);
    axi4_w_intf axi_w(.clk, .rst);
    axi4_r_intf #(.ID_WIDTH(ID_WIDTH)) axi_r(.clk, .rst);
    axi4_b_intf #(.ID_WIDTH(ID_WIDTH))axi_b(.clk, .rst);

    std_stream_intf #(.T(logic [7:0])) print_out(.clk, .rst);
    
    gecko_compute #(
        .ADDR_SPACE_WIDTH(ADDR_SPACE_WIDTH),
        .INST_LATENCY(INST_LATENCY),
        .DATA_LATENCY(DATA_LATENCY),
        .START_ADDR(START_ADDR),
        .ENABLE_PERFORMANCE_COUNTERS(ENABLE_PERFORMANCE_COUNTERS),
        .ENABLE_PRINT(ENABLE_PRINT),
        .AXI_ID_WIDTH(ID_WIDTH)
    ) gecko_compute_inst (
        .clk, .rst,

        .axi_ar, .axi_aw, .axi_w, .axi_r, .axi_b,

        .faulted_flag, .finished_flag,

        .print_out
    );

    always_comb begin

        axi_ar.arvalid = axi_arvalid;
        axi_arready = axi_ar.arready;
        axi_ar.araddr = axi_araddr;
        axi_ar.arburst = axi4_burst_t'(axi_arburst);
        axi_ar.arcache = axi4_cache_t'(axi_arcache);
        axi_ar.arlen = axi_arlen;
        axi_ar.arlock = axi4_lock_t'(axi_arlock);
        axi_ar.arprot = axi4_prot_t'(axi_arprot);
        axi_ar.arqos = axi_arqos;
        axi_ar.arsize = axi_arsize;
        axi_ar.aruser = axi_aruser;
        axi_ar.arid = axi_arid;

        axi_aw.awvalid = axi_awvalid;
        axi_awready = axi_aw.awready;
        axi_aw.awaddr = axi_awaddr;
        axi_aw.awburst = axi4_burst_t'(axi_awburst);
        axi_aw.awcache = axi4_cache_t'(axi_awcache);
        axi_aw.awlen = axi_awlen;
        axi_aw.awlock = axi4_lock_t'(axi_awlock);
        axi_aw.awprot = axi4_prot_t'(axi_awprot);
        axi_aw.awqos = axi_awqos;
        axi_aw.awsize = axi_awsize;
        axi_aw.awuser = axi_awuser;
        axi_aw.awid = axi_awid;

        axi_w.wvalid = axi_wvalid;
        axi_wready = axi_w.wready;
        axi_w.wdata = axi_wdata;
        axi_w.wstrb = axi_wstrb;
        axi_w.wlast = axi_wlast;

        axi_bvalid = axi_b.bvalid;
        axi_b.bready = axi_bready;
        axi_bresp = axi_b.bresp;
        axi_bid = axi_b.bid;

        axi_rvalid = axi_r.rvalid;
        axi_r.rready = axi_rready;
        axi_rdata = axi_r.rdata;
        axi_rlast = axi_r.rlast;
        axi_rresp = axi_r.rresp;
        axi_rid = axi_r.rid;

        print_valid = print_out.valid;
        print_out.ready = print_ready;
        print_data = print_out.payload;
    end

endmodule
