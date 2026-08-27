`timescale 1ns/1ps

module mem_sequential_double_tb_wrapper (
    input logic clk, rst,
    input logic d0_valid, d0_read, input logic [3:0] d0_write,
    input logic [9:0] d0_addr, input logic [31:0] d0_data,
    input logic [3:0] d0_id, input logic d0_last, output logic d0_ready,
    output logic d0o_valid, input logic d0o_ready, output logic [31:0] d0o_data,
    output logic [3:0] d0o_id, output logic d0o_last,
    input logic d1_valid, d1_read, input logic [3:0] d1_write,
    input logic [9:0] d1_addr, input logic [31:0] d1_data,
    input logic [3:0] d1_id, input logic d1_last, output logic d1_ready,
    output logic d1o_valid, input logic d1o_ready, output logic [31:0] d1o_data,
    output logic [3:0] d1o_id, output logic d1o_last
);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4)) mem_in[2](.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4)) mem_out[2](.clk, .rst);

    always_comb begin
        mem_in[0].valid = d0_valid;
        mem_in[0].read_enable = d0_read;
        mem_in[0].write_enable = d0_write;
        mem_in[0].addr = d0_addr;
        mem_in[0].data = d0_data;
        mem_in[0].id = d0_id;
        mem_in[0].last = d0_last;
        d0_ready = mem_in[0].ready;
        d0o_valid = mem_out[0].valid;
        mem_out[0].ready = d0o_ready;
        d0o_data = mem_out[0].data;
        d0o_id = mem_out[0].id;
        d0o_last = mem_out[0].last;

        mem_in[1].valid = d1_valid;
        mem_in[1].read_enable = d1_read;
        mem_in[1].write_enable = d1_write;
        mem_in[1].addr = d1_addr;
        mem_in[1].data = d1_data;
        mem_in[1].id = d1_id;
        mem_in[1].last = d1_last;
        d1_ready = mem_in[1].ready;
        d1o_valid = mem_out[1].valid;
        mem_out[1].ready = d1o_ready;
        d1o_data = mem_out[1].data;
        d1o_id = mem_out[1].id;
        d1o_last = mem_out[1].last;
    end

    mem_sequential_double #(
        .ENABLE_OUTPUT_REG0(1),
        .ENABLE_OUTPUT_REG1(1)
    ) dut (
        .clk,
        .rst,
        .mem_in0(mem_in[0]),
        .mem_out0(mem_out[0]),
        .mem_in1(mem_in[1]),
        .mem_out1(mem_out[1])
    );
endmodule
