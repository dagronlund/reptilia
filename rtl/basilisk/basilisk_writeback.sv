`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/fpu/fpu.svh"
`include "../../lib/basilisk/basilisk.svh"

`else

`include "std_util.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32f.svh"
`include "basilisk.svh"
`include "fpu.svh"

`endif

module basilisk_writeback
    import rv::*;
    import rv32::*;
    import rv32f::*;
    import fpu::*;
    import basilisk::*;
#(
    parameter int OUTPUT_REGISTER_MODE = 1,
    parameter int PORTS = 1
)(
    input logic clk, rst,

    std_stream_intf.in writeback_results_in [PORTS], // basilisk_result_t
    std_stream_intf.out writeback_result // basilisk_writeback_result_t
);

    std_stream_intf #(.T(basilisk_writeback_result_t)) next_writeback_result (.clk, .rst);

    logic [PORTS-1:0] results_in_valid, results_in_ready;
    basilisk_result_t results_in [PORTS];

    generate
    genvar k;
    for (k = 0; k < PORTS; k++) begin
        always_comb begin
            results_in_valid[k] = writeback_results_in[k].valid;
            results_in[k] = writeback_results_in[k].payload;
            writeback_results_in[k].ready = results_in_ready[k];
        end
    end
    endgenerate

    logic enable;
    logic [PORTS-1:0] consume;
    logic produce;

    std_flow_lite #(
        .NUM_INPUTS(PORTS),
        .NUM_OUTPUTS(1)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input(results_in_valid),
        .ready_input(results_in_ready),

        .valid_output({next_writeback_result.valid}),
        .ready_output({next_writeback_result.ready}),

        .consume, .produce, .enable
    );

    std_flow_stage #(
        .T(basilisk_writeback_result_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) output_stage_inst (
        .clk, .rst,
        .stream_in(next_writeback_result), .stream_out(writeback_result)
    );

    parameter int COUNTER_WIDTH = ($clog2(PORTS) > 0) ? $clog2(PORTS) : 1;
    typedef logic [COUNTER_WIDTH-1:0] counter_t;

    function automatic counter_t increment_counter(
        input counter_t counter
    );
        if (counter + 'b1 >= PORTS) begin
            return 'b0;
        end else begin
            return counter + 'b1;
        end
    endfunction 

    counter_t current_counter, next_counter;

    always_ff @(posedge clk) begin
        if(rst) begin
            current_counter <= 'b0;
        end else if (enable) begin
            current_counter <= next_counter;
        end
    end

    always_comb begin
        automatic counter_t iterated_counter;
        automatic fpu_result_t chosen_result;
        automatic rv32_reg_addr_t chosen_dest_reg_addr;
        automatic basilisk_offset_addr_t chosen_dest_offset_addr;

        consume = 'b0;
        produce = 'b1;
        next_counter = increment_counter(current_counter);

        iterated_counter = current_counter;

        // Always try to consume something
        consume[iterated_counter] = 'b1;

        for (int i = 0; i < PORTS; i++) begin
            if (results_in_valid[iterated_counter]) begin
                consume = 'b0;
                consume[iterated_counter] = 'b1;
                break;
            end
            iterated_counter = increment_counter(iterated_counter);
        end

        next_writeback_result.payload.dest_reg_addr = results_in[iterated_counter].dest_reg_addr;
        next_writeback_result.payload.dest_offset_addr = results_in[iterated_counter].dest_offset_addr;
        next_writeback_result.payload.result = fpu_decode_float(fpu_operations_round(
                results_in[iterated_counter].result
        ));

    end

endmodule
