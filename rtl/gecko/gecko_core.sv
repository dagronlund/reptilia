//!import std/std_pkg
//!import stream/stream_pkg
//!import riscv/riscv_pkg
//!import riscv/riscv32_pkg
//!import riscv/riscv32i_pkg
//!import gecko/gecko_pkg

`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "../mem/mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

module gecko_core
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import gecko_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter stream_pipeline_mode_t FETCH_PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,
    parameter stream_pipeline_mode_t INST_MEMORY_PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,
    parameter stream_pipeline_mode_t DECODE_PIPELINE_MODE = STREAM_PIPELINE_MODE_BUFFERED,
    parameter stream_pipeline_mode_t EXECUTE_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter stream_pipeline_mode_t SYSTEM_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter stream_pipeline_mode_t PRINT_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter stream_pipeline_mode_t WRITEBACK_PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter int INST_LATENCY = 1,
    parameter int DATA_LATENCY = 1,
    parameter int FLOAT_LATENCY = 1,
    parameter gecko_pc_t START_ADDR = 'b0,
    parameter int ENABLE_PERFORMANCE_COUNTERS = 1,
    parameter int ENABLE_BRANCH_PREDICTOR = 1,
    parameter int BRANCH_PREDICTOR_ADDR_WIDTH = 5,
    parameter int ENABLE_PRINT = 1,
    parameter int ENABLE_FLOAT = 0,
    parameter int ENABLE_INTEGER_MATH = 0
)(
    input wire clk, 
    input wire rst,

    mem_intf.out inst_request,
    mem_intf.in inst_result,

    mem_intf.out data_request,
    mem_intf.in data_result,

    mem_intf.out float_mem_request,
    mem_intf.in float_mem_result,

    stream_intf.out print_out,

    output logic faulted_flag, finished_flag
);

    `STATIC_ASSERT($size(inst_request.addr) == 32)
    `STATIC_ASSERT($size(inst_result.data) == 32)

    `STATIC_ASSERT($size(data_request.addr) == 32)
    `STATIC_ASSERT($size(data_result.data) == 32)

    stream_intf #(.T(gecko_jump_operation_t)) jump_command (.clk, .rst);

    stream_intf #(.T(gecko_execute_operation_t)) execute_command (.clk, .rst);
    stream_intf #(.T(gecko_system_operation_t)) system_command (.clk, .rst);
    stream_intf #(.T(gecko_ecall_operation_t)) ecall_command (.clk, .rst);
    stream_intf #(.T(gecko_float_operation_t)) float_command (.clk, .rst);

    stream_intf #(.T(gecko_operation_t)) execute_result (.clk, .rst);
    stream_intf #(.T(gecko_operation_t)) system_result (.clk, .rst);
    stream_intf #(.T(gecko_operation_t)) memory_result (.clk, .rst);
    stream_intf #(.T(gecko_operation_t)) float_result (.clk, .rst);

    stream_intf #(.T(gecko_operation_t)) writeback_result (.clk, .rst);

    stream_intf #(.T(gecko_instruction_operation_t)) instruction_command_in (.clk, .rst);
    stream_intf #(.T(gecko_instruction_operation_t)) instruction_command_out (.clk, .rst);
    stream_intf #(.T(gecko_instruction_operation_t)) instruction_command_break (.clk, .rst);

    stream_intf #(.T(gecko_mem_operation_t)) mem_command_in (.clk, .rst);
    stream_intf #(.T(gecko_mem_operation_t)) mem_command_out (.clk, .rst);

    gecko_retired_count_t retired_instructions;

    assign memory_result.valid = mem_command_out.valid && data_result.valid;
    assign memory_result.payload = gecko_get_load_operation(mem_command_out.payload, data_result.data);
    assign mem_command_out.ready = memory_result.ready;
    assign data_result.ready = memory_result.ready;

    gecko_forwarded_t execute_forwarded;
    gecko_forwarded_t writeback_forwarded;
    gecko_forwarded_t memory_forwarded;

    assign execute_forwarded = gecko_construct_forward(execute_result.valid, execute_result.payload);
    assign writeback_forwarded = gecko_construct_forward(writeback_result.valid, writeback_result.payload);
    assign memory_forwarded = gecko_construct_forward(memory_result.valid, memory_result.payload);

    assign jump_command.ready = 'b1;

    gecko_fetch #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .PIPELINE_MODE(FETCH_PIPELINE_MODE),
        .START_ADDR(START_ADDR),
        .ENABLE_BRANCH_PREDICTOR(ENABLE_BRANCH_PREDICTOR),
        .BRANCH_PREDICTOR_ADDR_WIDTH(BRANCH_PREDICTOR_ADDR_WIDTH)
    ) gecko_fetch_inst (
        .clk, .rst,

        .jump_command,

        .instruction_command(instruction_command_in),
        .instruction_request(inst_request)
    );

    stream_stage_multiple #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_REGISTERED),
        .STAGES(INST_LATENCY),
        .T(gecko_instruction_operation_t)
    ) gecko_inst_stage_inst (
        .clk, .rst,
        .stream_in(instruction_command_in),
        .stream_out(instruction_command_out)
    );

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_result_break (.clk, .rst);

    mem_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(INST_MEMORY_PIPELINE_MODE)
    ) mem_request_output_stage (
        .clk, .rst,
        .mem_in(inst_result), .mem_out(inst_result_break)
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(INST_MEMORY_PIPELINE_MODE),
        .T(gecko_instruction_operation_t)
    ) std_flow_stage_inst (
        .clk, .rst,
        .stream_in(instruction_command_out), .stream_out(instruction_command_break)
    );

    logic exit_flag;
    logic [7:0] exit_code;

    gecko_decode #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .PIPELINE_MODE(DECODE_PIPELINE_MODE),
        .NUM_FORWARDED(3),
        .ENABLE_PRINT(ENABLE_PRINT),
        .ENABLE_FLOAT(ENABLE_FLOAT)
    ) gecko_decode_inst (
        .clk, .rst,

        .instruction_command(instruction_command_break),
        .instruction_result(inst_result_break),

        .system_command,
        .execute_command,
        .float_command,

        .ecall_command,

        .jump_command,

        .writeback_result,

        .forwarded_results('{execute_forwarded, memory_forwarded, writeback_forwarded}),

        .exit_flag, .exit_code,
        // .faulted_flag, .finished_flag, 
        .retired_instructions
    );

    assign finished_flag = exit_flag && (exit_code == 'b0);
    assign faulted_flag = exit_flag && (exit_code != 'b0);

    gecko_execute #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .PIPELINE_MODE(EXECUTE_PIPELINE_MODE),
        .ENABLE_INTEGER_MATH(ENABLE_INTEGER_MATH)
    ) gecko_execute_inst (
        .clk, .rst,

        .execute_command,

        .mem_command(mem_command_in),
        .mem_request(data_request),

        .execute_result,

        .jump_command
    );

    stream_stage_multiple #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_REGISTERED),
        .STAGES(DATA_LATENCY),
        .T(gecko_mem_operation_t)
    ) gecko_data_stage_inst (
        .clk, .rst,
        .stream_in(mem_command_in),
        .stream_out(mem_command_out)
    );

    gecko_system #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .PIPELINE_MODE(SYSTEM_PIPELINE_MODE),
        .ENABLE_PERFORMANCE_COUNTERS(ENABLE_PERFORMANCE_COUNTERS)
    ) gecko_system_inst (
        .clk, .rst,

        .retired_instructions,

        .system_command,
        .system_result
    );

    gecko_print #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .PIPELINE_MODE(PRINT_PIPELINE_MODE)
    ) gecko_print_inst (
        .clk, .rst,
        .ecall_command,
        .print_out
    );

    generate
    if (ENABLE_FLOAT) begin

        // // TODO: Refactor VPU/FPU logic
        // basilisk_vpu #(
        //     .MEMORY_LATENCY(FLOAT_LATENCY)
        // ) basilisk_vpu_inst (
        //     .clk, .rst,
        //     .float_command, .float_result,
        //     .float_mem_request, .float_mem_result
        // );

    end else begin
        assign float_mem_request.valid = 'b0;
        assign float_mem_result.ready = 'b0;
        assign float_command.ready = 'b0;
        assign float_result.valid = 'b0;
    end
    endgenerate

    stream_intf #(.T(gecko_operation_t)) writeback_results_in [4] (.clk, .rst);

    stream_stage #(
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_TRANSPARENT),
        .T(gecko_operation_t)
    ) stream_tie_inst0(.stream_in(execute_result), .stream_out(writeback_results_in[0]));
    
    // stream_tie stream_tie_inst1(.stream_in(memory_result), .stream_out(writeback_results_in[1]));
    assign writeback_results_in[1].valid = memory_result.valid;
    assign writeback_results_in[1].payload = memory_result.payload;
    assign memory_result.ready = writeback_results_in[1].ready;

    stream_stage #(
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_TRANSPARENT),
        .T(gecko_operation_t)
    ) stream_tie_inst2(.stream_in(system_result), .stream_out(writeback_results_in[2]));
    
    stream_stage #(
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_TRANSPARENT),
        .T(gecko_operation_t)
    ) stream_tie_inst3(.stream_in(float_result), .stream_out(writeback_results_in[3]));

    gecko_writeback #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .PIPELINE_MODE(WRITEBACK_PIPELINE_MODE),
        .PORTS(4)
    ) gecko_writeback_inst (
        .clk, .rst,

        .writeback_results_in, .writeback_result
    );

`ifdef __SIMULATION__
    initial begin
        // Clear file
        automatic integer file = $fopen("log.txt", "w");
        $fclose(file);

        while ('b1) begin
            while (finished_flag || faulted_flag) @ (posedge clk);
            file = $fopen("log.txt", "w+");
            $display("Opened file");
            @ (posedge clk);
            while (1) begin
                if (print_out.valid && print_out.ready) begin
                    $fwrite(file, "%c", print_out.payload);
                end
                if (faulted_flag || finished_flag) begin
                    $display("Closed file");
                    $fclose(file);
                    break;
                end
                @ (posedge clk);
            end
            file = $fopen("status.txt", "w");
            if (faulted_flag) begin
                $display("Exit Error!!!");
                $fwrite(file, "Failure");
            end else begin
                $display("Exit Success!!!");
                $fwrite(file, "Success");
            end
            $fclose(file);
        end
    end
`endif

endmodule
