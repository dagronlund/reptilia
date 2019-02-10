`timescale 1ns/1ps

`include "../lib/std/std_util.svh"
`include "../lib/std/std_mem.svh"

module std_mem_single_tb();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    std_mem_intf mem_command(.*);
    std_mem_intf mem_result(.*);

    std_mem_single #(
        .WRITE_RESPOND(0)
    ) mem_inst0 (
        .clk, .rst,
        .command(mem_command),
        .result(mem_result)
    );

    initial begin
        mem_command.valid = 0;
        while (rst) @ (posedge clk);

        // read_en, write_en, addr, data
        @ (posedge clk);
        mem_command.send('b1, 'b0, 'b0, 'b0);

        @ (posedge clk);
        mem_command.send('b0, 'hf, 'b0, 'b1);

        @ (posedge clk);
        mem_command.send('b1, 'b0, 'b0, 'b0);

        $display("Sends Complete");
    end

    logic result_read_enable;
    logic [3:0] result_write_enable;
    logic [9:0] result_addr;
    logic [31:0] result_data;

    initial begin
        mem_result.ready = 0;
        while (rst) @ (posedge clk);

        @ (posedge clk);
        @ (posedge clk);
        @ (posedge clk);
        mem_result.recv(result_read_enable, result_write_enable, result_addr, result_data);

        @ (posedge clk);
        mem_result.recv(result_read_enable, result_write_enable, result_addr, result_data);

        $display("Recvs Complete");
        $finish;
    end

endmodule
