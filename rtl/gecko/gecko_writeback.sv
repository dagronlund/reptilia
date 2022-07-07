//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import riscv/riscv32i_pkg.sv
//!import gecko/gecko_pkg.sv
//!import gecko/gecko_decode_pkg.sv
//!import stream/stream_intf.sv
//!import std/std_register.sv
//!import stream/stream_stage.sv
//!import stream/stream_controller.sv
//!import mem/mem_combinational.sv
//!wrapper gecko/gecko_writeback_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

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
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import gecko_pkg::*;
    // import gecko_decode_util_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter int PORTS = 1
)(
    input wire clk, 
    input wire rst,
    stream_intf.in writeback_results_in [PORTS], // gecko_operation_t
    stream_intf.out writeback_result // gecko_operation_t
);

    // Check that status counter can count up to the number
    // of independent input streams to the writeback module
    `STATIC_ASSERT($pow(2, $size(gecko_reg_status_t)) >= 3)

    logic [PORTS-1:0] results_in_valid, results_in_ready;
    gecko_operation_t results_in_operation [PORTS];

    riscv32_reg_addr_t [PORTS-1:0] status_read_addr;

    generate
    genvar k;
    for (k = 0; k < PORTS; k++) begin
        always_comb begin
            results_in_valid[k] = writeback_results_in[k].valid;
            results_in_operation[k] = writeback_results_in[k].payload;
            writeback_results_in[k].ready = results_in_ready[k];
            // Read local register file status flags
            status_read_addr[k] = results_in_operation[k].addr;
        end
    end
    endgenerate

    logic enable;
    logic [PORTS-1:0] consume;
    logic produce;

    stream_intf #(.T(gecko_operation_t)) next_writeback_result (.clk, .rst);

    stream_controller #(
        .NUM_INPUTS(PORTS),
        .NUM_OUTPUTS(1)
    ) stream_controller_inst (
        .clk, .rst,

        .valid_input(results_in_valid),
        .ready_input(results_in_ready),

        .valid_output({next_writeback_result.valid}),
        .ready_output({next_writeback_result.ready}),

        .produce, 
        .consume, 
        .enable
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(gecko_operation_t)
    ) writeback_result_stage_inst (
        .clk, .rst,
        .stream_in(next_writeback_result), 
        .stream_out(writeback_result)
    );

    logic status_write_enable;
    riscv32_reg_addr_t status_write_addr;
    gecko_reg_status_t status_write_value;

    gecko_reg_status_t [PORTS-1:0] reg_status /* verilator isolate_assignments*/;

    // Local Register File Status
    localparam GECKO_REG_STATUS_WIDTH = $bits(gecko_reg_status_t);
    localparam GECKO_REG_STATUS_DEPTH = $bits(riscv32_reg_addr_t);

    logic reset_done;

    mem_combinational #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .DATA_WIDTH(GECKO_REG_STATUS_WIDTH),
        .ADDR_WIDTH(GECKO_REG_STATUS_DEPTH),
        .READ_PORTS(PORTS),
        .AUTO_RESET(1)
    ) register_status_counters_inst (
        .clk, .rst,

        // Always write to all bits in register, gate with state clock enable
        .write_enable(status_write_enable && enable),
        .write_addr(status_write_addr),
        .write_data_in(status_write_value),
        .write_data_out(),

        .read_addr(status_read_addr),
        .read_data_out(reg_status),

        .reset_done
    );

    riscv32_reg_addr_t current_counter, next_counter;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(riscv32_reg_addr_t),
        .RESET_VECTOR('b0)
    ) counter_register_inst (
        .clk, .rst,
        .enable,
        .next(next_counter),
        .value(current_counter)
    );

    logic [PORTS-1:0] status_good;

    always_comb begin
        // Find if input matches current ordering to accept it
        for (int i = 0; i < PORTS; i++) begin
            status_good[i] = (reg_status[i] == results_in_operation[i].reg_status);
        end

        next_counter = current_counter + 'b1;

        status_write_enable = 'b0;
        status_write_addr = current_counter;
        status_write_value = 'b0;

        consume = 'b0;
        next_writeback_result.payload = '{default: 'b0};

        if (reset_done) begin
            for (int i = 0; i < PORTS; i++) begin
                if (results_in_valid[i] && status_good[i]) begin
                    consume[i] = 'b1;
                    next_writeback_result.payload = results_in_operation[i];
                    break;
                end
            end
        end

        // // Round-Robin input selection
        // case (current_state)
        // GECKO_WRITEBACK_RESET: begin
        //     status_write_enable = 'b1;
        //     if (next_counter == 'b0) begin
        //         next_state = GECKO_WRITEBACK_NORMAL;
        //     end else begin
        //         next_state = GECKO_WRITEBACK_RESET;
        //     end
        // end
        // GECKO_WRITEBACK_NORMAL: begin
        //     for (int i = 0; i < PORTS; i++) begin
        //         if (results_in_valid[i] && status_good[i]) begin
        //             consume[i] = 'b1;
        //             next_writeback_result.payload = results_in_operation[i];
        //             break;
        //         end
        //     end
        // end
        // endcase

        produce = (|consume);

        // Update local register file status
        if (produce) begin
            status_write_enable = 'b1;
            status_write_addr = next_writeback_result.payload.addr;
            status_write_value = next_writeback_result.payload.reg_status + 'b1;
        end
    end

endmodule
