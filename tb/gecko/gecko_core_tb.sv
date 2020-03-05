`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "../mem/mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

module gecko_core_tb
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import gecko_pkg::*;
#()();

    localparam std_clock_info_t CLOCK_INFO = 'b0;

    logic clk, rst;
    clk_rst_gen #() clk_rst_gen_inst(.clk, .rst);

    logic faulted_flag, finished_flag;

    stream_intf #(.T(logic [7:0])) print_out (.clk, .rst);
    assign print_out.ready = 'b1;

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_result (.clk, .rst);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) data_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) data_result (.clk, .rst);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) float_mem_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) float_mem_result (.clk, .rst);
    assign float_mem_request.ready = 'b0;
    assign float_mem_result.valid = 'b0;

    gecko_core #(
        .CLOCK_INFO(CLOCK_INFO),
        // parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
        // parameter stream_pipeline_mode_t FETCH_PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,
        // parameter stream_pipeline_mode_t INST_MEMORY_PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,
        // parameter stream_pipeline_mode_t DECODE_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
        // parameter stream_pipeline_mode_t EXECUTE_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
        // parameter stream_pipeline_mode_t SYSTEM_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
        // parameter stream_pipeline_mode_t PRINT_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
        // parameter stream_pipeline_mode_t WRITEBACK_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
        .INST_LATENCY(1),
        .DATA_LATENCY(1),
        .FLOAT_LATENCY(1),
        .START_ADDR('b0),
        .BRANCH_PREDICTOR_TYPE(GECKO_BRANCH_PREDICTOR_GLOBAL),
        .BRANCH_PREDICTOR_TARGET_ADDR_WIDTH(5),
        .BRANCH_PREDICTOR_HISTORY_WIDTH(5),
        // .BRANCH_PREDICTOR_LOCAL_ADDR_WIDTH(7),
        .ENABLE_PERFORMANCE_COUNTERS(1),
        .ENABLE_INTEGER_MATH(1)
    ) gecko_core_inst (
        .clk, .rst,

        .inst_request, .inst_result,
        .data_request, .data_result,
        .float_mem_request, .float_mem_result,

        .print_out,

        .faulted_flag, .finished_flag
    );

    mem_sequential_double #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(STD_TECHNOLOGY_FPGA_XILINX),
        .MANUAL_ADDR_WIDTH(15),
        .ADDR_BYTE_SHIFTED(1),
        .ENABLE_OUTPUT_REG0(0),
        .ENABLE_OUTPUT_REG1(0),
        .HEX_FILE("test.mem")
    ) mem_sequential_double_inst (
        .clk, .rst,
        .mem_in0(inst_request), .mem_out0(inst_result),
        .mem_in1(data_request), .mem_out1(data_result)
    );

    initial begin

        @ (posedge clk);
        while (std_is_reset_active(CLOCK_INFO, rst)) @ (posedge clk);
        $display("Running...");

        while (!finished_flag && !faulted_flag) @ (posedge clk);
        
        @ (posedge clk);
        @ (posedge clk);
        if (finished_flag) begin
            $finish("Success!");
        end else begin
            $fatal("Failure!");
        end
    end

endmodule







