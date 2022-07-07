module gecko_print_wrapper 
    import gecko_pkg::*;
(
    input wire clk, 
    input wire rst
);

    stream_intf #(.T(gecko_ecall_operation_t)) ecall_command  (.clk, .rst);
    stream_intf #(.T(logic [7:0]))             print_out      (.clk, .rst);

    gecko_print inst (
        .clk, 
        .rst,

        .ecall_command,
        .print_out
    );

endmodule
