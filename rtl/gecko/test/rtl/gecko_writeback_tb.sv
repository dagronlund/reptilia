module gecko_writeback_tb
    import gecko_pkg::*;
();
    /* verilator public_flat_rw_on */
    logic clk, rst;
    stream_intf #(
        .T(gecko_operation_t)
    ) writeback_results_in[2] (
        .clk,
        .rst
    );
    stream_intf #(
        .T(gecko_operation_t)
    ) writeback_result (
        .clk,
        .rst
    );
    /* verilator public_off */

    gecko_writeback #(
        .PORTS(2)
    ) inst (
        .clk,
        .rst,
        .writeback_results_in,
        .writeback_result
    );

endmodule
