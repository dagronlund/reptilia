module gecko_execute_tb
    import riscv32i_pkg::*;
    import gecko_pkg::*;
();
    /* verilator public_flat_rw_on */
    logic clk, rst;
    stream_intf #(
        .T(gecko_execute_operation_t)
    ) execute_command (
        .clk,
        .rst
    );
    stream_intf #(
        .T(gecko_mem_operation_t)
    ) mem_command (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32)
    ) mem_request (
        .clk,
        .rst
    );
    stream_intf #(
        .T(gecko_operation_t)
    ) execute_result (
        .clk,
        .rst
    );
    stream_intf #(
        .T(gecko_jump_operation_t)
    ) jump_command (
        .clk,
        .rst
    );
    logic instruction_updated;
    logic instruction_executed;
    /* verilator public_off */

    gecko_execute #(
        .ENABLE_INTEGER_MATH(1'b1)
    ) inst (
        .clk,
        .rst,
        .instruction_updated,
        .execute_command,
        .mem_command,
        .mem_request,
        .execute_result,
        .jump_command,
        .instruction_executed
    );

endmodule
