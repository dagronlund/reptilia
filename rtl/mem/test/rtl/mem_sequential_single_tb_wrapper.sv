`timescale 1ns/1ps

module mem_sequential_single_tb_wrapper (
    input logic clk, rst,
    input logic s_valid, s_read, input logic [3:0] s_write,
    input logic [9:0] s_addr, input logic [31:0] s_data,
    input logic [3:0] s_id, input logic s_last, output logic s_ready,
    output logic so_valid, input logic so_ready, output logic [31:0] so_data,
    output logic [3:0] so_id, output logic so_last
);
    import std_pkg::*;
    import stream_pkg::*;

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4)) mem_in(.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4)) mem_mid(.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4)) mem_out(.clk, .rst);

    always_comb begin
        mem_in.valid = s_valid;
        mem_in.read_enable = s_read;
        mem_in.write_enable = s_write;
        mem_in.addr = s_addr;
        mem_in.data = s_data;
        mem_in.id = s_id;
        mem_in.last = s_last;
        s_ready = mem_in.ready;

        so_valid = mem_out.valid;
        mem_out.ready = so_ready;
        so_data = mem_out.data;
        so_id = mem_out.id;
        so_last = mem_out.last;
    end

    mem_sequential_single #(.ENABLE_OUTPUT_REG(1)) dut (
        .clk,
        .rst,
        .mem_in,
        .mem_out(mem_mid)
    );

    mem_stage #(.PIPELINE_MODE(STREAM_PIPELINE_MODE_REGISTERED)) output_stage (
        .clk,
        .rst,
        .mem_in(mem_mid),
        .mem_in_meta('0),
        .mem_out,
        .mem_out_meta()
    );
endmodule
