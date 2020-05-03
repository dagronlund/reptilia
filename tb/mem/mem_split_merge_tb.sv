`timescale 1ns/1ps

module mem_split_merge_tb
    import std_pkg::*;
    import stream_pkg::*;
#()();

    localparam std_clock_info_t CLOCK_INFO = 'b0;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    localparam int PORTS = 2;

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_in [PORTS] (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_mid (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_out [PORTS] (.clk, .rst);

    mem_merge #(
        .CLOCK_INFO(CLOCK_INFO),
        .PORTS(PORTS)
    ) mem_merge_inst (
        .clk, .rst,
        .mem_in(mem_in),
        .mem_out(mem_mid)
    );

    mem_split #(
        .CLOCK_INFO(CLOCK_INFO),
        .PORTS(PORTS)
    ) mem_split_inst(
        .clk, .rst,
        .mem_in(mem_mid),
        .mem_out(mem_out)
    );

    logic re;
    logic [3:0] we; 
    logic [31:0] data, addr;
    logic id;

    initial begin
        mem_in[0].valid = 'b0;
        mem_in[1].valid = 'b0;
        mem_out[0].ready = 'b0;
        mem_out[1].ready = 'b0;
        
        while (std_is_reset_active(CLOCK_INFO, rst)) @ (posedge clk);

    end

endmodule
