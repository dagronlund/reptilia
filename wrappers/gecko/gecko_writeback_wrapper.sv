module gecko_writeback_wrapper 
    import gecko_pkg::*;
(
    input wire clk, 
    input wire rst
);

    stream_intf #(.T(gecko_operation_t)) writeback_results_in [2] (.clk, .rst);
    stream_intf #(.T(gecko_operation_t)) writeback_result         (.clk, .rst);

    gecko_writeback #(.PORTS(2)) inst (
        .clk, 
        .rst,

        .writeback_results_in,
        .writeback_result
    );

endmodule
