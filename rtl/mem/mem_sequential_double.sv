//!import std/std_pkg.sv
//!import std/std_register.sv
//!import xilinx/xilinx_block_ram_double.sv
//!import mem/mem_intf.sv
//!wrapper mem/mem_sequential_double_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

module mem_sequential_double
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter int MANUAL_ADDR_WIDTH = 0, // Set other than zero to override
    parameter int ADDR_BYTE_SHIFTED = 0,
    parameter bit ENABLE_OUTPUT_REG0 = 0,
    parameter bit ENABLE_OUTPUT_REG1 = 0,
    parameter HEX_FILE = ""
)(
    input wire clk, 
    input wire rst,

    mem_intf.in mem_in0,
    mem_intf.out mem_out0,

    mem_intf.in mem_in1,
    mem_intf.out mem_out1
);

    typedef bit [mem_in0.ADDR_WIDTH-1:0] addr_width_temp_t;
    localparam int INTERNAL_ADDR_WIDTH = $bits(addr_width_temp_t);
    typedef bit [mem_in0.DATA_WIDTH-1:0] data_width_temp_t;
    localparam int DATA_WIDTH = $bits(data_width_temp_t);
    typedef bit [mem_in0.MASK_WIDTH-1:0] mask_width_temp_t;
    localparam int MASK_WIDTH = $bits(mask_width_temp_t);
    typedef bit [mem_in0.ID_WIDTH-1:0] id_width_temp_t;
    localparam int ID_WIDTH = $bits(id_width_temp_t);

    `STATIC_MATCH_MEM(mem_in0, mem_out0)
    `STATIC_MATCH_MEM(mem_in0, mem_in1)
    `STATIC_MATCH_MEM(mem_in0, mem_out1)
    `STATIC_ASSERT((ADDR_BYTE_SHIFTED == 0) || (DATA_WIDTH > 8))

    // localparam int DATA_WIDTH = $bits(mem_in0.data);
    // localparam int ID_WIDTH = $bits(mem_in0.id);
    // localparam int MASK_WIDTH = DATA_WIDTH / 8;
    localparam int ADDR_CORRECTION = (ADDR_BYTE_SHIFTED == 0) ? 0 : $clog2(MASK_WIDTH);
    localparam int ADDR_DEFAULT = (MANUAL_ADDR_WIDTH == 0) ? INTERNAL_ADDR_WIDTH : MANUAL_ADDR_WIDTH;
    localparam int ADDR_WIDTH = ADDR_DEFAULT - ADDR_CORRECTION;
    localparam int DATA_LENGTH = 2**ADDR_WIDTH;

    // Custom flow control is used here since in most SRAMs new values cannot be written without
    // changing the prior read values
    logic enable0, enable1, enable_output0, enable_output1;

    generate
    if (TECHNOLOGY == STD_TECHNOLOGY_FPGA_XILINX) begin

        xilinx_block_ram_double #(
            .CLOCK_INFO(CLOCK_INFO),
            .DATA_WIDTH(DATA_WIDTH),
            .ADDR_WIDTH(ADDR_WIDTH),
            .ENABLE_OUTPUT_REG0(ENABLE_OUTPUT_REG0),
            .ENABLE_OUTPUT_REG1(ENABLE_OUTPUT_REG1),
            .HEX_FILE(HEX_FILE)
        ) xilinx_block_ram_double_inst (
            .clk, .rst,
            // Avoid writing to memory values during reset, since they are not reset
            .enable0(!std_is_reset_active(CLOCK_INFO, rst) && enable0),
            .enable_output0(enable_output0),
            .write_enable0(mem_in0.write_enable),
            .addr_in0(mem_in0.addr[ADDR_DEFAULT-1:ADDR_CORRECTION]),
            .data_in0(mem_in0.data),
            .data_out0(mem_out0.data),

            // Avoid writing to memory values during reset, since they are not reset
            .enable1(!std_is_reset_active(CLOCK_INFO, rst) && enable1),
            .enable_output1(enable_output1),
            .write_enable1(mem_in1.write_enable),
            .addr_in1(mem_in1.addr[ADDR_DEFAULT-1:ADDR_CORRECTION]),
            .data_in1(mem_in1.data),
            .data_out1(mem_out1.data)
        );

    end else begin
        // TODO: Implement other memory technologies
        `PROCEDURAL_ASSERT(0)
    end

    if (ENABLE_OUTPUT_REG0) begin

        logic internal_valid;
        logic [ID_WIDTH-1:0] internal_id;
        logic internal_last;

        logic enable_internal_valid, enable_output_valid;
        logic next_internal_valid, next_output_valid;

        always_comb begin
            automatic logic internal_ready;

            internal_ready = mem_out0.ready || !mem_out0.valid;
            mem_in0.ready = internal_ready || !internal_valid;

            enable0 = mem_in0.valid && mem_in0.ready;
            enable_output0 = internal_valid && internal_ready;

            next_internal_valid = enable0 && mem_in0.read_enable;
            next_output_valid = enable_output0;

            enable_internal_valid = enable0 || internal_ready;
            enable_output_valid = enable_output0 || mem_out0.ready;
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
            .value(mem_out0.valid)
        );

        // ID Registers
        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic[ID_WIDTH-1:0]),
            .RESET_VECTOR('b0)
        ) id_internal_reg_inst (
            .clk, .rst,
            .enable(enable0),
            .next(mem_in0.id),
            .value(internal_id)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic[ID_WIDTH-1:0]),
            .RESET_VECTOR('b0)
        ) id_output_reg_inst (
            .clk, .rst,
            .enable(enable_output0),
            .next(internal_id),
            .value(mem_out0.id)
        );

        // Last Registers
        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) last_internal_reg_inst (
            .clk, .rst,
            .enable(enable0),
            .next(mem_in0.last),
            .value(internal_last)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) last_output_reg_inst (
            .clk, .rst,
            .enable(enable_output0),
            .next(internal_last),
            .value(mem_out0.last)
        );

    end else begin

        always_comb begin
            mem_in0.ready = mem_out0.ready || !mem_out0.valid;
            enable0 = mem_in0.valid && mem_in0.ready;
            enable_output0 = 'b1;
        end

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) valid_reg_inst (
            .clk, .rst,
            .enable(enable0 || mem_out0.ready),
            .next(enable0 && mem_in0.read_enable),
            .value(mem_out0.valid)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic[ID_WIDTH-1:0]),
            .RESET_VECTOR('b0)
        ) id_reg_inst (
            .clk, .rst,
            .enable(enable0),
            .next(mem_in0.id),
            .value(mem_out0.id)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) last_reg_inst (
            .clk, .rst,
            .enable(enable0),
            .next(mem_in0.last),
            .value(mem_out0.last)
        );

    end

    if (ENABLE_OUTPUT_REG1) begin

        logic internal_valid;
        logic [ID_WIDTH-1:0] internal_id;
        logic internal_last;

        logic enable_internal_valid, enable_output_valid;
        logic next_internal_valid, next_output_valid;

        always_comb begin
            automatic logic internal_ready;

            internal_ready = mem_out1.ready || !mem_out1.valid;
            mem_in1.ready = internal_ready || !internal_valid;

            enable1 = mem_in1.valid && mem_in1.ready;
            enable_output1 = internal_valid && internal_ready;

            next_internal_valid = enable1 && mem_in1.read_enable;
            next_output_valid = enable_output1;

            enable_internal_valid = enable1 || internal_ready;
            enable_output_valid = enable_output1 || mem_out1.ready;
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
            .value(mem_out1.valid)
        );

        // ID Registers
        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic[ID_WIDTH-1:0]),
            .RESET_VECTOR('b0)
        ) id_internal_reg_inst (
            .clk, .rst,
            .enable(enable1),
            .next(mem_in1.id),
            .value(internal_id)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic[ID_WIDTH-1:0]),
            .RESET_VECTOR('b0)
        ) id_output_reg_inst (
            .clk, .rst,
            .enable(enable_output1),
            .next(internal_id),
            .value(mem_out1.id)
        );

        // Last Registers
        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) last_internal_reg_inst (
            .clk, .rst,
            .enable(enable1),
            .next(mem_in1.last),
            .value(internal_last)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) last_output_reg_inst (
            .clk, .rst,
            .enable(enable_output1),
            .next(internal_last),
            .value(mem_out1.last)
        );

    end else begin

        always_comb begin
            mem_in1.ready = mem_out1.ready || !mem_out1.valid;
            enable1 = mem_in1.valid && mem_in1.ready;
            enable_output1 = 'b1;
        end

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) valid_reg_inst (
            .clk, .rst,
            .enable(enable1 || mem_out1.ready),
            .next(enable1 && mem_in1.read_enable),
            .value(mem_out1.valid)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic[ID_WIDTH-1:0]),
            .RESET_VECTOR('b0)
        ) id_reg_inst (
            .clk, .rst,
            .enable(enable1),
            .next(mem_in1.id),
            .value(mem_out1.id)
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) last_reg_inst (
            .clk, .rst,
            .enable(enable1),
            .next(mem_in1.last),
            .value(mem_out1.last)
        );

    end
    endgenerate

endmodule
