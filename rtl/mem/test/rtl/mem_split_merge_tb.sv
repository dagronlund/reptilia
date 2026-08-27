`timescale 1ns / 1ps
module mem_split_merge_tb ();
    import std_pkg::*;
    import stream_pkg::*;

    /* verilator public_flat_rw_on */
    logic clk, rst;

    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .ID_WIDTH  (1)
    ) mi[2] (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .ID_WIDTH  (2)
    ) mm (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .ID_WIDTH  (1)
    ) mo[2] (
        .clk,
        .rst
    );
    logic [1:0] meta_i;
    logic meta_m;
    logic [1:0] meta_o;
    /* verilator public_off */

    mem_merge #(
        .PORTS(2),
        .META_WIDTH(1),
        .USE_LAST(1)
    ) merge_inst (
        .clk,
        .rst,
        .mem_in(mi),
        .mem_in_meta('{meta_i[0], meta_i[1]}),
        .mem_out(mm),
        .mem_out_meta(meta_m)
    );
    mem_split #(
        .PORTS(2),
        .META_WIDTH(1),
        .USE_LAST(1)
    ) split_inst (
        .clk,
        .rst,
        .mem_in(mm),
        .mem_in_meta(meta_m),
        .mem_out(mo),
        .mem_out_meta('{meta_o[0], meta_o[1]})
    );
endmodule
