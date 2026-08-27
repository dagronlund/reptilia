`timescale 1ns / 1ps

module mem_sequential_single_tb ();
    import std_pkg::*;
    import stream_pkg::*;

    /* verilator public_flat_rw_on */
    logic clk, rst;

    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .ID_WIDTH  (4)
    ) mem_in (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .ID_WIDTH  (4)
    ) mem_mid (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .ID_WIDTH  (4)
    ) mem_out (
        .clk,
        .rst
    );
    /* verilator public_off */

    mem_sequential_single #(
        .ENABLE_OUTPUT_REG(1)
    ) dut (
        .clk,
        .rst,
        .mem_in,
        .mem_out(mem_mid)
    );

    mem_stage #(
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_REGISTERED)
    ) output_stage (
        .clk,
        .rst,
        .mem_in(mem_mid),
        .mem_in_meta('0),
        .mem_out,
        .mem_out_meta()
    );
endmodule
