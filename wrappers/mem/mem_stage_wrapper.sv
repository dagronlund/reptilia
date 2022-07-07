module mem_stage_wrapper (
    input wire clk, 
    input wire rst
);

    mem_intf mem_in (.clk, .rst),
             mem_out(.clk, .rst);

    logic [0:0] mem_in_meta;
    logic [0:0] mem_out_meta;

    mem_stage inst(
        .clk,
        .rst,
        .mem_in,
        .mem_in_meta,
        .mem_out,
        .mem_out_meta
    );

endmodule