`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

module mem_mux_tb
#()();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    localparam int SLAVE_PORTS = 2;
    localparam int ID_WIDTH = 2;

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) master_command0 (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) master_command1 (.clk, .rst);

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) slave_command (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) slave_result (.clk, .rst);

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) master_result0 (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) master_result1 (.clk, .rst);

    mem_mux #(
        .ID_WIDTH(ID_WIDTH),
        .SLAVE_PORTS(SLAVE_PORTS)
    ) mem_mux_inst (
        .clk, .rst,

        .slave_command('{master_command0, master_command1}),
        .slave_result('{master_result0, master_result1}),

        .master_command(slave_command),
        .master_result(slave_result)
    );

    std_mem_single #(
        .MANUAL_ADDR_WIDTH(16),
        .ADDR_BYTE_SHIFTED(1),
        .ENABLE_OUTPUT_REG(0)
    ) memory_inst (
        .clk, .rst,
        .command(slave_command),
        .result(slave_result)
    );

    logic re;
    logic [3:0] we; 
    logic [31:0] data, addr;
    logic id;

    initial begin
        master_command0.valid = 'b0;
        master_command1.valid = 'b0;
        master_result0.ready = 'b0;
        master_result1.ready = 'b0;
        while (rst) @ (posedge clk);

        fork
        begin
            master_command0.send('b1, 'b0, 'b0, 'h1, 'b0);
            master_command0.send('b1, 'b0, 'b0, 'h2, 'b0);
        end
        begin
            master_command1.send('b1, 'b0, 'b0, 'h3, 'b0);
            master_command1.send('b1, 'b0, 'b0, 'h4, 'b0);
        end
        begin
            master_result1.recv(re, we, data, addr, id);
            master_result0.recv(re, we, data, addr, id);
            master_result0.recv(re, we, data, addr, id);
            master_result1.recv(re, we, data, addr, id);
        end
        join

    end

endmodule
