module mem_sequential_read_write_wrapper (
    input wire clk, 
    input wire rst
);

    mem_intf mem_read_in (.clk, .rst),
             mem_read_out (.clk, .rst),
             mem_write_in (.clk, .rst);

    mem_sequential_read_write inst(
        .clk,
        .rst,
        .mem_read_in,
        .mem_read_out,
        .mem_write_in
    );

endmodule