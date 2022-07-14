//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import riscv/riscv32i_pkg.sv
//!import gecko/gecko_pkg.sv
//!import mem/mem_sequential_double.sv
//!import gecko/gecko_core.sv
//!wrapper gecko/cores/gecko_nano_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

module gecko_nano
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import gecko_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter bit              INST_MEMORY_OUTPUT_REG = 0,
    parameter bit              DATA_MEMORY_OUTPUT_REG = 0,
    parameter gecko_config_t   CONFIG = gecko_get_basic_config(
        INST_MEMORY_OUTPUT_REG ? 2 : 1,
        DATA_MEMORY_OUTPUT_REG ? 2 : 1,
        0
    ),
    parameter int MEMORY_ADDR_WIDTH = 10,
    parameter STARTUP_PROGRAM = ""
)(
    input wire clk, 
    input wire rst,

    output gecko_debug_info_t debug_info,

    stream_intf.in  tty_in, // logic [7:0]
    stream_intf.out tty_out, // logic [7:0]

    output logic       exit_flag,
    output logic       error_flag,
    output logic [7:0] exit_code
);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_result (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) data_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) data_result (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) float_mem_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) float_mem_result (.clk, .rst);

    always_comb float_mem_request.ready = 'b0;
    always_comb float_mem_result.valid = 'b0;

    mem_sequential_double #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .MANUAL_ADDR_WIDTH(MEMORY_ADDR_WIDTH),
        .ADDR_BYTE_SHIFTED(1),
        .ENABLE_OUTPUT_REG0(INST_MEMORY_OUTPUT_REG),
        .ENABLE_OUTPUT_REG1(DATA_MEMORY_OUTPUT_REG),
        .HEX_FILE(STARTUP_PROGRAM)
    ) mem (
        .clk, 
        .rst,

        .mem_in0(inst_request),
        .mem_out0(inst_result),

        .mem_in1(data_request),
        .mem_out1(data_result)
    );

    gecko_core #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .CONFIG(CONFIG)
    ) core (
        .clk, 
        .rst,

        .inst_request,
        .inst_result,

        .data_request,
        .data_result,

        .float_mem_request,
        .float_mem_result,

        .debug_info,

        .tty_in,
        .tty_out,

        .exit_flag,
        .error_flag,
        .exit_code
    );

endmodule
