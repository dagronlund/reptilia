//!import std/std_pkg
//!import std/std_register
//!import xilinx/xilinx_block_ram_simple

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

`timescale 1ns/1ps

module mem_sequential_read_write
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter int MANUAL_ADDR_WIDTH = 0, // Set other than zero to override
    parameter int ENABLE_OUTPUT_REG = 0,
    parameter HEX_FILE = ""
)(
    input wire clk, 
    input wire rst,

    mem_intf.in mem_read_in,
    mem_intf.out mem_read_out,

    mem_intf.in mem_write_in
);

    `STATIC_MATCH_MEM(mem_read_in, mem_read_out)
    `STATIC_MATCH_MEM(mem_read_in, mem_write_in)

    localparam int DATA_WIDTH = $bits(mem_read_in.data);
    localparam int ID_WIDTH = $bits(mem_read_in.id);
    localparam int ADDR_WIDTH = (MANUAL_ADDR_WIDTH == 0) ? $bits(mem_read_in.addr) : MANUAL_ADDR_WIDTH;
    localparam int DATA_LENGTH = 2**ADDR_WIDTH;

    // Custom flow control is used here since in most SRAMs new values cannot be written without
    // changing the prior read values
    logic write_enable, read_enable, read_output_enable;

    // Nothing can backflow the write channel so its always ready
    assign mem_write_in.ready = 'b1;
    assign write_enable = mem_write_in.valid;

    generate
    if (TECHNOLOGY == STD_TECHNOLOGY_FPGA_XILINX) begin

        xilinx_block_ram_simple #(
            .CLOCK_INFO(CLOCK_INFO),
            .DATA_WIDTH(DATA_WIDTH),
            .ADDR_WIDTH(ADDR_WIDTH),
            .ENABLE_OUTPUT_REG(ENABLE_OUTPUT_REG),
            .HEX_FILE(HEX_FILE)
        ) xilinx_block_ram_simple_inst (
            .clk, .rst,

            .write_enable(!std_is_reset_active(CLOCK_INFO, rst) && write_enable),
            .write_addr(mem_write_in.addr),
            .write_data(mem_write_in.data),

            .read_enable(!std_is_reset_active(CLOCK_INFO, rst) && read_enable),
            .read_output_enable(read_output_enable),
            .read_addr(mem_read_in.addr),
            .read_data(mem_read_out.data)
        );

    end else begin
        // TODO: Implement other memory technologies
        `PROCEDURAL_ASSERT(0)
    end

    if (ENABLE_OUTPUT_REG) begin

        logic internal_valid;
        logic [ID_WIDTH-1:0] internal_id;
        logic internal_last;

        logic enable_internal_valid, enable_output_valid;
        logic next_internal_valid, next_output_valid;

        always_comb begin
            automatic logic internal_ready;

            internal_ready = mem_read_out.ready || !mem_read_out.valid;
            mem_read_in.ready = internal_ready || !internal_valid;

            read_enable = mem_read_in.valid && mem_read_in.ready;
            read_output_enable = internal_valid && internal_ready;

            next_internal_valid = read_enable;
            next_output_valid = read_output_enable;

            enable_internal_valid = read_enable || internal_ready;
            enable_output_valid = read_output_enable || mem_read_out.ready;
        end

        // Valid Registers
        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) valid_internal_reg_inst (
            .clk, .rst,
            .enable(enable_internal_valid),
            .next(next_internal_valid),
            .value(internal_valid)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) valid_output_reg_inst (
            .clk, .rst,
            .enable(enable_output_valid),
            .next(next_output_valid),
            .value(mem_read_out.valid)
        );

        // ID Registers
        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic[ID_WIDTH-1:0]),
            .RESET_VECTOR('b0)
        ) id_internal_reg_inst (
            .clk, .rst,
            .enable(read_enable),
            .next(mem_read_in.id),
            .value(internal_id)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic[ID_WIDTH-1:0]),
            .RESET_VECTOR('b0)
        ) id_output_reg_inst (
            .clk, .rst,
            .enable(read_output_enable),
            .next(internal_id),
            .value(mem_read_out.id)
        );

        // Last Registers
        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) last_internal_reg_inst (
            .clk, .rst,
            .enable(read_enable),
            .next(mem_read_in.last),
            .value(internal_last)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) last_output_reg_inst (
            .clk, .rst,
            .enable(read_output_enable),
            .next(internal_last),
            .value(mem_read_out.last)
        );

    end else begin

        always_comb begin
            mem_read_in.ready = mem_read_out.ready || !mem_read_out.valid;
            read_enable = mem_read_in.valid && mem_read_in.ready;
            read_output_enable = 'b1;
        end

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) valid_reg_inst (
            .clk, .rst,
            .enable(read_enable || mem_read_out.ready),
            .next(read_enable),
            .value(mem_read_out.valid)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic[ID_WIDTH-1:0]),
            .RESET_VECTOR('b0)
        ) id_reg_inst (
            .clk, .rst,
            .enable(read_enable),
            .next(mem_read_in.id),
            .value(mem_read_out.id)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) last_reg_inst (
            .clk, .rst,
            .enable(read_enable),
            .next(mem_read_in.last),
            .value(mem_read_out.last)
        );

    end

    endgenerate

endmodule
