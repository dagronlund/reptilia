module gecko_decode_wrapper 
    import gecko_pkg::*;
(
    input wire clk, 
    input wire rst,

    input  wire                          instruction_result_valid,
    output logic                         instruction_result_ready,
    input  wire                          instruction_result_read_enable,
    input  wire  [3:0]                   instruction_result_write_enable,
    input  wire  [31:0]                  instruction_result_addr,
    input  wire  [31:0]                  instruction_result_data,
    input  wire  [0:0]                   instruction_result_id,
    input  wire                          instruction_result_last,
    
    // Input streams
    input  wire                          instruction_command_valid,
    output logic                         instruction_command_ready,
    input  gecko_instruction_operation_t instruction_command_data,    

    input  wire                          jump_command_valid,
    output logic                         jump_command_ready,
    input  gecko_jump_operation_t        jump_command_data,    

    input  wire                          writeback_result_valid,
    output logic                         writeback_result_ready,
    input  gecko_operation_t             writeback_result_data,

    // Output streams
    output logic                         system_command_valid,
    input  wire                          system_command_ready,
    output gecko_system_operation_t      system_command_data,

    output logic                         execute_command_valid,
    input  wire                          execute_command_ready,
    output gecko_execute_operation_t     execute_command_data,

    output logic                         float_command_valid,
    input  wire                          float_command_ready,
    output gecko_float_operation_t       float_command_data,

    input gecko_forwarded_t [0:0] forwarded_results,

    output gecko_performance_stats_t performance_stats,

    output logic instruction_decoded,

    output logic exit_flag,
    output logic error_flag
);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) instruction_result (.clk, .rst);

    stream_intf #(.T(gecko_instruction_operation_t)) instruction_command  (.clk, .rst);
    stream_intf #(.T(gecko_system_operation_t))      system_command       (.clk, .rst);
    stream_intf #(.T(gecko_execute_operation_t))     execute_command      (.clk, .rst);
    stream_intf #(.T(gecko_float_operation_t))       float_command        (.clk, .rst);
    stream_intf #(.T(gecko_jump_operation_t))        jump_command         (.clk, .rst);
    stream_intf #(.T(gecko_operation_t))             writeback_result     (.clk, .rst);

    always_comb instruction_result.valid        = instruction_result_valid;
    always_comb instruction_result_ready        = instruction_result.ready;
    always_comb instruction_result.read_enable  = instruction_result_read_enable;
    always_comb instruction_result.write_enable = instruction_result_write_enable;
    always_comb instruction_result.addr         = instruction_result_addr;
    always_comb instruction_result.data         = instruction_result_data;
    always_comb instruction_result.id           = instruction_result_id;
    always_comb instruction_result.last         = instruction_result_last;

    // Input Streams
    always_comb instruction_command.valid   = instruction_command_valid;
    always_comb instruction_command_ready   = instruction_command.ready;
    always_comb instruction_command.payload = instruction_command_data;

    always_comb jump_command.valid   = jump_command_valid;
    always_comb jump_command_ready   = jump_command.ready;
    always_comb jump_command.payload = jump_command_data;

    always_comb writeback_result.valid   = writeback_result_valid;
    always_comb writeback_result_ready   = writeback_result.ready;
    always_comb writeback_result.payload = writeback_result_data;

    // Output streams
    always_comb system_command_valid = system_command.valid;
    always_comb system_command.ready = system_command_ready;
    always_comb system_command_data  = system_command.payload;

    always_comb execute_command_valid = execute_command.valid;
    always_comb execute_command.ready = execute_command_ready;
    always_comb execute_command_data  = execute_command.payload;

    always_comb float_command_valid = float_command.valid;
    always_comb float_command.ready = float_command_ready;
    always_comb float_command_data  = float_command.payload;

    gecko_decode inst (
        .clk, 
        .rst,

        .instruction_result,
        .instruction_command,

        .system_command,
        .execute_command,
        .float_command,

        .jump_command,
        .writeback_result,

        .forwarded_results,

        .performance_stats,
        .instruction_decoded,
        .exit_flag,
        .error_flag
    );

endmodule