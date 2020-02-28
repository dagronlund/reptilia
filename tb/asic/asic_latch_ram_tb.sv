`timescale 1ns/1ps

module asic_latch_ram_tb
    import std_pkg::*;
#()();

    localparam std_clock_info_t CLOCK_INFO = 'b0;

    logic clk, rst;
    clk_rst_gen #() clk_rst_gen_inst(.clk, .rst);

    localparam int DATA_WIDTH = 32;
    localparam int ADDR_WIDTH = 5;
    localparam int READ_PORTS = 2;

    logic write_enable;
    logic [ADDR_WIDTH-1:0] write_addr;
    logic [DATA_WIDTH-1:0] write_data_in, write_data_out;

    logic [READ_PORTS-1:0] [ADDR_WIDTH-1:0] read_addr;
    logic [READ_PORTS-1:0] [DATA_WIDTH-1:0] read_data_out;

    asic_latch_ram #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(STD_TECHNOLOGY_ASIC_TSMC),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .READ_PORTS(READ_PORTS)
    ) asic_latch_ram_inst (
        .clk, .rst,

        .write_enable,
        .write_addr,
        .write_data_in,
        .write_data_out,

        .read_addr,
        .read_data_out
    );

    initial begin
        write_enable = 'b0;
        write_addr = 'b0;
        write_data_in = 'b0;
        read_addr[0] = 'b0;
        read_addr[1] = 'b0;

        @ (posedge clk);
        while (std_is_reset_active(CLOCK_INFO, rst)) @ (posedge clk);

        @ (posedge clk);
        write_enable <= 'b1;
        write_addr <= 'd1;
        write_data_in <= 'h42;

        @ (posedge clk);
        @ (posedge clk);
        write_enable <= 'b1;
        write_addr <= 'd2;
        write_data_in <= 'h69;

        @ (posedge clk);
        write_enable <= 'b1;
        write_addr <= 'd3;
        write_data_in <= 'h420;

        // Test to make sure we don't overwrite something
        // when the address is there but not write enabled
        @ (posedge clk);
        write_enable <= 'b0;
        write_addr <= 'd1;
        write_data_in <= 'h420;

        @ (posedge clk);
        write_enable <= 'b0;

        @ (posedge clk);
        read_addr[0] = 'd3;
        read_addr[1] = 'd2;
        #1; // This is disgusting
        $display("Read Data out (should be 'h420, 'h69) %h, %h", 
                read_data_out[0], read_data_out[1]);

        @ (posedge clk);
        $finish();
    end

endmodule
