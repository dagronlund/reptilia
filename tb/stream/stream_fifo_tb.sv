//!import std/std_pkg
//!import std/stream_pkg
//!import stream/stream_intf
//!import stream/stream_fifo

`timescale 1ns/1ps

module stream_fifo_tb 
    import std_pkg::*;
    import stream_pkg::*;
#()();

    logic fifo_comb_success, fifo_comb_failure;
    logic fifo_comb_reg_success, fifo_comb_reg_failure;
    logic fifo_seq_success, fifo_seq_failure;
    logic fifo_seq_reg_success, fifo_seq_reg_failure;

    stream_fifo_param_tb #(
        .FIFO_MODE(STREAM_FIFO_MODE_COMBINATIONAL),
        .FIFO_ADDRESS_MODE(STREAM_FIFO_ADDRESS_MODE_POINTERS),
        .DEPTH(16)
    ) stream_fifo_param_tb_comb_inst (
        .success(fifo_comb_success),
        .failure(fifo_comb_failure)
    );

    stream_fifo_param_tb #(
        .FIFO_MODE(STREAM_FIFO_MODE_COMBINATIONAL_REGISTERED),
        .FIFO_ADDRESS_MODE(STREAM_FIFO_ADDRESS_MODE_POINTERS),
        .DEPTH(16)
    ) stream_fifo_param_tb_comb_reg_inst (
        .success(fifo_comb_reg_success),
        .failure(fifo_comb_reg_failure)
    );

    stream_fifo_param_tb #(
        .FIFO_MODE(STREAM_FIFO_MODE_SEQUENTIAL),
        .FIFO_ADDRESS_MODE(STREAM_FIFO_ADDRESS_MODE_POINTERS),
        .DEPTH(16)
    ) stream_fifo_param_tb_seq_inst (
        .success(fifo_seq_success),
        .failure(fifo_seq_failure)
    );

    stream_fifo_param_tb #(
        .FIFO_MODE(STREAM_FIFO_MODE_SEQUENTIAL_REGISTERED),
        .FIFO_ADDRESS_MODE(STREAM_FIFO_ADDRESS_MODE_POINTERS),
        .DEPTH(16)
    ) stream_fifo_param_tb_seq_reg_inst (
        .success(fifo_seq_reg_success),
        .failure(fifo_seq_reg_failure)
    );

    initial begin
        while ('b1) begin
            if (fifo_comb_failure)
                $fatal("Error!");
            if (fifo_comb_reg_failure)
                $fatal("Error!");
            if (fifo_seq_failure)
                $fatal("Error!");
            if (fifo_seq_reg_failure)
                $fatal("Error!");
            if (fifo_comb_success && fifo_comb_reg_success &&
                    fifo_seq_success && fifo_seq_reg_success)
                $finish();
            #5;
        end
    end

endmodule

module stream_fifo_param_tb
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter stream_fifo_mode_t FIFO_MODE = STREAM_FIFO_MODE_COMBINATIONAL_REGISTERED,
    parameter stream_fifo_address_mode_t FIFO_ADDRESS_MODE = STREAM_FIFO_ADDRESS_MODE_POINTERS,
    parameter int DEPTH = 16
)(
    output logic success, failure
);

    localparam int NUM_TRIALS = 1024;
    localparam std_clock_info_t CLOCK_INFO = 'b0;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    stream_intf #(.T(int)) stream_in (.clk, .rst);
    stream_intf #(.T(int)) stream_out (.clk, .rst);

    stream_fifo #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(STD_TECHNOLOGY_FPGA_XILINX),
        .FIFO_MODE(FIFO_MODE),
        .FIFO_ADDRESS_MODE(FIFO_ADDRESS_MODE),
        .DEPTH(DEPTH),
        .T(int)
    ) stream_fifo_inst (
        .clk, .rst,
        .stream_in, 
        .stream_out
    );

    initial begin
        automatic int write_count;

        success = 'b0;
        failure = 'b0;

        stream_in.valid = 'b0;
        stream_out.ready = 'b0;

        while (std_is_reset_active(CLOCK_INFO, rst)) @ (posedge clk);

        // Check that FIFO can handle being filled to at least DEPTH - 1
        write_count = 0;
        while (write_count < (DEPTH - 1)) begin
            stream_in.valid <= 'b1;
            stream_in.payload <= 'h42;
            @ (posedge clk);
            if (!stream_in.ready) begin
                $error("FIFO not ready at fill of %d, expected at least %d", write_count, DEPTH - 1);
                failure = 'b1;
            end
            write_count += 1;
        end
        stream_in.valid <= 'b0;

        // Empty the FIFO
        while (write_count > 0) begin
            stream_out.ready <= 'b1;
            @ (posedge clk);
            while (!(stream_out.valid && stream_out.ready))
                @ (posedge clk);
            write_count -= 1;
        end
        stream_out.ready <= 'b0;

        @ (posedge clk);
        @ (posedge clk);
        @ (posedge clk);

        // Check that FIFO can handle random flow control signals
        fork
        // Send incrementing numbers
        for (int i = 0; i < NUM_TRIALS; i++) begin
            stream_in.payload <= i;
            @ (posedge clk);
            while (!(stream_in.valid && stream_in.ready))
                @ (posedge clk);
        end

        // Receive and check incrementing numbers
        begin
            for (int i = 0; i < NUM_TRIALS; i++) begin
                @ (posedge clk);
                while (!(stream_out.valid && stream_out.ready))
                    @ (posedge clk);
                if (i != stream_out.payload) begin
                    $error("Stream FIFO test failed! %d != %d", i, stream_out.payload);
                    failure = 'b1;
                end
            end
            $display("Stream FIFO test succeeded!");
            success = 'b1;
        end

        // Randomly set external valid and ready
        while ('b1) begin
            @ (posedge clk);
            stream_in.valid <= $urandom();
            stream_out.ready <= $urandom();
        end
        join

    end

endmodule
