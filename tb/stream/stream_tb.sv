//!import std/std_pkg
//!import std/stream_pkg
//!import stream/stream_intf
//!import stream/stream_stage

`timescale 1ns/1ps

module stream_tb
    import std_pkg::*;
    import stream_pkg::*;
#()();

    localparam int NUM_TRIALS = 1024;
    localparam std_clock_info_t CLOCK_INFO = 'b0;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    stream_intf #(.T(int)) stream_transparent_in (.clk, .rst);
    stream_intf #(.T(int)) stream_transparent_out (.clk, .rst);

    stream_intf #(.T(int)) stream_registered_in (.clk, .rst);
    stream_intf #(.T(int)) stream_registered_out (.clk, .rst);

    stream_intf #(.T(int)) stream_buffered_in (.clk, .rst);
    stream_intf #(.T(int)) stream_buffered_out (.clk, .rst);

    stream_intf #(.T(int)) stream_elastic_in (.clk, .rst);
    stream_intf #(.T(int)) stream_elastic_out (.clk, .rst);

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_TRANSPARENT),
        .T(int)
    ) stream_stage_transparent_inst (
        .clk, .rst,
        .stream_in(stream_transparent_in), .stream_out(stream_transparent_out)
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_REGISTERED),
        .T(int)
    ) stream_stage_registered_inst (
        .clk, .rst,
        .stream_in(stream_registered_in), .stream_out(stream_registered_out)
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_BUFFERED),
        .T(int)
    ) stream_stage_buffered_inst (
        .clk, .rst,
        .stream_in(stream_buffered_in), .stream_out(stream_buffered_out)
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_ELASTIC),
        .T(int)
    ) stream_stage_elastic_inst (
        .clk, .rst,
        .stream_in(stream_elastic_in), .stream_out(stream_elastic_out)
    );

    initial begin
        stream_transparent_in.valid = 'b0;
        stream_transparent_out.ready = 'b0;

        stream_registered_in.valid = 'b0;
        stream_registered_out.ready = 'b0;

        stream_buffered_in.valid = 'b0;
        stream_buffered_out.ready = 'b0;

        stream_elastic_in.valid = 'b0;
        stream_elastic_out.ready = 'b0;

        while (std_is_reset_active(CLOCK_INFO, rst)) @ (posedge clk);

        fork
        // Send incrementing numbers
        begin
            for (int i = 0; i < NUM_TRIALS; i++) begin
                stream_transparent_in.payload <= i;
                @ (posedge clk);
                while (!(stream_transparent_in.valid && stream_transparent_in.ready))
                    @ (posedge clk);
            end
        end
        begin
            for (int i = 0; i < NUM_TRIALS; i++) begin
                stream_registered_in.payload <= i;
                @ (posedge clk);
                while (!(stream_registered_in.valid && stream_registered_in.ready))
                    @ (posedge clk);
            end
        end
        begin
            for (int i = 0; i < NUM_TRIALS; i++) begin
                stream_buffered_in.payload <= i;
                @ (posedge clk);
                while (!(stream_buffered_in.valid && stream_buffered_in.ready))
                    @ (posedge clk);
            end
        end
        begin
            for (int i = 0; i < NUM_TRIALS; i++) begin
                stream_elastic_in.payload <= i;
                @ (posedge clk);
                while (!(stream_elastic_in.valid && stream_elastic_in.ready))
                    @ (posedge clk);
            end
        end

        // Recieve and check incrementing numbers
        begin
            fork
            for (int i = 0; i < NUM_TRIALS; i++) begin
                @ (posedge clk);
                while (!(stream_transparent_out.valid && stream_transparent_out.ready))
                    @ (posedge clk);
                if (i != stream_transparent_out.payload) begin
                    $display("Stream test failed! %d != %d", i, stream_transparent_out.payload);
                    $finish();
                end
            end
            for (int i = 0; i < NUM_TRIALS; i++) begin
                @ (posedge clk);
                while (!(stream_registered_out.valid && stream_registered_out.ready))
                    @ (posedge clk);
                if (i != stream_registered_out.payload) begin
                    $display("Stream test failed! %d != %d", i, stream_registered_out.payload);
                    $finish();
                end
            end
            for (int i = 0; i < NUM_TRIALS; i++) begin
                @ (posedge clk);
                while (!(stream_buffered_out.valid && stream_buffered_out.ready))
                    @ (posedge clk);
                if (i != stream_buffered_out.payload) begin
                    $display("Stream test failed! %d != %d", i, stream_buffered_out.payload);
                    $finish();
                end
            end
            for (int i = 0; i < NUM_TRIALS; i++) begin
                @ (posedge clk);
                while (!(stream_elastic_out.valid && stream_elastic_out.ready))
                    @ (posedge clk);
                if (i != stream_elastic_out.payload) begin
                    $display("Stream test failed! %d != %d", i, stream_elastic_out.payload);
                    $finish();
                end
            end
            join
            
            $display("Stream test succeeded!");
            $finish();
        end

        // Randomly set external valid and ready
        begin
            while ('b1) begin
                @ (posedge clk);
                stream_transparent_in.valid <= $urandom();
                stream_transparent_out.ready <= $urandom();
                stream_registered_in.valid <= $urandom();
                stream_registered_out.ready <= $urandom();
                stream_buffered_in.valid <= $urandom();
                stream_buffered_out.ready <= $urandom();
                stream_elastic_in.valid <= $urandom();
                stream_elastic_out.ready <= $urandom();
            end
        end
        join

    end

endmodule
