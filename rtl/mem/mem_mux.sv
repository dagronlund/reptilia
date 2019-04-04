`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

module mem_mux #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int MASK_WIDTH = DATA_WIDTH / 8,
    parameter int ID_WIDTH = 1,
    parameter int SLAVE_PORTS = 2
)(
    input logic clk, rst,

    std_mem_intf.in slave_command [SLAVE_PORTS],
    std_mem_intf.out slave_result [SLAVE_PORTS],

    std_mem_intf.out master_command,
    std_mem_intf.in master_result
);

    `STATIC_ASSERT(SLAVE_PORTS > 1)

    mem_merge #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .PORTS(SLAVE_PORTS)
    ) mem_merge_inst (
        .clk, .rst,

        .mem_in(slave_command),
        .mem_out(master_command)
    );

    mem_split #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .PORTS(SLAVE_PORTS)
    ) mem_split_inst (
        .clk, .rst,

        .mem_in(master_result),
        .mem_out(slave_result)
    );

endmodule
