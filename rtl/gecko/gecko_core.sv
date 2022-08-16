//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import riscv/riscv32i_pkg.sv
//!import gecko/gecko_pkg.sv
//!import stream/stream_connect.sv
//!import stream/stream_stage_multiple.sv
//!import gecko/gecko_fetch.sv
//!import gecko/gecko_decode.sv
//!import gecko/gecko_execute.sv
//!import gecko/gecko_writeback.sv
//!import gecko/gecko_system.sv
//!wrapper gecko/gecko_core_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

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
    parameter gecko_config_t   CONFIG     = gecko_get_basic_config(1, 1, 1)
)(
    input wire clk, 
    input wire rst,

    mem_intf.out inst_request,
    mem_intf.in inst_result,

    mem_intf.out data_request,
    mem_intf.in data_result,

    mem_intf.out float_mem_request,
    mem_intf.in float_mem_result,

    stream_intf.in  tty_in, // logic [7:0]
    stream_intf.out tty_out, // logic [7:0]

    output logic       exit_flag,
    output logic       error_flag,
    output logic [7:0] exit_code
);

    `STATIC_ASSERT($size(inst_request.addr) == 32)
    `STATIC_ASSERT($size(inst_result.data) == 32)

    `STATIC_ASSERT($size(data_request.addr) == 32)
    `STATIC_ASSERT($size(data_result.data) == 32)

    stream_intf #(.T(gecko_jump_operation_t)) jump_command (.clk, .rst);

    stream_intf #(.T(gecko_execute_operation_t)) execute_command (.clk, .rst);
    stream_intf #(.T(gecko_system_operation_t)) system_command (.clk, .rst);
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

    gecko_performance_stats_t performance_stats;

    // Turn memory result into normal register result, ignoring data if mispredicted
    always_comb memory_result.valid = mem_command_out.valid && 
            (data_result.valid || 
            mem_command_out.payload.mispredicted);
    always_comb memory_result.payload = gecko_get_load_operation(mem_command_out.payload, data_result.data);
    always_comb mem_command_out.ready = memory_result.ready;
    always_comb data_result.ready = memory_result.ready && !mem_command_out.payload.mispredicted;

    gecko_forwarded_t execute_forwarded;
    gecko_forwarded_t writeback_forwarded;
    gecko_forwarded_t memory_forwarded;

    always_comb execute_forwarded = gecko_construct_forward(execute_result.valid, execute_result.payload);
    always_comb writeback_forwarded = gecko_construct_forward(writeback_result.valid, writeback_result.payload);
    always_comb memory_forwarded = gecko_construct_forward(memory_result.valid, memory_result.payload);

    always_comb jump_command.ready = 'b1;

    gecko_fetch #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .PIPELINE_MODE(CONFIG.fetch_pipeline_mode),
        .START_ADDR(CONFIG.start_addr),
        .BRANCH_PREDICTOR_CONFIG(CONFIG.branch_predictor_config)
    ) gecko_fetch_inst (
        .clk, .rst,

        .jump_command,

        .instruction_command(instruction_command_in),
        .instruction_request(inst_request)
    );

    stream_stage_multiple #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_REGISTERED),
        .STAGES(CONFIG.instruction_memory_latency),
        .T(gecko_instruction_operation_t)
    ) gecko_inst_stage_inst (
        .clk, .rst,
        .stream_in(instruction_command_in),
        .stream_out(instruction_command_out)
    );

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_result_break (.clk, .rst);

    mem_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(CONFIG.imem_pipeline_mode)
    ) instruction_result_output_stage_inst (
        .clk, .rst,
        .mem_in(inst_result), 
        .mem_in_meta('b0),
        .mem_out(inst_result_break),
        .mem_out_meta()
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(CONFIG.imem_pipeline_mode),
        .T(gecko_instruction_operation_t)
    ) instruction_command_output_stage_inst (
        .clk, .rst,
        .stream_in(instruction_command_out), 
        .stream_out(instruction_command_break)
    );

    gecko_decode #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .PIPELINE_MODE(CONFIG.decode_pipeline_mode),
        .NUM_FORWARDED(3),
        .ENABLE_FLOAT(CONFIG.enable_floating_point),
        .ENABLE_INTEGER_MATH(CONFIG.enable_integer_math)
    ) gecko_decode_inst (
        .clk, .rst,

        .instruction_command(instruction_command_break),
        .instruction_result(inst_result_break),

        .system_command,
        .execute_command,
        .float_command,

        .jump_command,

        .writeback_result,

        .forwarded_results({execute_forwarded, memory_forwarded, writeback_forwarded}),

        .exit_flag, 
        .error_flag,

        .performance_stats
    );

    gecko_execute #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .PIPELINE_MODE(CONFIG.execute_pipeline_mode),
        .ENABLE_INTEGER_MATH(CONFIG.enable_integer_math)
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
        .STAGES(CONFIG.data_memory_latency),
        .T(gecko_mem_operation_t)
    ) gecko_data_stage_inst (
        .clk, .rst,
        .stream_in(mem_command_in),
        .stream_out(mem_command_out)
    );

    gecko_system #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .PIPELINE_MODE(CONFIG.system_pipeline_mode),
        .ENABLE_TTY_IO(CONFIG.enable_tty_io),
        .ENABLE_PERFORMANCE_COUNTERS(CONFIG.enable_performance_counters)
    ) gecko_system_inst (
        .clk, .rst,

        .performance_stats,

        .system_command,
        .system_result,

        .tty_in,
        .tty_out,
        .exit_code
    );

    generate
    if (CONFIG.enable_floating_point) begin

        // // TODO: Refactor VPU/FPU logic
        // basilisk_vpu #(
        //     .MEMORY_LATENCY(CONFIG.float_memory_latency)
        // ) basilisk_vpu_inst (
        //     .clk, .rst,
        //     .float_command, .float_result,
        //     .float_mem_request, .float_mem_result
        // );

    end else begin
        always_comb float_mem_request.valid = 'b0;
        always_comb float_mem_result.ready = 'b0;
        always_comb float_command.ready = 'b0;
        always_comb float_result.valid = 'b0;
    end
    endgenerate

    stream_intf #(.T(gecko_operation_t)) writeback_results_in [4] (.clk, .rst);

    stream_connect #(.T(gecko_operation_t)) 
        stream_connect0(.stream_in(execute_result), .stream_out(writeback_results_in[0])),
        stream_connect1(.stream_in(memory_result),  .stream_out(writeback_results_in[1])),
        stream_connect2(.stream_in(system_result),  .stream_out(writeback_results_in[2])),
        stream_connect3(.stream_in(float_result),   .stream_out(writeback_results_in[3]));

    gecko_writeback #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .PIPELINE_MODE(CONFIG.writeback_pipeline_mode),
        .PORTS(4)
    ) gecko_writeback_inst (
        .clk, .rst,

        .writeback_results_in, 
        .writeback_result
    );

endmodule
