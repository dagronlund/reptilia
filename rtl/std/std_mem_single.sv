`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`else

`include "std_util.svh"
`include "std_mem.svh"

`endif

/*
 * Implements a single cycle memory with an input stream for commands and an 
 * output stream for the results of those commands. Enabling the output 
 * stage immediately after this will allow for the block memory output 
 * register to be used.
 */ 
module std_mem_single #(
    parameter int MANUAL_ADDR_WIDTH = 0, // Set other than zero to override
    parameter int ADDR_BYTE_SHIFTED = 0,
    parameter int ENABLE_OUTPUT_REG = 0,
    parameter HEX_FILE = ""
)(
    input logic clk, rst,
    std_mem_intf.in command, // Inbound Commands
    std_mem_intf.out result // Outbound Results
);

    `STATIC_MATCH_MEM(command, result)
    `STATIC_ASSERT((ADDR_BYTE_SHIFTED == 0) || ($bits(command.data) > 8))

    localparam DATA_WIDTH = $bits(command.data);
    localparam ID_WIDTH = $bits(command.id);
    localparam MASK_WIDTH = DATA_WIDTH / 8;
    localparam ADDR_CORRECTION = (ADDR_BYTE_SHIFTED == 0) ? 0 : $clog2(MASK_WIDTH);
    localparam ADDR_DEFAULT = (MANUAL_ADDR_WIDTH == 0) ? 
            $bits(command.addr) : MANUAL_ADDR_WIDTH;
    localparam ADDR_WIDTH = ADDR_DEFAULT - ADDR_CORRECTION;
    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    /*
     * Custom flow control is used here since the block RAM cannot be written
     * to without changing the read value.
     */
    logic enable, enable_output;

    std_block_ram_single #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ENABLE_OUTPUT_REG(ENABLE_OUTPUT_REG),
        .HEX_FILE(HEX_FILE)
    ) std_block_ram_single_inst (
        .clk, .rst,
        // Avoid writing to memory values during reset, since they are not reset
        .enable(!rst && enable),
        .enable_output(enable_output),
        .write_enable(command.write_enable),
        .addr_in(command.addr[ADDR_DEFAULT-1:ADDR_CORRECTION]),
        .data_in(command.data),
        .data_out(result.data)
    );

    generate
    if (ENABLE_OUTPUT_REG) begin

        logic internal_valid, internal_ready;
        logic [ID_WIDTH-1:0] internal_id;

        always_ff @ (posedge clk) begin
            if (rst) begin
                internal_valid <= 'b0;
            end else if (enable) begin
                internal_valid <= command.read_enable;
            end else if (internal_ready) begin
                internal_valid <= 'b0;
            end
        end

        always_comb begin
            command.ready = internal_ready || !internal_valid;
            enable = command.valid && command.ready;
        end

        logic enable_output_null;
        std_flow #(
            .NUM_INPUTS(1),
            .NUM_OUTPUTS(1)
        ) output_register_flow_inst (
            .clk, .rst,

            .valid_input(internal_valid),
            .ready_input(internal_ready),

            .valid_output(result.valid),
            .ready_output(result.ready),

            .consume('b1), .produce('b1),
            .enable(enable_output), .enable_output(enable_output_null)
        );

        always_ff @ (posedge clk) begin
            if (enable) begin
                internal_id <= command.id;
            end
            if (enable_output) begin
                result.id <= internal_id;
            end
        end

    end else begin
        assign enable_output = 'b1;
    
        always_ff @ (posedge clk) begin
            if (rst) begin
                result.valid <= 'b0;
            end else if (enable) begin
                result.valid <= command.read_enable;
            end else if (result.ready) begin
                result.valid <= 'b0;
            end
        end

        always_comb begin
            command.ready = result.ready || !result.valid;
            enable = command.valid && command.ready;
        end

        always_ff @ (posedge clk) begin
            if (enable) begin
                result.id <= command.id;
            end
        end
    end
    endgenerate

endmodule
