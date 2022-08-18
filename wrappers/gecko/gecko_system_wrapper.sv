module gecko_sytem_wrapper 
    import gecko_pkg::*;
(
    input wire clk, 
    input wire rst,

    input logic instruction_decoded,
    input logic instruction_executed
);

    stream_intf #(.T(gecko_system_operation_t)) system_command (.clk, .rst);
    stream_intf #(.T(gecko_operation_t))        system_result  (.clk, .rst);

    stream_intf #(.T(logic [7:0])) tty_in (.clk, .rst);
    stream_intf #(.T(logic [7:0])) tty_out (.clk, .rst);

    logic [7:0] exit_code;

    gecko_performance_stats_t performance_stats;

    gecko_system inst (
        .clk, 
        .rst,

        .performance_stats,
        .system_command,
        .system_result,

        .instruction_decoded,
        .instruction_executed,

        .tty_in,
        .tty_out,
        .exit_code
    );

endmodule
