`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/gecko/gecko.svh"
`include "../../lib/gecko/gecko_decode_util.svh"

`else

`include "std_util.svh"
`include "std_mem.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32i.svh"
`include "gecko.svh"
`include "gecko_decode_util.svh"

`endif

/*
 * A round-robin (maybe?) scheduler for producing commands to write back to the
 * register file, one result at a time. The writeback stage also implements
 * the logic necessary to align a value read from memory according to halfword
 * or byte boundaries.
 *
 * A result is not accepted unless its reg_status matches the current
 * reg_status for that result, in order to preserve ordering.
 */
module gecko_writeback
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
    import gecko_decode_util::*;
#(
    parameter int PORTS = 1
)(
    input logic clk, rst,

    std_stream_intf.in writeback_results_in [PORTS], // gecko_operation_t

    std_stream_intf.out writeback_result // gecko_operation_t
);

    // Check that status counter can count up to the number
    // of independent input streams to the writeback module
    `STATIC_ASSERT($pow(2, $size(gecko_reg_status_t)) >= 3)

    typedef enum logic {
        GECKO_WRITEBACK_RESET = 1'b0,
        GECKO_WRITEBACK_NORMAL = 1'b1
    } gecko_writeback_state_t;

    logic [PORTS-1:0] results_in_valid, results_in_ready;
    gecko_operation_t results_in_operation [PORTS];

    generate
    genvar k;
    for (k = 0; k < PORTS; k++) begin
        always_comb begin
            results_in_valid[k] = writeback_results_in[k].valid;
            results_in_operation[k] = writeback_results_in[k].payload;
            writeback_results_in[k].ready = results_in_ready[k];
        end
    end
    endgenerate

    logic enable;
    logic [PORTS-1:0] consume;
    logic produce;

    // Flow Controller
    std_flow #(
        .NUM_INPUTS(PORTS),
        .NUM_OUTPUTS(1)
    ) std_flow_inst (
        .clk, .rst,

        .valid_input(results_in_valid),
        .ready_input(results_in_ready),

        .valid_output({writeback_result.valid}),
        .ready_output({writeback_result.ready}),

        .produce, .consume, .enable
    );

    logic status_write_enable;
    rv32_reg_addr_t status_write_addr;
    gecko_reg_status_t status_write_value;

    rv32_reg_addr_t status_read_addr [PORTS];
    gecko_reg_status_t reg_status [PORTS];

    // Local Register File Status
    localparam GECKO_REG_STATUS_WIDTH = $size(gecko_reg_status_t);
    std_distributed_ram #(
        .DATA_WIDTH(GECKO_REG_STATUS_WIDTH),
        .ADDR_WIDTH($size(rv32_reg_addr_t)),
        .READ_PORTS(PORTS)
    ) register_status_counters_inst (
        .clk, .rst,

        // Always write to all bits in register, gate with state clock enable
        .write_enable({GECKO_REG_STATUS_WIDTH{status_write_enable && enable}}),
        .write_addr(status_write_addr),
        .write_data_in(status_write_value),

        .read_addr(status_read_addr),
        .read_data_out(reg_status)
    );

    gecko_writeback_state_t current_state, next_state;
    rv32_reg_addr_t current_counter, next_counter;

    gecko_operation_t next_writeback_result;

    always_ff @(posedge clk) begin
        if(rst) begin
            current_state <= GECKO_WRITEBACK_RESET;
            current_counter <= 'b0;
        end else if (enable) begin
            current_state <= next_state;
            current_counter <= next_counter;
        end

        if (enable) begin
            writeback_result.payload <= next_writeback_result;
        end
    end

    always_comb begin
        automatic logic [PORTS-1:0] status_good;

        // Read local register file status flags
        for (int i = 0; i < PORTS; i++) begin
            status_read_addr[i] = results_in_operation[i].addr;
        end

        // Find if input matches current ordering to accept it
        for (int i = 0; i < PORTS; i++) begin
            status_good[i] = (reg_status[i] == results_in_operation[i].reg_status);
        end

        next_state = current_state;
        next_counter = current_counter + 'b1;

        status_write_enable = 'b0;
        status_write_addr = current_counter;
        status_write_value = 'b0;

        consume = 'b0;

        next_writeback_result = '{default: 'b0};

        // Round-Robin input selection
        case (current_state)
        GECKO_WRITEBACK_RESET: begin
            status_write_enable = 'b1;
            if (next_counter == 'b0) begin
                next_state = GECKO_WRITEBACK_NORMAL;
            end else begin
                next_state = GECKO_WRITEBACK_RESET;
            end
        end
        GECKO_WRITEBACK_NORMAL: begin
            for (int i = 0; i < PORTS; i++) begin
                if (results_in_valid[i] && status_good[i]) begin
                    consume[i] = 'b1;
                    next_writeback_result = results_in_operation[i];
                    break;
                end
            end
        end
        endcase

        produce = (|consume);

        // Update local register file status
        if (produce) begin
            status_write_enable = 'b1;
            status_write_addr = next_writeback_result.addr;
            status_write_value = next_writeback_result.reg_status + 'b1;
        end
    end

endmodule
