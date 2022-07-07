module stream_stage_wrapper (
    input wire clk, 
    input wire rst
);

    stream_intf stream_in  (.clk, .rst),
                stream_out (.clk, .rst);

    stream_stage inst(
        .clk,
        .rst,
        .stream_in,
        .stream_out
    );

endmodule