`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

module mem_crossbar_tb
#()();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    localparam int PORTS = 2;

    // std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) masters [PORTS] (.clk, .rst);
    // std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) slaves [PORTS] (.clk, .rst);

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) slave0 (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) slave1 (.clk, .rst);

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) master0 (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) master1 (.clk, .rst);

    mem_crossbar #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32),
        .SLAVE_PORTS(PORTS),
        .MASTER_PORTS(PORTS),
        .ADDR_MAP_BEGIN('{32'h0, 32'h8000_0000}),
        .ADDR_MAP_END('{32'h7FFF_FFFF, 32'hFFFF_FFFF})
    ) mem_crossbar_inst (
        .clk, .rst,
        .slaves('{slave0, slave1}),
        .masters('{master0, master1})
    );

    logic re;
    logic [3:0] we; 
    logic [31:0] data, addr;
    logic id;

    initial begin
        slave0.valid = 'b0;
        slave1.valid = 'b0;
        master0.ready = 'b0;
        master1.ready = 'b0;
        while (rst) @ (posedge clk);

        fork
        begin
            slave0.send(0, 0, 'hAABBCCDD, 'h42);
            // slave0.send(0, 0, 'hAABBCCDD, 'h69);
            // slave0.send(0, 0, 'h0ABBCCDD, 'h69);
        end
        begin
            slave1.send(0, 0, 'h0ABBCCDD, 'h100);
            // slave1.send(0, 0, 'hAABBCCDD, 'h200);
        end
        begin
            master1.recv(re, we, addr, data);
            master1.recv(re, we, addr, data);
            master1.recv(re, we, addr, data);
        end
        begin
            master0.recv(re, we, addr, data);
        end
        join

    end

endmodule
