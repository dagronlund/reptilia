module stream_connect_wrapper (
    input wire clk, 
    input wire rst
);

    stream_intf stream_in  (.clk, .rst),
                stream_out (.clk, .rst);

    stream_connect inst(
        .stream_in,
        .stream_out);

endmodule