`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`else

`include "std_util.svh"
`include "std_mem.svh"

`endif

/*
 * Implements a single cycle memory with two input streams for commands and two
 * output streams for the results of those commands. Adding a single register 
 * stage immediately after this will allow for the block memory output 
 * register to be used.
 */
module std_mem_double #(
    parameter int MANUAL_ADDR_WIDTH = 0, // Set other than zero to override
    parameter int ADDR_BYTE_SHIFTED = 0,
    parameter int ENABLE_OUTPUT_REG0 = 0,
    parameter int ENABLE_OUTPUT_REG1 = 0,
    parameter HEX_FILE = ""
)(
    input logic clk, rst,
    std_mem_intf.in command0, command1, // Inbound Commands
    std_mem_intf.out result0, result1 // Outbound Results
);

    `STATIC_MATCH_MEM(command0, result0)
    `STATIC_MATCH_MEM(command0, command1)
    `STATIC_MATCH_MEM(command0, result1)
    `STATIC_ASSERT((ADDR_BYTE_SHIFTED == 0) || ($bits(command0.data) > 8))

    localparam DATA_WIDTH = $bits(command0.data);
    localparam ID_WIDTH = $bits(command0.id);
    localparam MASK_WIDTH = DATA_WIDTH / 8;
    localparam ADDR_CORRECTION = (ADDR_BYTE_SHIFTED == 0) ? 0 : $clog2(MASK_WIDTH);
    localparam ADDR_DEFAULT = (MANUAL_ADDR_WIDTH == 0) ?
            $bits(command0.addr) : MANUAL_ADDR_WIDTH;
    localparam ADDR_WIDTH = ADDR_DEFAULT - ADDR_CORRECTION;
    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    /*
     * Custom flow control is used here since the block RAM cannot be written
     * to without changing the read value.
     */
    logic enable0, enable1, enable_output0, enable_output1;

    std_block_ram_double #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ENABLE_OUTPUT_REG0(ENABLE_OUTPUT_REG0),
        .ENABLE_OUTPUT_REG1(ENABLE_OUTPUT_REG1),
        .HEX_FILE(HEX_FILE)
    ) std_block_ram_double_inst (
        .clk, .rst,
        // Avoid writing to memory values during reset, since they are not reset
        .enable0(!rst && enable0),
        .enable_output0(enable_output0),
        .write_enable0(command0.write_enable),
        .addr_in0(command0.addr[ADDR_DEFAULT-1:ADDR_CORRECTION]),
        .data_in0(command0.data),
        .data_out0(result0.data),

        // Avoid writing to memory values during reset, since they are not reset
        .enable1(!rst && enable1),
        .enable_output1(enable_output1),
        .write_enable1(command1.write_enable),
        .addr_in1(command1.addr[ADDR_DEFAULT-1:ADDR_CORRECTION]),
        .data_in1(command1.data),
        .data_out1(result1.data)
    );

    generate
    if (ENABLE_OUTPUT_REG0) begin

        logic internal_valid, internal_ready;
        logic [ID_WIDTH-1:0] internal_id;

        always_ff @ (posedge clk) begin
            if (rst) begin
                internal_valid <= 'b0;
            end else if (enable0) begin
                internal_valid <= command0.read_enable;
            end else if (internal_ready) begin
                internal_valid <= 'b0;
            end
        end

        always_comb begin
            command0.ready = internal_ready || !internal_valid;
            enable0 = command0.valid && command0.ready;
        end

        logic enable_output_null;
        std_flow #(
            .NUM_INPUTS(1),
            .NUM_OUTPUTS(1)
        ) output_register_flow_inst (
            .clk, .rst,

            .valid_input(internal_valid),
            .ready_input(internal_ready),

            .valid_output(result0.valid),
            .ready_output(result0.ready),

            .consume('b1), .produce('b1),
            .enable(enable_output0), .enable_output(enable_output_null)
        );

        always_ff @ (posedge clk) begin
            if (enable0) begin
                internal_id <= command0.id;
            end
            if (enable_output0) begin
                result0.id <= internal_id;
            end
        end

    end else begin
        assign enable_output0 = 'b1;
    
        always_ff @ (posedge clk) begin
            if (rst) begin
                result0.valid <= 'b0;
            end else if (enable0) begin
                result0.valid <= command0.read_enable;
            end else if (result0.ready) begin
                result0.valid <= 'b0;
            end
        end

        always_comb begin
            command0.ready = result0.ready || !result0.valid;
            enable0 = command0.valid && command0.ready;
        end

        always_ff @ (posedge clk) begin
            if (enable0) begin
                result0.id <= command0.id;
            end
        end
    end
    endgenerate

    generate
    if (ENABLE_OUTPUT_REG1) begin

        logic internal_valid, internal_ready;
        logic [ID_WIDTH-1:0] internal_id;

        always_ff @ (posedge clk) begin
            if (rst) begin
                internal_valid <= 'b0;
            end else if (enable1) begin
                internal_valid <= command1.read_enable;
            end else if (internal_ready) begin
                internal_valid <= 'b0;
            end
        end

        always_comb begin
            command1.ready = internal_ready || !internal_valid;
            enable1 = command1.valid && command1.ready;
        end

        logic enable_output_null;
        std_flow #(
            .NUM_INPUTS(1),
            .NUM_OUTPUTS(1)
        ) output_register_flow_inst (
            .clk, .rst,

            .valid_input(internal_valid),
            .ready_input(internal_ready),

            .valid_output(result1.valid),
            .ready_output(result1.ready),

            .consume('b1), .produce('b1),
            .enable(enable_output1), .enable_output(enable_output_null)
        );

        always_ff @ (posedge clk) begin
            if (enable1) begin
                internal_id <= command1.id;
            end
            if (enable_output1) begin
                result1.id <= internal_id;
            end
        end

    end else begin
        assign enable_output1 = 'b1;
    
        always_ff @ (posedge clk) begin
            if (rst) begin
                result1.valid <= 'b0;
            end else if (enable1) begin
                result1.valid <= command1.read_enable;
            end else if (result1.ready) begin
                result1.valid <= 'b0;
            end
        end

        always_comb begin
            command1.ready = result1.ready || !result1.valid;
            enable1 = command1.valid && command1.ready;
        end

        always_ff @ (posedge clk) begin
            if (enable1) begin
                result1.id <= command1.id;
            end
        end
    end
    endgenerate

endmodule
