`timescale 1ns/1ps
module stream_merge_tb ();
    import std_pkg::*;
    import stream_pkg::*;

    /* verilator public_flat_rw_on */
    logic clk, rst;

    stream_intf #(.T(logic[31:0])) stream_in[4](.clk,.rst), stream_out(.clk,.rst);
    logic [3:0][1:0] stream_in_id;
    logic [3:0] stream_in_last;
    logic [1:0] stream_out_id;
    logic stream_out_last;
    /* verilator public_off */

    stream_merge #(
        .PORTS(4),
        .ID_WIDTH(2),
        .STREAM_SELECT_MODE(STREAM_SELECT_MODE_ORDERED)
    ) ordered_merge (
        .clk,
        .rst,
        .stream_in,
        .stream_in_id('{stream_in_id[0],stream_in_id[1],stream_in_id[2],stream_in_id[3]}),
        .stream_in_last('{stream_in_last[0],stream_in_last[1],stream_in_last[2],stream_in_last[3]}),
        .stream_out,
        .stream_out_id,
        .stream_out_last
    );
endmodule
