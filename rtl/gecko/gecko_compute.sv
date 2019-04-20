`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/gecko/gecko.svh"
`include "../../lib/axi/axi4.svh"

`else

`include "std_util.svh"
`include "std_mem.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32i.svh"
`include "gecko.svh"
`include "axi4.svh"

`endif

module gecko_compute
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
    import axi4::*;
#(
    parameter ADDR_SPACE_WIDTH = 16,
    parameter INST_LATENCY = 2,
    parameter DATA_LATENCY = 2,
    parameter gecko_pc_t START_ADDR = 'h0,
    parameter int ENABLE_PERFORMANCE_COUNTERS = 1
)(
    input logic clk, rst,

    axi4_ar_intf.in axi_ar,
    axi4_aw_intf.in axi_aw,
    axi4_w_intf.in axi_w,
    axi4_r_intf.out axi_r,
    axi4_b_intf.out axi_b,

    output logic faulted_flag, finished_flag
);

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) supervisor_request (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) supervisor_response (.clk, .rst);

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_request (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_response (.clk, .rst);

    axi4_slave #(
        // parameter int AXI_ADDR_WIDTH = 32,
        // parameter int AXI_DATA_WIDTH = 32,
        // parameter int AXI_ID_WIDTH = 1,
        // parameter int AXI_USER_WIDTH = 1,

        // parameter int MEM_ADDR_WIDTH = 32,
        // parameter int MEM_DATA_WIDTH = 32,
    ) axi4_slave_inst (
        .clk, .rst,

        .axi_ar, .axi_aw, .axi_w, .axi_r, .axi_b,
        .mem_request(supervisor_request),
        .mem_response(supervisor_response)
    );

    gecko_micro #(
        .ADDR_SPACE_WIDTH(ADDR_SPACE_WIDTH),
        .INST_LATENCY(INST_LATENCY),
        .DATA_LATENCY(DATA_LATENCY),
        .START_ADDR(START_ADDR),
        .ENABLE_PERFORMANCE_COUNTERS(ENABLE_PERFORMANCE_COUNTERS)
    ) gecko_micro_inst (
        .clk, .rst,

        .supervisor_request, .supervisor_response,
        .faulted_flag, .finished_flag
    );

endmodule
