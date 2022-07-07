module stream_split_wrapper (
    input wire clk, 
    input wire rst
);

    stream_intf stream_in (.clk, .rst),
                stream_out [2] (.clk, .rst);

    logic [0:0] stream_in_id;
    logic       stream_in_last;

    logic [0:0] stream_out_id [2];
    logic       stream_out_last [2];

    stream_split inst(
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