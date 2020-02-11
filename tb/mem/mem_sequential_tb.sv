//!import std/std_pkg
//!import std/stream_pkg
//!import stream/stream_intf
//!import stream/stream_stage
//!import mem/mem_intf
//!import mem/mem_sequential_single

`timescale 1ns/1ps

// module mem_sequential_tb
//     import std_pkg::*;
//     import stream_pkg::*;
// #()();

//     mem_sequential_base_tb #(.ENABLE_OUTPUT_REG(0)) output_tb_inst();
//     mem_sequential_base_tb #(.ENABLE_OUTPUT_REG(1)) output_reg_tb_inst();

// endmodule

// module mem_sequential_base_tb
module mem_sequential_tb
    import std_pkg::*;
    import stream_pkg::*;
#(
    // parameter logic ENABLE_OUTPUT_REG = 0
)();

    localparam int NUM_TRIALS = 1024;
    localparam std_clock_info_t CLOCK_INFO = 'b0;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4), .ADDR_BYTE_SHIFTED(0)) mem_in (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4), .ADDR_BYTE_SHIFTED(0)) mem_out_pre_stage (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4), .ADDR_BYTE_SHIFTED(0)) mem_out (.clk, .rst);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4), .ADDR_BYTE_SHIFTED(0)) mem_in0 (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4), .ADDR_BYTE_SHIFTED(0)) mem_in1 (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4), .ADDR_BYTE_SHIFTED(0)) mem_out0 (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4), .ADDR_BYTE_SHIFTED(0)) mem_out1 (.clk, .rst);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4), .ADDR_BYTE_SHIFTED(0)) mem_write_in (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4), .ADDR_BYTE_SHIFTED(0)) mem_read_in (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(10), .ID_WIDTH(4), .ADDR_BYTE_SHIFTED(0)) mem_read_out (.clk, .rst);

    mem_sequential_single #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(STD_TECHNOLOGY_FPGA_XILINX),
        .ENABLE_OUTPUT_REG(1)
    ) mem_sequential_single_inst (
        .clk, .rst,
        .mem_in, .mem_out(mem_out_pre_stage)
    );

    mem_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_REGISTERED)
    ) mem_stage_inst (
        .clk, .rst,
        .mem_in(mem_out_pre_stage),
        .mem_out(mem_out)
    );

    mem_sequential_double #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(STD_TECHNOLOGY_FPGA_XILINX),
        .ENABLE_OUTPUT_REG0(1),
        .ENABLE_OUTPUT_REG1(1)
    ) mem_sequential_double_inst (
        .clk, .rst,
        .mem_in0, .mem_out0,
        .mem_in1, .mem_out1
    );

    mem_sequential_read_write #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(STD_TECHNOLOGY_FPGA_XILINX),
        .ENABLE_OUTPUT_REG(1)
    ) mem_sequential_read_write_inst (
        .clk, .rst,
        .mem_write_in,
        .mem_read_in,
        .mem_read_out
    );

    initial begin
        mem_in.valid = 'b0;
        mem_in.write_enable = 'b0;
        mem_in.read_enable = 'b0;
        mem_in.addr = 'b0;
        mem_in.data = 'b0;
        mem_in.id = 'b0;
        mem_out.ready = 'b0;

        while (std_is_reset_active(CLOCK_INFO, rst)) @ (posedge clk);

        fork
        // Send incrementing numbers
        begin
            // Fill up memory with decrementing numbers
            for (int i = 0; i < NUM_TRIALS; i++) begin
                mem_in.read_enable <= 'b0;
                mem_in.write_enable <= 'hf;
                mem_in.addr <= i;
                mem_in.data <= (NUM_TRIALS - i - 1);
                mem_in.id <= i[3:0];

                @ (posedge clk);
                while (!(mem_in.valid && mem_in.ready))
                    @ (posedge clk);
            end

            // Read out decrementing numbers from memory
            // Sets up incorrect write but this should be ignored
            for (int i = 0; i < NUM_TRIALS; i++) begin
                mem_in.read_enable <= 'b1;
                mem_in.write_enable <= 'b0;
                mem_in.addr <= i;
                mem_in.data <= i;
                mem_in.id <= i[3:0];

                @ (posedge clk);
                while (!(mem_in.valid && mem_in.ready))
                    @ (posedge clk);
            end

            // Read same values as last time and write new ones
            // Tests the read-first functionality of the memory
            for (int i = 0; i < NUM_TRIALS; i++) begin
                mem_in.read_enable <= 'b1;
                mem_in.write_enable <= 'hf;
                mem_in.addr <= i;
                mem_in.data <= i;
                mem_in.id <= i[3:0];

                @ (posedge clk);
                while (!(mem_in.valid && mem_in.ready))
                    @ (posedge clk);
            end

            // Finally read out incrementing values from the last write
            for (int i = 0; i < NUM_TRIALS; i++) begin
                mem_in.read_enable <= 'b1;
                mem_in.write_enable <= 'b0;
                mem_in.addr <= i;
                mem_in.data <= i;
                mem_in.id <= i[3:0];

                @ (posedge clk);
                while (!(mem_in.valid && mem_in.ready))
                    @ (posedge clk);
            end
        end


        // Check the three separate read phases
        begin
            for (int i = 0; i < NUM_TRIALS; i++) begin
                @ (posedge clk);
                while (!(mem_out.valid && mem_out.ready))
                    @ (posedge clk);
                if ((NUM_TRIALS - i - 1) != mem_out.data) begin
                    $fatal("Memory test failed! %d != %d", (NUM_TRIALS - i - 1), mem_out.data);
                end
                if (i[3:0] != mem_out.id) begin
                    $fatal("Memory test failed! %d, %d", i[3:0], mem_out.id);
                end
            end
            for (int i = 0; i < NUM_TRIALS; i++) begin
                @ (posedge clk);
                while (!(mem_out.valid && mem_out.ready))
                    @ (posedge clk);
                if ((NUM_TRIALS - i - 1) != mem_out.data) begin
                    $fatal("Memory test failed! %d != %d", (NUM_TRIALS - i - 1), mem_out.data);
                end
                if (i[3:0] != mem_out.id) begin
                    $fatal("Memory test failed! %d, %d", i[3:0], mem_out.id);
                end
            end
            for (int i = 0; i < NUM_TRIALS; i++) begin
                @ (posedge clk);
                while (!(mem_out.valid && mem_out.ready))
                    @ (posedge clk);
                if (i != mem_out.data) begin
                    $fatal("Memory test failed! %d != %d", i, mem_out.data);
                end
                if (i[3:0] != mem_out.id) begin
                    $fatal("Memory test failed! %d, %d", i[3:0], mem_out.id);
                end
            end

            $display("Memory test succeeded!");
            $finish();
        end

        // Randomly set external valid and ready
        while ('b1) begin
            @ (posedge clk);
            mem_in.valid <= $urandom();
            mem_out.ready <= $urandom();
        end
        join

    end

endmodule
