module gecko_execute_wrapper 
    import gecko_pkg::*;
(
    input wire clk, 
    input wire rst,

    output logic instruction_executed
);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_request (.clk, .rst);

    stream_intf #(.T(gecko_execute_operation_t)) execute_command (.clk, .rst);
    stream_intf #(.T(gecko_mem_operation_t))     mem_command     (.clk, .rst);
    stream_intf #(.T(gecko_operation_t))         execute_result  (.clk, .rst);
    stream_intf #(.T(gecko_jump_operation_t))    jump_command    (.clk, .rst);

    gecko_execute inst (
        .clk, 
        .rst,

        .execute_command,

        .mem_command,
        .mem_request,
        .execute_result,
        .jump_command,

        .instruction_executed
    );

endmodule