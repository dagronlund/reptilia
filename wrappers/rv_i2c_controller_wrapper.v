`timescale 1ns/1ps

`include "../lib/def/rv_axi4_lite_def.svh"

module rv_i2c_controller_wrapper #(
    parameter DEFAULT_CYCLES = 10'd249,
    parameter DEFAULT_DELAY = 10'd0
)(
    input wire clk, rst,

    `RV_AXI4_LITE_PORTS_SLAVE(axi, 32, 32),

    output wire s_scl_t, s_scl_o,
    input wire s_scl_i,

    output wire s_sda_t, s_sda_o,
    input wire s_sda_i
);

    // test_wrapper_sv test_wrapper_sv_inst (

    //     `RV_AXI4_CONNECT_PORTS(axi4_master, axi4_master),
    //     `RV_AXI4_CONNECT_PORTS(axi4_slave, axi4_slave),

    //     `RV_AXI4_LITE_CONNECT_PORTS(axi4_lite_master, axi4_lite_master),
    //     `RV_AXI4_LITE_CONNECT_PORTS(axi4_lite_slave, axi4_lite_slave)
    // );

    rv_i2c_controller_wrapper_sv #(
        .DEFAULT_CYCLES(DEFAULT_CYCLES),
        .DEFAULT_DELAY(DEFAULT_DELAY)
    ) rv_i2c_controller_wrapper_sv_inst (
        .clk(clk), .rst(rst),

        `RV_AXI4_LITE_CONNECT_PORTS(axi, axi),

        .scl_t(s_scl_t),
        .scl_o(s_scl_o),
        .scl_i(s_scl_i),
        .sda_t(s_sda_t),
        .sda_o(s_sda_o),
        .sda_i(s_sda_i)
    );

endmodule
