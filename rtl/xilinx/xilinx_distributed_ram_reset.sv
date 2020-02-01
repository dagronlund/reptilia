`timescale 1ns/1ps

//!import std/std_pkg
//!import std/std_register
//!import xilinx/xilinx_distributed_ram

module xilinx_distributed_ram_reset
    import std_pkg.*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter int DATA_WIDTH = 1,
    parameter int ADDR_WIDTH = 5,
    parameter int READ_PORTS = 1
)(
    input wire clk, 
    input wire rst,

    output logic reset_done,

    input wire [DATA_WIDTH-1:0]   write_enable,
    input wire [ADDR_WIDTH-1:0]   write_addr,
    input wire [DATA_WIDTH-1:0]   write_data_in,
    output logic [DATA_WIDTH-1:0] write_data_out,

    input wire [ADDR_WIDTH-1:0]   read_addr [READ_PORTS],
    output logic [DATA_WIDTH-1:0] read_data_out [READ_PORTS]
);

    logic current_reset_state, clear_reset_state;
    logic [ADDR_WIDTH-1:0] current_reset_counter, next_reset_counter;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic),
        .RESET_VECTOR('b1)
    ) reset_state_reg_inst (
        .clk, .rst,
        .enable(clear_reset_state),
        .next('b0),
        .value(current_reset_state)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic[ADDR_WIDTH-1:0]),
        .RESET_VECTOR('b0)
    ) reset_counter_reg_inst (
        .clk, .rst,
        .enable(current_reset_state),
        .next(next_reset_counter),
        .value(current_reset_counter)
    );

    logic [DATA_WIDTH-1:0] write_enable_internal;
    logic [ADDR_WIDTH-1:0] write_addr_internal;
    logic [DATA_WIDTH-1:0] write_data_in_internal;

    xilinx_distributed_ram #(
        .CLOCK_INFO(CLOCK_INFO),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .READ_PORTS(READ_PORTS)
    ) xilinx_distributed_ram_inst (
        .clk, .rst,

        .write_enable(write_enable_internal),
        .write_addr(write_addr_internal),
        .write_data_in(write_data_in_internal),
        .write_data_out,

        .read_addr, .read_data_out
    );

    always_comb begin
        clear_reset_state = (current_reset_counter == {ADDR_WIDTH{1'b1}});
        next_reset_counter = current_reset_counter + 'b1;

        if (current_reset_state) begin
            write_enable_internal = {DATA_WIDTH{1'b1}};
            write_addr_internal = current_reset_counter;
            write_data_in_internal = 'b0;
        end else begin
            write_enable_internal = write_enable;
            write_addr_internal = write_addr;
            write_data_in_internal = write_data_in;
        end
    end

endmodule
