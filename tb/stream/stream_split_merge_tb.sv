//!import std/std_pkg
//!import std/stream_pkg
//!import stream/stream_intf
//!import stream/stream_stage
//!import stream/stream_split
//!import stream/stream_merge

`timescale 1ns/1ps

module stream_split_merge_tb
    import std_pkg::*;
    import stream_pkg::*;
#()();

    localparam int NUM_TRIALS = 1024;
    localparam std_clock_info_t CLOCK_INFO = 'b0;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    stream_intf #(.T(int)) merge_stream_in [2] (.clk, .rst);
    logic merge_stream_in_id [2];
    logic merge_stream_in_last [2];

    stream_intf #(.T(int)) merge_split_stream (.clk, .rst);
    logic merge_split_stream_id;
    logic merge_split_stream_last;

    stream_intf #(.T(int)) split_stream_out [2] (.clk, .rst);
    logic split_stream_out_id [2];
    logic split_stream_out_last [2];

    stream_merge #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_REGISTERED),
        .STREAM_SELECT_MODE(STREAM_SELECT_MODE_ROUND_ROBIN),
        .PORTS(2),
        .USE_LAST(1)
    ) stream_merge_round_robin_inst (
        .clk, .rst,

        .stream_in(merge_stream_in), 
        .stream_in_id(merge_stream_in_id), 
        .stream_in_last(merge_stream_in_last),
        
        .stream_out(merge_split_stream), 
        .stream_out_id(merge_split_stream_id), 
        .stream_out_last(merge_split_stream_last)
    );

    stream_split #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_REGISTERED),
        .STREAM_SELECT_MODE(STREAM_SELECT_MODE_ROUND_ROBIN),
        .PORTS(2),
        .USE_LAST(1)
    ) stream_split_round_robin_inst (
        .clk, .rst,

        .stream_in(merge_split_stream), 
        .stream_in_id(merge_split_stream_id),
        .stream_in_last(merge_split_stream_last),
        
        .stream_out(split_stream_out), 
        .stream_out_id(split_stream_out_id),
        .stream_out_last(split_stream_out_last)
    );

    stream_intf #(.T(int)) merge_ordered_stream_in [4] (.clk, .rst);
    logic [1:0] merge_ordered_stream_in_id [4];

    stream_intf #(.T(int)) merge_ordered_stream_out (.clk, .rst);
    logic [1:0] merge_ordered_stream_out_id;

    stream_merge #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_REGISTERED),
        .STREAM_SELECT_MODE(STREAM_SELECT_MODE_ORDERED),
        .PORTS(4)
    ) stream_merge_ordered_inst (
        .clk, .rst,

        .stream_in(merge_ordered_stream_in), .stream_in_id(merge_ordered_stream_in_id),
        .stream_out(merge_ordered_stream_out), .stream_out_id(merge_ordered_stream_out_id)
    );

    int result0, result1;

    initial begin
        automatic logic [1:0] ordered_id = 'b0;

        merge_stream_in[0].valid = 'b0;
        merge_stream_in_id[0] = 'b0;
        merge_stream_in_last[0] = 'b0;
        merge_stream_in[1].valid = 'b0;
        merge_stream_in_id[1] = 'b0;
        merge_stream_in_last[1] = 'b0;

        split_stream_out[0].ready = 'b0;
        split_stream_out[1].ready = 'b0;

        merge_ordered_stream_in[0].valid = 'b0;
        merge_ordered_stream_in[1].valid = 'b0;
        merge_ordered_stream_in[2].valid = 'b0;
        merge_ordered_stream_in[3].valid = 'b0;

        merge_ordered_stream_out.ready = 'b0;

        while (std_is_reset_active(CLOCK_INFO, rst)) @ (posedge clk);

        // // Perform random stream validation
        // fork
        // // Send incrementing numbers on stream 0
        // for (int i = 0; i < NUM_TRIALS; i++) begin
        //     merge_stream_in[0].payload <= i;
        //     @ (posedge clk);
        //     while (!(merge_stream_in[0].valid && merge_stream_in[0].ready))
        //         @ (posedge clk);
        // end
        // // Send decrementing numbers on stream 1
        // for (int i = 0; i < NUM_TRIALS; i++) begin
        //     merge_stream_in[1].payload <= (NUM_TRIALS - i - 1);
        //     @ (posedge clk);
        //     while (!(merge_stream_in[1].valid && merge_stream_in[1].ready))
        //         @ (posedge clk);
        // end

        // // TODO: Create test for ordered merge

        // // Recieve and check numbers
        // begin
        //     fork
        //     for (int i = 0; i < NUM_TRIALS; i++) begin
        //         @ (posedge clk);
        //         while (!(split_stream_out[0].valid && split_stream_out[0].ready))
        //             @ (posedge clk);
        //         if (i != split_stream_out[0].payload) begin
        //             $fatal("Stream test failed! %d != %d", i, split_stream_out[0].payload);
        //         end
        //     end
        //     for (int i = 0; i < NUM_TRIALS; i++) begin
        //         @ (posedge clk);
        //         while (!(split_stream_out[1].valid && split_stream_out[1].ready))
        //             @ (posedge clk);
        //         if ((NUM_TRIALS - i - 1) != split_stream_out[1].payload) begin
        //             $fatal("Stream test failed! %d != %d", (NUM_TRIALS - i - 1), split_stream_out[1].payload);
        //         end
        //     end
        //     join
            
        //     $display("Random Stream split merge test succeeded!");
        //     $finish();
        // end

        // // Randomly set external valid and ready
        // while ('b1) begin
        //     @ (posedge clk);
        //     merge_stream_in[0].valid <= $urandom();
        //     split_stream_out[0].ready <= $urandom();
        //     merge_stream_in[1].valid <= $urandom();
        //     split_stream_out[1].ready <= $urandom();

        //     merge_ordered_stream_out.ready <= $urandom();
        // end
        // join

        // Perform last flag ordering validation
        split_stream_out[0].ready <= 'b1;
        split_stream_out[1].ready <= 'b1;
        $display("All stream 0 and 1 results should be consecutive.");
        fork
        begin
            merge_stream_in[0].send(0);
            merge_stream_in[0].send(1);
            merge_stream_in[0].send(2);
            merge_stream_in_last[0] <= 'b1;
            merge_stream_in[0].send(3);
        end
        begin
            merge_stream_in[1].send(0);
            merge_stream_in[1].send(1);
            merge_stream_in[1].send(2);
            merge_stream_in_last[1] <= 'b1;
            merge_stream_in[1].send(3);
        end
        begin
            split_stream_out[0].recv(result0);
            $display("Stream 0: %h, %b", result0, split_stream_out_last[0]);
            split_stream_out[0].recv(result0);
            $display("Stream 0: %h, %b", result0, split_stream_out_last[0]);
            split_stream_out[0].recv(result0);
            $display("Stream 0: %h, %b", result0, split_stream_out_last[0]);
            split_stream_out[0].recv(result0);
            $display("Stream 0: %h, %b", result0, split_stream_out_last[0]);
        end
        begin
            split_stream_out[1].recv(result1);
            $display("Stream 1: %h, %b", result1, split_stream_out_last[1]);
            split_stream_out[1].recv(result1);
            $display("Stream 1: %h, %b", result1, split_stream_out_last[1]);
            split_stream_out[1].recv(result1);
            $display("Stream 1: %h, %b", result1, split_stream_out_last[1]);
            split_stream_out[1].recv(result1);
            $display("Stream 1: %h, %b", result1, split_stream_out_last[1]);
        end
        join

        $display("Last ordering split merge test finished (see results above)!");
        $finish();

    end

endmodule
