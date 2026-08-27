`timescale 1ns / 1ps
module stream_split_merge_tb ();
    import std_pkg::*;
    import stream_pkg::*;

    /* verilator public_flat_rw_on */
    logic clk, rst;

    stream_intf #(.T(logic [31:0]))
        ri[2] (
            .clk,
            .rst
        ),
        mid (
            .clk,
            .rst
        ),
        rout[2] (
            .clk,
            .rst
        );
    logic [1:0] rid, rlast, rout_id, rout_last;
    logic mid_id, mid_last;
    /* verilator public_off */

    stream_merge #(
        .PORTS(2),
        .USE_LAST(1)
    ) rr_merge (
        .clk,
        .rst,
        .stream_in(ri),
        .stream_in_id('{rid[0], rid[1]}),
        .stream_in_last('{rlast[0], rlast[1]}),
        .stream_out(mid),
        .stream_out_id(mid_id),
        .stream_out_last(mid_last)
    );
    stream_split #(
        .PORTS(2),
        .USE_LAST(1)
    ) rr_split (
        .clk,
        .rst,
        .stream_in(mid),
        .stream_in_id(mid_id),
        .stream_in_last(mid_last),
        .stream_out(rout),
        .stream_out_id('{rout_id[0], rout_id[1]}),
        .stream_out_last('{rout_last[0], rout_last[1]})
    );
endmodule
