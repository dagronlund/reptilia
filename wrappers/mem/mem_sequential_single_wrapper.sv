module mem_sequential_single_wrapper (
    input wire clk, 
    input wire rst
);

    mem_intf mem_in (.clk, .rst),
             mem_out (.clk, .rst);

    mem_sequential_single inst(
        .clk,
        .rst,
        .mem_in,
        .mem_out
    );

endmodule