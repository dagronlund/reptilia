`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

module gecko_micro
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#(
    parameter ADDR_SPACE_WIDTH = 16,
    parameter INST_LATENCY = 2,
    parameter DATA_LATENCY = 2,
    parameter gecko_pc_t START_ADDR = 'h0
)(
    input logic clk, rst,

    output logic faulted_flag, finished_flag
);

    `STATIC_ASSERT(INST_LATENCY > 0)
    `STATIC_ASSERT(DATA_LATENCY > 0)

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_request (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_result (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_result_registered (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) data_request (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) data_result (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) data_result_registered (.clk, .rst);

    std_mem_stage #(
        .LATENCY((INST_LATENCY > 1) ? (INST_LATENCY - 2) : 0)
    ) inst_register_stage (
        .clk, .rst,
        .data_in(inst_result),
        .data_out(inst_result_registered)
    );

    std_mem_stage #(
        .LATENCY((DATA_LATENCY > 1) ? (DATA_LATENCY - 2) : 0)
    ) data_register_stage (
        .clk, .rst,
        .data_in(data_result),
        .data_out(data_result_registered)
    );

    std_mem_double #(
        .MANUAL_ADDR_WIDTH(ADDR_SPACE_WIDTH),
        .ADDR_BYTE_SHIFTED(1),
        .ENABLE_OUTPUT_REG0((INST_LATENCY > 1) ? 1 : 0),
        .ENABLE_OUTPUT_REG1((DATA_LATENCY > 1) ? 1 : 0),
        .HEX_FILE("test.mem")
    ) memory_inst (
        .clk, .rst,
        .command0(inst_request), .command1(data_request),
        .result0(inst_result), .result1(data_result)
    );

    gecko_core #(
        .INST_LATENCY(INST_LATENCY),
        .DATA_LATENCY(DATA_LATENCY),
        .START_ADDR(START_ADDR)
    ) gecko_core_inst (
        .clk, .rst,
        .inst_request, .inst_result(inst_result_registered),
        .data_request, .data_result(data_result_registered),
        .faulted_flag, .finished_flag
    );


endmodule

