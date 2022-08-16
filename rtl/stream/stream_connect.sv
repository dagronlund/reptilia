//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import stream/stream_intf.sv
//!import stream/stream_stage.sv
//!wrapper stream/stream_connect_wrapper.sv

module stream_connect
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter type T = logic
)(
    stream_intf.in stream_in,
    stream_intf.out stream_out
);

    stream_stage #(
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_TRANSPARENT),
        .T(T)
    ) stream_stage_inst0(
        .clk('b0),
        .rst('b0),
        .stream_in, 
        .stream_out);

endmodule



