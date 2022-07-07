module gecko_sytem_wrapper 
    import gecko_pkg::*;
(
    input wire clk, 
    input wire rst
);

    stream_intf #(.T(gecko_system_operation_t)) system_command (.clk, .rst);
    stream_intf #(.T(gecko_operation_t))        system_result  (.clk, .rst);

    gecko_retired_count_t retired_instructions;

    gecko_system inst (
        .clk, 
        .rst,

        .retired_instructions,
        .system_command,
        .system_result
    );

endmodule
