`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "../mem/mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

module gecko_core_wrapper
    // import std_pkg::*;
    // import stream_pkg::*;
    // import riscv_pkg::*;
    // import riscv32_pkg::*;
    // import riscv32i_pkg::*;
    // import gecko_pkg::*;
#(
    // parameter std_clock_info_t CLOCK_INFO = 'b0,
    // parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    // parameter stream_pipeline_mode_t FETCH_PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,
    // parameter stream_pipeline_mode_t INST_MEMORY_PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,
    // parameter stream_pipeline_mode_t DECODE_PIPELINE_MODE = STREAM_PIPELINE_MODE_BUFFERED,
    // parameter stream_pipeline_mode_t EXECUTE_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    // parameter stream_pipeline_mode_t SYSTEM_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    // parameter stream_pipeline_mode_t PRINT_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    // parameter stream_pipeline_mode_t WRITEBACK_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    // parameter int INST_LATENCY = 1,
    // parameter int DATA_LATENCY = 1,
    // parameter int FLOAT_LATENCY = 1,
    // parameter gecko_pc_t START_ADDR = 'b0,
    // parameter int ENABLE_PERFORMANCE_COUNTERS = 1,
    // parameter int ENABLE_BRANCH_PREDICTOR = 1,
    // parameter int BRANCH_PREDICTOR_ADDR_WIDTH = 5,
    // parameter int ENABLE_PRINT = 1,
    // parameter int ENABLE_FLOAT = 0,
    // parameter int ENABLE_INTEGER_MATH = 0
)(
    input logic clk, rst,


    // mem_intf.out inst_request,
    // mem_intf.in inst_result,

    output logic        inst_request_valid,
    input  wire         inst_request_ready,
    output logic        inst_request_read_enable,
    output logic        inst_request_write_enable,
    output logic [31:0] inst_request_addr,
    output logic [31:0] inst_request_data,
    output logic        inst_request_id,

    input  wire        inst_result_valid,
    output logic       inst_result_ready,
    input  wire        inst_result_read_enable,
    input  wire        inst_result_write_enable,
    input  wire [31:0] inst_result_addr,
    input  wire [31:0] inst_result_data,
    input  wire        inst_result_id,

    // mem_intf.out data_request,
    // mem_intf.in data_result,

    output logic        data_request_valid,
    input  wire         data_request_ready,
    output logic        data_request_read_enable,
    output logic        data_request_write_enable,
    output logic [31:0] data_request_addr,
    output logic [31:0] data_request_data,
    output logic        data_request_id,

    input  wire        data_result_valid,
    output logic       data_result_ready,
    input  wire        data_result_read_enable,
    input  wire        data_result_write_enable,
    input  wire [31:0] data_result_addr,
    input  wire [31:0] data_result_data,
    input  wire        data_result_id,

    // mem_intf.out float_mem_request,
    // mem_intf.in float_mem_result,

    output logic        float_mem_request_valid,
    input  wire         float_mem_request_ready,
    output logic        float_mem_request_read_enable,
    output logic        float_mem_request_write_enable,
    output logic [31:0] float_mem_request_addr,
    output logic [31:0] float_mem_request_data,
    output logic        float_mem_request_id,

    input  wire        float_mem_result_valid,
    output logic       float_mem_result_ready,
    input  wire        float_mem_result_read_enable,
    input  wire        float_mem_result_write_enable,
    input  wire [31:0] float_mem_result_addr,
    input  wire [31:0] float_mem_result_data,
    input  wire        float_mem_result_id,

    // logic valid, ready;
    // logic                  read_enable;
    // logic [MASK_WIDTH-1:0] write_enable;
    // logic [ADDR_WIDTH-1:0] addr;
    // logic [DATA_WIDTH-1:0] data;
    // logic [ID_WIDTH-1:0]   id;

    output logic print_out_valid,
    input wire print_out_ready,
    output logic [7:0] print_out_data,

    output logic faulted_flag, finished_flag
);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_result (.clk, .rst);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) data_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) data_result (.clk, .rst);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) float_mem_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) float_mem_result (.clk, .rst);

    stream_intf #(.T(logic [7:0])) print_out (.clk, .rst);

    gecko_core #(
    ) gecko_core_inst (
        .clk, .rst,

        .inst_request,
        .inst_result,
        .data_request,
        .data_result,
        .float_mem_request,
        .float_mem_result,

        .print_out,

        .faulted_flag, .finished_flag
    );

    always_comb begin

        inst_request_valid = inst_request.valid;
        inst_request.ready = inst_request_ready;
        inst_request_read_enable = inst_request.read_enable;
        inst_request_write_enable = inst_request.write_enable;
        inst_request_addr = inst_request.addr;
        inst_request_data = inst_request.data;
        inst_request_id = inst_request.id;

        inst_result.valid = inst_result_valid;
        inst_result_ready = inst_result.ready;
        inst_result.read_enable = inst_result_read_enable;
        inst_result.write_enable = inst_result_write_enable;
        inst_result.addr = inst_result_addr;
        inst_result.data = inst_result_data;
        inst_result.id = inst_result_id;



        data_request_valid = data_request.valid;
        data_request.ready = data_request_ready;
        data_request_read_enable = data_request.read_enable;
        data_request_write_enable = data_request.write_enable;
        data_request_addr = data_request.addr;
        data_request_data = data_request.data;
        data_request_id = data_request.id;

        data_result.valid = data_result_valid;
        data_result_ready = data_result.ready;
        data_result.read_enable = data_result_read_enable;
        data_result.write_enable = data_result_write_enable;
        data_result.addr = data_result_addr;
        data_result.data = data_result_data;
        data_result.id = data_result_id;



        float_mem_request_valid = float_mem_request.valid;
        float_mem_request.ready = float_mem_request_ready;
        float_mem_request_read_enable = float_mem_request.read_enable;
        float_mem_request_write_enable = float_mem_request.write_enable;
        float_mem_request_addr = float_mem_request.addr;
        float_mem_request_data = float_mem_request.data;
        float_mem_request_id = float_mem_request.id;

        float_mem_result.valid = float_mem_result_valid;
        float_mem_result_ready = float_mem_result.ready;
        float_mem_result.read_enable = float_mem_result_read_enable;
        float_mem_result.write_enable = float_mem_result_write_enable;
        float_mem_result.addr = float_mem_result_addr;
        float_mem_result.data = float_mem_result_data;
        float_mem_result.id = float_mem_result_id;



        print_out_valid = print_out.valid;
        print_out.ready = print_out_ready;
        print_out_data = print_out.payload;

    end

endmodule
