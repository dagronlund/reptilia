module gecko_core_wrapper 
    import gecko_pkg::*;
(
    input wire clk, 
    input wire rst
);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) 
        inst_request (.clk, .rst),
        inst_result (.clk, .rst),
        data_request (.clk, .rst),
        data_result (.clk, .rst),
        float_mem_request (.clk, .rst),
        float_mem_result (.clk, .rst);

    logic       exit_flag;
    logic       error_flag;
    logic [7:0] exit_code;

    stream_intf #(.T(logic [7:0])) 
        tty_in (.clk, .rst),
        tty_out (.clk, .rst);

    gecko_core inst (
        .clk, 
        .rst,

        .inst_request,
        .inst_result,

        .data_request,
        .data_result,

        .float_mem_request,
        .float_mem_result,

        .tty_in,
        .tty_out,
        .exit_flag,
        .error_flag,
        .exit_code
    );

endmodule