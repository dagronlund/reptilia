//!import std/std_pkg.sv
//!import std/std_register.sv
//!import xilinx/xilinx_distributed_ram.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

module mem_combinational
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter int DATA_WIDTH = 1,
    parameter int ADDR_WIDTH = 5,
    parameter int READ_PORTS = 1,
    parameter bit AUTO_RESET = 0,
    parameter bit [DATA_WIDTH-1:0] AUTO_RESET_VALUE = '0
)(
    input wire clk, 
    input wire rst,

    input  wire                   write_enable,
    input  wire  [ADDR_WIDTH-1:0] write_addr,
    input  wire  [DATA_WIDTH-1:0] write_data_in,
    output logic [DATA_WIDTH-1:0] write_data_out,

    input  wire  [READ_PORTS-1:0] [ADDR_WIDTH-1:0] read_addr,
    output logic [READ_PORTS-1:0] [DATA_WIDTH-1:0] read_data_out,

    output logic reset_done
);

    logic                  write_enable_internal;
    logic [ADDR_WIDTH-1:0] write_addr_internal;
    logic [DATA_WIDTH-1:0] write_data_in_internal;

    generate
    if (AUTO_RESET) begin

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

        always_comb begin
            clear_reset_state = (current_reset_counter == {ADDR_WIDTH{1'b1}});
            next_reset_counter = current_reset_counter + 'b1;
            reset_done = (current_reset_state == 0);

            if (current_reset_state) begin
                write_enable_internal = 1'b1;
                write_addr_internal = current_reset_counter;
                write_data_in_internal = AUTO_RESET_VALUE;
            end else begin
                write_enable_internal = write_enable;
                write_addr_internal = write_addr;
                write_data_in_internal = write_data_in;
            end
        end

    end else begin

        always_comb begin
            reset_done = 'b1;

            write_enable_internal = write_enable;
            write_addr_internal = write_addr;
            write_data_in_internal = write_data_in;
        end

    end
    endgenerate

    // TODO: Fix ASIC latch RAM and verilator
    // generate
    // // Only try the latch-RAM if it is wide enough to justify it 
    // if ((TECHNOLOGY == STD_TECHNOLOGY_ASIC_TSMC || 
    //         TECHNOLOGY == STD_TECHNOLOGY_ASIC_INTEL) &&
    //         DATA_WIDTH > 8) begin

    //     asic_latch_ram #(
    //         .CLOCK_INFO(CLOCK_INFO),
    //         .TECHNOLOGY(TECHNOLOGY),
    //         .DATA_WIDTH(DATA_WIDTH),
    //         .ADDR_WIDTH(ADDR_WIDTH),
    //         .READ_PORTS(READ_PORTS)
    //     ) asic_latch_ram_inst (
    //         .clk, .rst,

    //         .write_enable(write_enable_internal),
    //         .write_addr(write_addr_internal),
    //         .write_data_in(write_data_in_internal),
    //         .write_data_out,
    //         .read_addr, 
    //         .read_data_out
    //     );

    // end else begin // TECHNOLOGY == STD_TECHNOLOGY_FPGA_XILINX

    // end
    // endgenerate

    // Just use inferred distributed RAM for any FPGA technology
    // TODO: Verify Intel FPGAs supports this format
    xilinx_distributed_ram #(
        .CLOCK_INFO(CLOCK_INFO),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .READ_PORTS(READ_PORTS)
    ) xilinx_distributed_ram_inst (
        .clk, .rst,

        // Only using single-bit write enable for this module,
        // manually use the distributed RAM module for more
        // granularity
        .write_enable({DATA_WIDTH{write_enable_internal}}),
        .write_addr(write_addr_internal),
        .write_data_in(write_data_in_internal),
        .write_data_out,
        .read_addr, 
        .read_data_out
    );

endmodule
