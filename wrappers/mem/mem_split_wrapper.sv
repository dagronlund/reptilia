module mem_split_wrapper (
    input wire clk, 
    input wire rst
);

    mem_intf #(.ID_WIDTH(2)) mem_in      (.clk, .rst);
    mem_intf                 mem_out [2] (.clk, .rst);

    logic [0:0] mem_in_meta;
    logic [0:0] mem_out_meta [2];

    mem_split inst(
        .clk,
        .rst,
        .mem_in,
        .mem_in_meta,
        .mem_out,
        .mem_out_meta
    );

endmodule