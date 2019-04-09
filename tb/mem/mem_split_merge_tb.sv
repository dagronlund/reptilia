`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

module mem_split_merge_tb
#()();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    localparam int PORTS = 2;

    // std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_in [PORTS] (.clk, .rst);
    // std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_out [PORTS] (.clk, .rst);

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_in0 (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_in1 (.clk, .rst);

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_mid (.clk, .rst);

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_out0 (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_out1 (.clk, .rst);


    mem_merge #(
        .PORTS(PORTS),
        .PIPELINE_MODE(1)
    ) mem_merge_inst (
        .clk, .rst,
        .mem_in('{mem_in0, mem_in1}),
        // .mem_in(mem_in),
        .mem_out(mem_mid)
    );

    mem_split #(
        .PORTS(PORTS),
        .PIPELINE_MODE(0)
    ) mem_split_inst(
        .clk, .rst,
        .mem_in(mem_mid),
        .mem_out('{mem_out0, mem_out1})
        // .mem_out(mem_out)
    );

    logic re;
    logic [3:0] we; 
    logic [31:0] data, addr;
    logic id;

    initial begin
        mem_in0.valid = 'b0;
        mem_in1.valid = 'b0;
        mem_out0.ready = 'b0;
        mem_out1.ready = 'b0;
        while (rst) @ (posedge clk);

        fork
        begin
            mem_in0.send('b0, 'b0, 'b0, 'h1, 'b0);
            mem_in0.send('b0, 'b0, 'b0, 'h2, 'b0);
        end
        begin
            mem_in1.send('b0, 'b0, 'b0, 'h3, 'b0);
            mem_in1.send('b0, 'b0, 'b0, 'h4, 'b0);
        end
        begin
            mem_out0.recv(re, we, data, addr, id);
            // mem_out1.recv(re, we, data, addr, id);
            mem_out0.recv(re, we, data, addr, id);
            // mem_out1.recv(re, we, data, addr, id);
        end
        begin
            mem_out1.recv(re, we, data, addr, id);
            mem_out1.recv(re, we, data, addr, id);
        end
        join

    end

endmodule
