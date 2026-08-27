`timescale 1ns/1ps

module mem_sequential_read_write_tb_wrapper (
    input logic clk, rst,
    input logic rw_w_valid, input logic [9:0] rw_w_addr,
    input logic [31:0] rw_w_data, output logic rw_w_ready,
    input logic rw_r_valid, input logic rw_r_read, input logic [3:0] rw_r_write,
    input logic [9:0] rw_r_addr, input logic [31:0] rw_r_data,
    input logic [3:0] rw_r_id, input logic rw_r_last, output logic rw_r_ready,
    output logic rw_o_valid, input logic rw_o_ready, output logic [31:0] rw_o_data,
    output logic [3:0] rw_o_id, output logic rw_o_last
);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4)) mem_write_in(.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4)) mem_read_in(.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4)) mem_read_out(.clk, .rst);

    always_comb begin
        mem_write_in.valid = rw_w_valid;
        mem_write_in.read_enable = 0;
        mem_write_in.write_enable = '1;
        mem_write_in.addr = rw_w_addr;
        mem_write_in.data = rw_w_data;
        mem_write_in.id = 0;
        mem_write_in.last = 0;
        rw_w_ready = mem_write_in.ready;

        mem_read_in.valid = rw_r_valid;
        mem_read_in.read_enable = rw_r_read;
        mem_read_in.write_enable = rw_r_write;
        mem_read_in.addr = rw_r_addr;
        mem_read_in.data = rw_r_data;
        mem_read_in.id = rw_r_id;
        mem_read_in.last = rw_r_last;
        rw_r_ready = mem_read_in.ready;

        rw_o_valid = mem_read_out.valid;
        mem_read_out.ready = rw_o_ready;
        rw_o_data = mem_read_out.data;
        rw_o_id = mem_read_out.id;
        rw_o_last = mem_read_out.last;
    end

    mem_sequential_read_write #(.ENABLE_OUTPUT_REG(1)) dut (
        .clk,
        .rst,
        .mem_read_in,
        .mem_read_out,
        .mem_write_in
    );
endmodule
