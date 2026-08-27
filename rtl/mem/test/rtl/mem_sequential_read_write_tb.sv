`timescale 1ns / 1ps

module mem_sequential_read_write_tb ();
    /* verilator public_flat_rw_on */
    logic clk, rst;

    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .ID_WIDTH  (4)
    ) mem_write_in (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .ID_WIDTH  (4)
    ) mem_read_in (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .ID_WIDTH  (4)
    ) mem_read_out (
        .clk,
        .rst
    );
    /* verilator public_off */

    always_comb begin
        mem_write_in.read_enable = 0;
        mem_write_in.write_enable = '1;
        mem_write_in.id = 0;
        mem_write_in.last = 0;
    end

    mem_sequential_read_write #(
        .ENABLE_OUTPUT_REG(1)
    ) dut (
        .clk,
        .rst,
        .mem_read_in,
        .mem_read_out,
        .mem_write_in
    );
endmodule
