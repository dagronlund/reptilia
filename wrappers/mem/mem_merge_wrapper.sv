module mem_merge_wrapper (
    input wire clk, 
    input wire rst
);

    mem_intf                 mem_in [2] (.clk, .rst);
    mem_intf #(.ID_WIDTH(2)) mem_out    (.clk, .rst);

    logic [0:0] mem_in_meta [2];
    logic [0:0] mem_out_meta;

    mem_merge inst(
        .clk,
        .rst,
        .mem_in,
        .mem_in_meta,
        .mem_out,
        .mem_out_meta
    );

endmodule