module stream_merge_wrapper (
    input wire clk, 
    input wire rst
);

    stream_intf stream_in [2] (.clk, .rst),
                stream_out (.clk, .rst);

    logic [0:0] stream_in_id [2];
    logic       stream_in_last [2];

    logic [0:0] stream_out_id;
    logic       stream_out_last;

    stream_merge inst(
        .clk,
        .rst,

        .stream_in,
        .stream_in_id,
        .stream_in_last,

        .stream_out,
        .stream_out_id,
        .stream_out_last     
    );

endmodule