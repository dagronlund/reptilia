module gecko_core_wrapper 
    import gecko_pkg::*;
(
    input wire clk, 
    input wire rst
);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) inst_result (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) data_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) data_result (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) float_mem_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) float_mem_result (.clk, .rst);

    stream_intf #(.T(logic [7:0])) print_out (.clk, .rst);

    logic faulted_flag;
    logic finished_flag;

    gecko_core inst (
        .clk, 
        .rst,

        .inst_request,
        .inst_result,

        .data_request,
        .data_result,

        .float_mem_request,
        .float_mem_result,

        .print_out,

        .finished_flag,
        .faulted_flag
    );

endmodule