module gecko_decode_tb
    import gecko_pkg::*;
();
    /* verilator public_flat_rw_on */
    logic clk, rst;
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32)
    ) instruction_result (
        .clk,
        .rst
    );
    stream_intf #(
        .T(gecko_instruction_operation_t)
    ) instruction_command (
        .clk,
        .rst
    );
    stream_intf #(
        .T(gecko_system_operation_t)
    ) system_command (
        .clk,
        .rst
    );
    stream_intf #(
        .T(gecko_execute_operation_t)
    ) execute_command (
        .clk,
        .rst
    );
    stream_intf #(
        .T(gecko_float_operation_t)
    ) float_command (
        .clk,
        .rst
    );
    stream_intf #(
        .T(gecko_jump_operation_t)
    ) jump_command (
        .clk,
        .rst
    );
    stream_intf #(
        .T(gecko_operation_t)
    ) writeback_result (
        .clk,
        .rst
    );
    logic error_flag;
    /* verilator public_off */

    gecko_decode #(
        .ENABLE_INTEGER_MATH(1'b1),
        .ENABLE_FLOAT(1'b0)
    ) inst (
        .clk,
        .rst,
        .instruction_result,
        .instruction_command,
        .system_command,
        .execute_command,
        .float_command,
        .jump_command,
        .writeback_result,
        .forwarded_results('{default: '0}),
        .performance_stats(),
        .instruction_decoded(),
        .exit_flag(),
        .error_flag
    );

endmodule
