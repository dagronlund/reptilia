`timescale 1ns/1ps

`include "../lib/rv_axi4_lite.svh"
`include "../lib/def/rv_axi4_lite_def.svh"

// `include "../lib/def/rv_io_def.svh"

module rv_i2c_controller_wrapper_sv #(
    parameter DEFAULT_CYCLES = 10'd249,
    parameter DEFAULT_DELAY = 10'd0
)(
    input logic clk, rst,

    `RV_AXI4_LITE_PORTS_SLAVE(axi, 32, 32),

    output logic scl_t, scl_o,
    input logic scl_i,

    output logic sda_t, sda_o,
    input logic sda_i
);

    `RV_AXI4_LITE_CREATE_INTF(axi, 32, 32)
    `RV_AXI4_LITE_CONNECT_PORTS_TO_INTF(axi, axi)

    rv_io_intf scl();
    rv_io_intf sda();

    assign scl_o = scl.o;
    assign scl_t = scl.t;
    assign scl.i = scl_i;

    assign sda_o = sda.o;
    assign sda_t = sda.t;
    assign sda.i = sda_i;

    rv_i2c_controller #(
        .DEFAULT_CYCLES(DEFAULT_CYCLES),
        .DEFAULT_DELAY(DEFAULT_DELAY)
    ) rv_i2c_controller_inst (.*);

endmodule

