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
#()(
    input logic clk, rst
);

    std_mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .ADDR_BYTE_SHIFTED(1)
    ) inst_request (.clk, .rst);

    std_mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .ADDR_BYTE_SHIFTED(1)
    ) inst_result (.clk, .rst);

    std_mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .ADDR_BYTE_SHIFTED(1)
    ) data_request (.clk, .rst);

    std_mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .ADDR_BYTE_SHIFTED(1)
    ) data_result (.clk, .rst);

    std_mem_double #(
        .MANUAL_ADDR_WIDTH(10),
        .HEX_FILE("test.bin")
    ) memory_inst (
        .clk, .rst,
        .command0(inst_request), .command1(data_request),
        .result0(inst_result), .result1(data_result)
    );

    gecko_core #(
        .INST_LATENCY(1),
        .DATA_LATENCY(1)
    ) gecko_core_inst (
        .clk, .rst,
        .inst_request, .inst_result,
        .data_request, .data_result
    );


endmodule

