`timescale 1ns/1ps
module stream_fifo_tb #(
    parameter stream_pkg::stream_fifo_mode_t FIFO_MODE =
        stream_pkg::STREAM_FIFO_MODE_COMBINATIONAL_REGISTERED,
    parameter int DEPTH = 16
) ();
    /* verilator public_flat_rw_on */
    logic clk, rst;

    stream_intf #(.T(logic[31:0])) stream_in(.clk, .rst);
    stream_intf #(.T(logic[31:0])) stream_out(.clk, .rst);
    /* verilator public_off */

    stream_fifo #(
        .FIFO_MODE(FIFO_MODE),
        .DEPTH(DEPTH),
        .T(logic[31:0])
    ) dut (
        .clk,
        .rst,
        .stream_in,
        .stream_out
    );
endmodule
