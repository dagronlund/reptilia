//!import std/std_pkg
//!import std/stream_pkg
//!import stream/stream_intf
//!import stream/stream_stage
//!import axi/axi4_pkg

`timescale 1ns/1ps

module axi4_tb
    import std_pkg::*;
    import stream_pkg::*;
    import axi4_pkg::*;
#()();

    localparam std_clock_info_t CLOCK_INFO = 'b0;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    axi4_ar_intf #(.ADDR_WIDTH(32), .USER_WIDTH(1), .ID_WIDTH(1)) axi_ar_in (.clk, .rst);
    axi4_ar_intf #(.ADDR_WIDTH(32), .USER_WIDTH(1), .ID_WIDTH(1)) axi_ar_out (.clk, .rst);

    axi4_ar_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_TRANSPARENT)
    ) axi4_ar_stage_inst (
        .clk, .rst,
        .axi_ar_in, .axi_ar_out
    );

    axi4_aw_intf #(.ADDR_WIDTH(32), .USER_WIDTH(1), .ID_WIDTH(1)) axi_aw_in (.clk, .rst);
    axi4_aw_intf #(.ADDR_WIDTH(32), .USER_WIDTH(1), .ID_WIDTH(1)) axi_aw_out (.clk, .rst);

    axi4_aw_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_TRANSPARENT)
    ) axi4_aw_stage_inst (
        .clk, .rst,
        .axi_aw_in, .axi_aw_out
    );

    axi4_w_intf #(.DATA_WIDTH(32)) axi_w_in (.clk, .rst);
    axi4_w_intf #(.DATA_WIDTH(32)) axi_w_out (.clk, .rst);

    axi4_w_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_TRANSPARENT)
    ) axi4_w_stage_inst (
        .clk, .rst,
        .axi_w_in, .axi_w_out
    );

    axi4_r_intf #(.DATA_WIDTH(32), .ID_WIDTH(1)) axi_r_in (.clk, .rst);
    axi4_r_intf #(.DATA_WIDTH(32), .ID_WIDTH(1)) axi_r_out (.clk, .rst);

    axi4_r_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_TRANSPARENT)
    ) axi4_r_stage_inst (
        .clk, .rst,
        .axi_r_in, .axi_r_out
    );

    axi4_b_intf #(.ID_WIDTH(1)) axi_b_in (.clk, .rst);
    axi4_b_intf #(.ID_WIDTH(1)) axi_b_out (.clk, .rst);    

    axi4_b_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_TRANSPARENT)
    ) axi4_b_stage_inst (
        .clk, .rst,
        .axi_b_in, .axi_b_out
    );

endmodule
