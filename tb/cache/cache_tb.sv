//!import std/std_pkg
//!import std/stream_pkg
//!import stream/stream_intf
//!import stream/stream_stage
//!import mem/mem_intf
//!import mem/mem_sequential_single

`timescale 1ns/1ps

module cache_tb
    import std_pkg::*;
    import stream_pkg::*;
    import cache_pkg::*;
#(
)();

    localparam std_clock_info_t CLOCK_INFO = 'b0;
    localparam int PORTS = 1;
    localparam int ADDR_WIDTH = 32;
    localparam int CHILD_DATA_WIDTH = 32;
    localparam int PARENT_DATA_WIDTH = 32;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    mem_intf #(.DATA_WIDTH(CHILD_DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) child_request [PORTS] (.clk, .rst);
    mem_intf #(.DATA_WIDTH(CHILD_DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) child_response [PORTS] (.clk, .rst);

    cache_mesi_request_t child_request_info [PORTS];
    cache_mesi_response_t child_response_info [PORTS];

    mem_intf #(.DATA_WIDTH(PARENT_DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) parent_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(PARENT_DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) parent_response (.clk, .rst);

    cache_mesi_request_t parent_request_info;
    cache_mesi_response_t parent_response_info;

    cache #(
        .CLOCK_INFO(CLOCK_INFO),
        .PORTS(PORTS),

        // parameter stream_pipeline_mode_t MERGE_PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,
        // parameter stream_pipeline_mode_t DECODE_PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,
        // parameter logic                  MEMORY_OUTPUT_REGISTER = 'b0,
        // parameter stream_pipeline_mode_t ENCODE_PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,
        // parameter stream_pipeline_mode_t SPLIT_PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,

        .BLOCK_ADDR_WIDTH(4),
        .INDEX_ADDR_BITS(6),
        .ASSOCIATIVITY(2),

        .IS_COHERENT(0),
        .IS_LAST_LEVEL(0),
        .IS_FIRST_LEVEL(0)
    ) cache_inst (
        .clk, .rst,

        .child_request, .child_request_info,
        .child_response, .child_response_info,
        .parent_response, .parent_response_info,
        .parent_request, .parent_request_info
    );

    mem_sequential_single #(
        .CLOCK_INFO(CLOCK_INFO),
        .MANUAL_ADDR_WIDTH(16),
        .ADDR_BYTE_SHIFTED(1),
        .ENABLE_OUTPUT_REG(1)
    ) parent_memory (
        .clk, .rst,
        .mem_in(parent_request), .mem_out(parent_response)
    );

    logic read_enable_temp;
    logic [3:0] write_enable_temp;
    logic [31:0] addr_temp, data_temp;
    logic [0:0] id_temp;

    initial begin
        // for (int i = 0; i < PORTS; i++) begin
        //     child_request[i].valid = 'b0;
        //     child_request[i].write_enable = 'b0;
        //     child_request[i].read_enable = 'b0;
        //     child_request[i].addr = 'b0;
        //     child_request[i].data = 'b0;
        //     child_request[i].id = 'b0;

        //     child_response[i].ready = 'b0;
        // end

        child_request_info[0].op = CACHE_MESI_OPERATION_REJECT;
        parent_response_info.op = CACHE_MESI_OPERATION_REJECT;

        child_request[0].valid = 'b0;
        child_request[0].write_enable = 'b0;
        child_request[0].read_enable = 'b0;
        child_request[0].addr = 'b0;
        child_request[0].data = 'b0;
        child_request[0].id = 'b0;
        
        child_response[0].ready = 'b0;

        while (std_is_reset_active(CLOCK_INFO, rst)) @ (posedge clk);

        fork
        begin
            // Read, Write, Addr, Data, Id
            child_request[0].send('b1, 'b0, 'h0, 'h0, 'b0); // Read 0x0
            child_request[0].send('b0, 'b1, 'h0, 'h42, 'b0); // Write 0x0
            child_request[0].send('b0, 'b1, 'h4, 'h69, 'b0); // Write 0x4
            child_request[0].send('b1, 'b0, 'h0, 'h0, 'b0); // Read 0x0
            child_request[0].send('b1, 'b0, 'h4, 'h0, 'b0); // Read 0x4

            // Read something that should associate
            child_request[0].send('b1, 'b0, 'h1 << 12, 'h0, 'b0); // Read 0x1000

            // Read something that should evict the first read
            child_request[0].send('b1, 'b0, 'h2 << 12, 'h0, 'b0); // Read 0x2000
        end
        begin
            child_response[0].recv(read_enable_temp, write_enable_temp, addr_temp, data_temp, id_temp);
            $display("Read back: 0x%h, should be 0x0", data_temp);
            child_response[0].recv(read_enable_temp, write_enable_temp, addr_temp, data_temp, id_temp);
            $display("Read back: 0x%h, should be 0x42", data_temp);
            child_response[0].recv(read_enable_temp, write_enable_temp, addr_temp, data_temp, id_temp);
            $display("Read back: 0x%h, should be 0x69", data_temp);

            child_response[0].recv(read_enable_temp, write_enable_temp, addr_temp, data_temp, id_temp);
            $display("Read back: 0x%h, should be 0x0", data_temp);
            child_response[0].recv(read_enable_temp, write_enable_temp, addr_temp, data_temp, id_temp);
            $display("Read back: 0x%h, should be 0x0", data_temp);
        end
        join

        $finish();

        // child_request[0].valid = 'b0;

        // fork
        // // Send incrementing numbers
        // begin
        //     // Fill up memory with decrementing numbers
        //     for (int i = 0; i < NUM_TRIALS; i++) begin
        //         mem_in.read_enable <= 'b0;
        //         mem_in.write_enable <= 'hf;
        //         mem_in.addr <= i;
        //         mem_in.data <= (NUM_TRIALS - i - 1);
        //         mem_in.id <= i[3:0];

        //         @ (posedge clk);
        //         while (!(mem_in.valid && mem_in.ready))
        //             @ (posedge clk);
        //     end

        //     // Read out decrementing numbers from memory
        //     // Sets up incorrect write but this should be ignored
        //     for (int i = 0; i < NUM_TRIALS; i++) begin
        //         mem_in.read_enable <= 'b1;
        //         mem_in.write_enable <= 'b0;
        //         mem_in.addr <= i;
        //         mem_in.data <= i;
        //         mem_in.id <= i[3:0];

        //         @ (posedge clk);
        //         while (!(mem_in.valid && mem_in.ready))
        //             @ (posedge clk);
        //     end

        //     // Read same values as last time and write new ones
        //     // Tests the read-first functionality of the memory
        //     for (int i = 0; i < NUM_TRIALS; i++) begin
        //         mem_in.read_enable <= 'b1;
        //         mem_in.write_enable <= 'hf;
        //         mem_in.addr <= i;
        //         mem_in.data <= i;
        //         mem_in.id <= i[3:0];

        //         @ (posedge clk);
        //         while (!(mem_in.valid && mem_in.ready))
        //             @ (posedge clk);
        //     end

        //     // Finally read out incrementing values from the last write
        //     for (int i = 0; i < NUM_TRIALS; i++) begin
        //         mem_in.read_enable <= 'b1;
        //         mem_in.write_enable <= 'b0;
        //         mem_in.addr <= i;
        //         mem_in.data <= i;
        //         mem_in.id <= i[3:0];

        //         @ (posedge clk);
        //         while (!(mem_in.valid && mem_in.ready))
        //             @ (posedge clk);
        //     end
        // end


        // // Check the three separate read phases
        // begin
        //     for (int i = 0; i < NUM_TRIALS; i++) begin
        //         @ (posedge clk);
        //         while (!(mem_out.valid && mem_out.ready))
        //             @ (posedge clk);
        //         if ((NUM_TRIALS - i - 1) != mem_out.data) begin
        //             $fatal("Memory test failed! %d != %d", (NUM_TRIALS - i - 1), mem_out.data);
        //         end
        //         if (i[3:0] != mem_out.id) begin
        //             $fatal("Memory test failed! %d, %d", i[3:0], mem_out.id);
        //         end
        //     end
        //     for (int i = 0; i < NUM_TRIALS; i++) begin
        //         @ (posedge clk);
        //         while (!(mem_out.valid && mem_out.ready))
        //             @ (posedge clk);
        //         if ((NUM_TRIALS - i - 1) != mem_out.data) begin
        //             $fatal("Memory test failed! %d != %d", (NUM_TRIALS - i - 1), mem_out.data);
        //         end
        //         if (i[3:0] != mem_out.id) begin
        //             $fatal("Memory test failed! %d, %d", i[3:0], mem_out.id);
        //         end
        //     end
        //     for (int i = 0; i < NUM_TRIALS; i++) begin
        //         @ (posedge clk);
        //         while (!(mem_out.valid && mem_out.ready))
        //             @ (posedge clk);
        //         if (i != mem_out.data) begin
        //             $fatal("Memory test failed! %d != %d", i, mem_out.data);
        //         end
        //         if (i[3:0] != mem_out.id) begin
        //             $fatal("Memory test failed! %d, %d", i[3:0], mem_out.id);
        //         end
        //     end

        //     $display("Memory test succeeded!");
        //     $finish();
        // end

//        // Randomly set external valid and ready
//        while ('b1) begin
//            @ (posedge clk);
//            mem_in.valid <= $urandom();
//            mem_out.ready <= $urandom();
//        end
//        join

    end

endmodule
