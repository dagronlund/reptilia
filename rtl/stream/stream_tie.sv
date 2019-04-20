`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"

`else

`include "std_util.svh"

`endif

module stream_tie #()(
    std_stream_intf.in stream_in,
    std_stream_intf.out stream_out
);

    `STATIC_ASSERT($bits(stream_in.payload) == $bits(stream_out.payload))

    always_comb begin
        stream_out.valid = stream_in.valid;
        stream_in.ready = stream_out.ready;
        stream_out.payload = stream_in.payload;
    end

endmodule
