//!import std/std_pkg
//!import std/std_register
//!import stream/stream_pkg

`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
`else
    `include "std_util.svh"
`endif

module stream_stage_multiple
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter int STAGES = 1,
    parameter type T = logic
)(
    input wire clk, 
    input wire rst,

    stream_intf.in stream_in,
    stream_intf.out stream_out
);

    `STATIC_ASSERT($bits(T) == $bits(stream_in.payload))
    `STATIC_ASSERT($bits(T) == $bits(stream_out.payload))



    genvar k;
    generate
    if (STAGES == 0) begin

        stream_stage #(
            .CLOCK_INFO(CLOCK_INFO),
            .PIPELINE_MODE(STREAM_PIPELINE_MODE_TRANSPARENT),
            .T(T)
        ) stream_stage_inst (
            .clk, .rst,
            .stream_in, .stream_out
        );

    end else if (STAGES == 1) begin

        stream_stage #(
            .CLOCK_INFO(CLOCK_INFO),
            .PIPELINE_MODE(PIPELINE_MODE),
            .T(T)
        ) stream_stage_inst (
            .clk, .rst,
            .stream_in, .stream_out
        );

    end else begin
        localparam int INTERNAL_STAGES = STAGES - 1;
        stream_intf #(.T(T)) internal_streams [INTERNAL_STAGES] (.clk, .rst);

        for (k = 0; k < STAGES; k++) begin
            if (k == 0) begin

                stream_stage #(
                    .CLOCK_INFO(CLOCK_INFO),
                    .PIPELINE_MODE(PIPELINE_MODE),
                    .T(T)
                ) stream_stage_inst (
                    .clk, .rst,
                    .stream_in(stream_in), .stream_out(internal_streams[k])
                );

            end else if (k == STAGES - 1) begin

                stream_stage #(
                    .CLOCK_INFO(CLOCK_INFO),
                    .PIPELINE_MODE(PIPELINE_MODE),
                    .T(T)
                ) stream_stage_inst (
                    .clk, .rst,
                    .stream_in(internal_streams[k - 1]), .stream_out(stream_out)
                );

            end else begin

                stream_stage #(
                    .CLOCK_INFO(CLOCK_INFO),
                    .PIPELINE_MODE(PIPELINE_MODE),
                    .T(T)
                ) stream_stage_inst (
                    .clk, .rst,
                    .stream_in(internal_streams[k - 1]), .stream_out(internal_streams[k])
                );

            end
        end
    end

    
    endgenerate

endmodule
