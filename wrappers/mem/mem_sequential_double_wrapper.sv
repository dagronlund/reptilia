module mem_sequential_double_wrapper (
    input wire clk, 
    input wire rst
);

    mem_intf mem_in0 (.clk, .rst),
             mem_out0 (.clk, .rst),
             mem_in1 (.clk, .rst),
             mem_out1 (.clk, .rst);

    mem_sequential_double inst(
        .clk,
        .rst,
        .mem_in0,
        .mem_out0,
        .mem_in1,
        .mem_out1
    );

endmodule