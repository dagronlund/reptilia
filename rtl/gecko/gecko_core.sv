`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/gecko/gecko.svh"

`else

`include "std_util.svh"
`include "std_mem.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32i.svh"
`include "gecko.svh"

`endif

module gecko_core
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#(
    parameter int INST_LATENCY = 1,
    parameter int DATA_LATENCY = 1,
    parameter int INST_PIPELINE_BREAK = 1,
    parameter gecko_pc_t START_ADDR = 'b0,
    parameter int ENABLE_PERFORMANCE_COUNTERS = 1,
    parameter int ENABLE_PRINT = 1
)(
    input logic clk, rst,

    std_mem_intf.out inst_request,
    std_mem_intf.in inst_result,

    std_mem_intf.out data_request,
    std_mem_intf.in data_result,

    std_stream_intf.out print_out,

    output logic faulted_flag, finished_flag
);

    `STATIC_ASSERT($size(inst_request.addr) == 32)
    `STATIC_ASSERT($size(inst_result.data) == 32)

    `STATIC_ASSERT($size(data_request.addr) == 32)
    `STATIC_ASSERT($size(data_result.data) == 32)

    std_stream_intf #(.T(gecko_jump_operation_t)) jump_command (.clk, .rst);

    std_stream_intf #(.T(gecko_execute_operation_t)) execute_command (.clk, .rst);
    std_stream_intf #(.T(gecko_system_operation_t)) system_command (.clk, .rst);
    std_stream_intf #(.T(gecko_ecall_operation_t)) ecall_command (.clk, .rst);
    std_stream_intf #(.T(gecko_float_operation_t)) float_command (.clk, .rst);
    assign float_command.ready = 'b1;

    std_stream_intf #(.T(gecko_operation_t)) execute_result (.clk, .rst);
    std_stream_intf #(.T(gecko_operation_t)) system_result (.clk, .rst);
    std_stream_intf #(.T(gecko_operation_t)) memory_result (.clk, .rst);

    std_stream_intf #(.T(gecko_operation_t)) writeback_result (.clk, .rst);

    std_stream_intf #(.T(gecko_instruction_operation_t)) instruction_command_in (.clk, .rst);
    std_stream_intf #(.T(gecko_instruction_operation_t)) instruction_command_out (.clk, .rst);
    std_stream_intf #(.T(gecko_instruction_operation_t)) instruction_command_break (.clk, .rst);

    std_stream_intf #(.T(gecko_mem_operation_t)) mem_command_in (.clk, .rst);
    std_stream_intf #(.T(gecko_mem_operation_t)) mem_command_out (.clk, .rst);

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

    gecko_fetch #(
        .START_ADDR(START_ADDR)
    ) gecko_fetch_inst (
        .clk, .rst,

        .jump_command,

        .instruction_command(instruction_command_in),
        .instruction_request(inst_request)
    );

    std_stream_stage #(
        .T(gecko_instruction_operation_t),
        .LATENCY(INST_LATENCY)
    ) gecko_inst_stage_inst (
        .clk, .rst,
        .data_in(instruction_command_in),
        .data_out(instruction_command_out)
    );

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_result_break (.clk, .rst);

    mem_stage #(
        .MODE(INST_PIPELINE_BREAK ? 2 : 0)
    ) mem_request_output_stage (
        .clk, .rst,
        .mem_in(inst_result), .mem_out(inst_result_break)
    );

    std_flow_stage #(
        .T(gecko_instruction_operation_t),
        .MODE(INST_PIPELINE_BREAK ? 2 : 0)
    ) std_flow_stage_inst (
        .clk, .rst,
        .stream_in(instruction_command_out), .stream_out(instruction_command_break)
    );

    logic exit_flag;
    logic [7:0] exit_code;

    gecko_decode #(
        .NUM_FORWARDED(3),
        .ENABLE_PRINT(ENABLE_PRINT)
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

    gecko_execute gecko_execute_inst
    (
        .clk, .rst,

        .execute_command,

        .mem_command(mem_command_in),
        .mem_request(data_request),

        .execute_result,

        .jump_command
    );

    std_stream_stage #(
        .T(gecko_mem_operation_t),
        .LATENCY(DATA_LATENCY)
    ) gecko_data_stage_inst (
        .clk, .rst,
        .data_in(mem_command_in),
        .data_out(mem_command_out)
    );

    gecko_system #(
        .ENABLE_PERFORMANCE_COUNTERS(ENABLE_PERFORMANCE_COUNTERS)
    ) gecko_system_inst (
        .clk, .rst,

        .retired_instructions,

        .system_command,
        .system_result
    );

    gecko_print #(
    ) gecko_print_inst (
        .clk, .rst,
        .ecall_command,
        .print_out
    );

    std_stream_intf #(.T(gecko_operation_t)) writeback_results_in [3] (.clk, .rst);

    stream_tie stream_tie_inst0(.stream_in(execute_result), .stream_out(writeback_results_in[0]));
    stream_tie stream_tie_inst1(.stream_in(memory_result), .stream_out(writeback_results_in[1]));
    stream_tie stream_tie_inst2(.stream_in(system_result), .stream_out(writeback_results_in[2]));

    gecko_writeback #(
        .PORTS(3)
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
