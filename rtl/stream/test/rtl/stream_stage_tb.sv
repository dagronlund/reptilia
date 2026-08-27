`timescale 1ns/1ps
module stream_stage_tb #(
    parameter stream_pkg::stream_pipeline_mode_t PIPELINE_MODE =
        stream_pkg::STREAM_PIPELINE_MODE_REGISTERED
) ();
    /* verilator public_flat_rw_on */
    logic clk, rst;

    stream_intf #(.T(logic[31:0])) stream_in(.clk, .rst);
    stream_intf #(.T(logic[31:0])) stream_out(.clk, .rst);
    /* verilator public_off */

    stream_stage #(
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(logic[31:0])
    ) dut (
        .clk,
        .rst,
        .stream_in,
        .stream_out
    );
endmodule
