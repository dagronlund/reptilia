`timescale 1ns / 1ps

module mem_sequential_double_tb ();
    /* verilator public_flat_rw_on */
    logic clk, rst;

    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .ID_WIDTH  (4)
    ) mem_in[2] (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .ID_WIDTH  (4)
    ) mem_out[2] (
        .clk,
        .rst
    );
    /* verilator public_off */

    mem_sequential_double #(
        .ENABLE_OUTPUT_REG0(1),
        .ENABLE_OUTPUT_REG1(1)
    ) dut (
        .clk,
        .rst,
        .mem_in0 (mem_in[0]),
        .mem_out0(mem_out[0]),
        .mem_in1 (mem_in[1]),
        .mem_out1(mem_out[1])
    );
endmodule
