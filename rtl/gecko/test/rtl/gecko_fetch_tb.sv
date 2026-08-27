module gecko_fetch_tb
    import gecko_pkg::*;
();
    /* verilator public_flat_rw_on */
    logic clk, rst;
    stream_intf #(
        .T(gecko_jump_operation_t)
    ) jump_command (
        .clk,
        .rst
    );
    stream_intf #(
        .T(gecko_instruction_operation_t)
    ) instruction_command (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32)
    ) instruction_request (
        .clk,
        .rst
    );
    /* verilator public_off */

    gecko_fetch #(
        .PREDICTOR_CONFIG(
        '{mode: GECKO_PREDICTOR_MODE_NONE, target_addr_width: 5, history_width: 5, local_addr_width: 5}
        )
    ) inst (
        .clk,
        .rst,
        .jump_command,
        .instruction_command,
        .instruction_request
    );

endmodule
