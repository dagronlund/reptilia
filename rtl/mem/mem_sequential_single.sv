//!import std/std_pkg
//!import std/std_register
//!import stream/stream_pkg
//!import xilinx/xilinx_block_ram_single

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

`timescale 1ns/1ps

module mem_sequential_single 
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter int MANUAL_ADDR_WIDTH = 0, // Set other than zero to override
    parameter int ADDR_BYTE_SHIFTED = 0,
    parameter int ENABLE_OUTPUT_REG = 0,
    parameter HEX_FILE = ""
)(
    input wire clk, 
    input wire rst,

    mem_intf.in mem_in,
    mem_intf.out mem_out
);

    `STATIC_MATCH_MEM(mem_in, mem_out)
    `STATIC_ASSERT((ADDR_BYTE_SHIFTED == 0) || ($bits(mem_in.data) > 8))

    localparam int DATA_WIDTH = $bits(mem_in.data);
    localparam int ID_WIDTH = $bits(mem_in.id);
    localparam int MASK_WIDTH = DATA_WIDTH / 8;
    localparam int ADDR_CORRECTION = (ADDR_BYTE_SHIFTED == 0) ? 0 : $clog2(MASK_WIDTH);
    localparam int ADDR_DEFAULT = (MANUAL_ADDR_WIDTH == 0) ? $bits(mem_in.addr) : MANUAL_ADDR_WIDTH;
    localparam int ADDR_WIDTH = ADDR_DEFAULT - ADDR_CORRECTION;
    localparam int DATA_LENGTH = 2**ADDR_WIDTH;

    // Custom flow control is used here since in most SRAMs new values cannot be written without
    // changing the prior read values
    logic enable, enable_output;

    generate
    if (TECHNOLOGY == STD_TECHNOLOGY_FPGA_XILINX) begin

        xilinx_block_ram_single #(
            .CLOCK_INFO(CLOCK_INFO),
            .DATA_WIDTH(DATA_WIDTH),
            .ADDR_WIDTH(ADDR_WIDTH),
            .ENABLE_OUTPUT_REG(ENABLE_OUTPUT_REG),
            .HEX_FILE(HEX_FILE)
        ) xilinx_block_ram_single_inst (
            .clk, .rst,
            // Avoid writing to memory values during reset, since the memory values are not reset
            .enable(!std_is_reset_active(CLOCK_INFO, rst) && enable),
            .enable_output(enable_output),
            .write_enable(mem_in.write_enable),
            .addr_in(mem_in.addr[ADDR_DEFAULT-1:ADDR_CORRECTION]),
            .data_in(mem_in.data),
            .data_out(mem_out.data)
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

            internal_ready = mem_out.ready || !mem_out.valid;
            mem_in.ready = internal_ready || !internal_valid;

            enable = mem_in.valid && mem_in.ready;
            enable_output = internal_valid && internal_ready;

            next_internal_valid = enable && mem_in.read_enable;
            next_output_valid = enable_output;

            enable_internal_valid = enable || internal_ready;
            enable_output_valid = enable_output || mem_out.ready;
        end

        // Valid Registers
        std_register #(.CLOCK_INFO(CLOCK_INFO), .T(logic), .RESET_VECTOR('b0)) valid_internal_reg_inst (.clk, .rst, .enable(enable_internal_valid), .next(next_internal_valid), .value(internal_valid));
        std_register #(.CLOCK_INFO(CLOCK_INFO), .T(logic), .RESET_VECTOR('b0)) valid_output_reg_inst (.clk, .rst, .enable(enable_output_valid), .next(next_output_valid), .value(mem_out.valid));
        // ID Registers
        std_register #(.CLOCK_INFO(CLOCK_INFO), .T(logic[ID_WIDTH-1:0]), .RESET_VECTOR('b0)) id_internal_reg_inst (.clk, .rst, .enable, .next(mem_in.id), .value(internal_id));
        std_register #(.CLOCK_INFO(CLOCK_INFO), .T(logic[ID_WIDTH-1:0]), .RESET_VECTOR('b0)) id_output_reg_inst (.clk, .rst, .enable(enable_output), .next(internal_id), .value(mem_out.id));
        // Last Registers
        std_register #(.CLOCK_INFO(CLOCK_INFO), .T(logic), .RESET_VECTOR('b0)) last_internal_reg_inst (.clk, .rst, .enable, .next(mem_in.last), .value(internal_last));
        std_register #(.CLOCK_INFO(CLOCK_INFO), .T(logic), .RESET_VECTOR('b0)) last_output_reg_inst (.clk, .rst, .enable(enable_output), .next(internal_last), .value(mem_out.last));

    end else begin

        always_comb begin
            mem_in.ready = mem_out.ready || !mem_out.valid;
            enable = mem_in.valid && mem_in.ready;
            enable_output = 'b1;
        end

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) valid_reg_inst (
            .clk, .rst,
            .enable(enable || mem_out.ready),
            .next(enable && mem_in.read_enable),
            .value(mem_out.valid)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic[ID_WIDTH-1:0]),
            .RESET_VECTOR('b0)
        ) id_reg_inst (
            .clk, .rst,
            .enable,
            .next(mem_in.id),
            .value(mem_out.id)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) last_reg_inst (
            .clk, .rst,
            .enable,
            .next(mem_in.last),
            .value(mem_out.last)
        );

    end
    endgenerate

endmodule
