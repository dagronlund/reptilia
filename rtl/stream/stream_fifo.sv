//!import std/std_pkg
//!import std/std_register
//!import std/std_register_granular
//!import stream/stream_pkg

`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
`else
    `include "std_util.svh"
`endif

/*
Implements a valid/ready controlled FIFO. The FIFO mas two main settings that
determine its internal construction, but the same contracts regarding in/out 
streams hold here as hold for the stream stage module.

For anyone who has used another synchronous FIFO implementation from another
libary, you have no idea how flexible and easy to use this one is.

FIFO_MODE
    STREAM_FIFO_MODE_COMBINATIONAL
        This setting uses a combinational memory element like a distributed-RAM
        (FPGA) or the ASIC equivalent where values are read out of the memory
        combinationally with no clock cycle penalty. These memories are usually
        more efficient for very small FIFOs (4 to ~256 entries) and have a lower
        latency penalty than larger memories, which improves the packet time
        through the FIFO when it is empty.

    STREAM_FIFO_MODE_COMBINATIONAL_REGISTERED
        Uses the same combinational memory element but puts an output register
        after it along with the relevant stream stage handling logic. This is
        the default FIFO setting since it both small and relatively high
        performance, since any data launch from a register rather than a memory.

    STREAM_FIFO_MODE_SEQUENTIAL
        This uses a sequential memory element like an BRAM (FPGA) or SRAM (ASIC)
        to store data. While this configuration has the potential for much more
        efficient storage, it will incur a latency penalty on the time it takes
        for a packet to emerge from a FIFO that starts out empty.

    STREAM_FIFO_MODE_SEQUENTIAL_REGISTERED:
        This mode will use the same memory as STREAM_FIFO_MODE_SEQUENTIAL but
        will also use the integrated output register of the FIFO if it is
        available in that technology. If the technology does not have an
        explicit output register, then one will be added using normal registers.
        This will increase empty FIFO latency but hopefully improve timing.

FIFO_ADDRESS_MODE
    STREAM_FIFO_ADDRESS_MODE_POINTERS
        This will use the normal read/write pointers a traditional FIFO would
        be described as using. To prevent the need for the ready signal to
        combinationally propagate through the FIFO, the maximum capacity of the
        FIFO is (2^DEPTH)-1 since the read and write pointers cannot equal each
        other than to indicate the FIFO is empty.

    STREAM_FIFO_ADDRESS_MODE_FLAGS
        This addressing mode will look very similar to the one-hot encoding used
        in the buffered mode of a stream stage. Essentially DEPTH number of
        registers are created, each of which represents whether that entry in
        the memory contains a valid entry. This approach does allow for the FIFO
        to completely fill with DEPTH entries, but at the cost of more registers
        especially for large values of DEPTH. This addressing mode is not
        advised for FIFOs really any bigger than 16 entries, but can be useful
        when you need to be able to fill the entirety of a small FIFO.
*/
module stream_fifo
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter stream_fifo_mode_t FIFO_MODE = STREAM_FIFO_MODE_COMBINATIONAL_REGISTERED,
    parameter stream_fifo_address_mode_t FIFO_ADDRESS_MODE = STREAM_FIFO_ADDRESS_MODE_POINTERS,
    parameter int DEPTH = 16,
    parameter type T = logic
)(
    input wire clk, 
    input wire rst,

    stream_intf.in stream_in,
    stream_intf.out stream_out
);

    `STATIC_ASSERT($bits(T) == $bits(stream_in.payload))
    `STATIC_ASSERT($bits(T) == $bits(stream_out.payload))

    localparam int DATA_WIDTH = $bits(T);
    localparam int POINTER_WIDTH = $clog2(DEPTH);
    typedef logic [POINTER_WIDTH-1:0] pointer_t;
    typedef logic [DEPTH-1:0] flag_t;

    logic read_pointer_enable, write_pointer_enable;
    pointer_t read_pointer, write_pointer;
    logic full, empty;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(pointer_t),
        .RESET_VECTOR('b0)
    ) read_pointer_register_inst (
        .clk, .rst,
        .enable(read_pointer_enable),
        .next(read_pointer + 'b1),
        .value(read_pointer)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(pointer_t),
        .RESET_VECTOR('b0)
    ) write_pointer_register_inst (
        .clk, .rst,
        .enable(write_pointer_enable),
        .next(write_pointer + 'b1),
        .value(write_pointer)
    );

    generate
    if (FIFO_ADDRESS_MODE == STREAM_FIFO_ADDRESS_MODE_POINTERS) begin

        always_comb begin
            full = (read_pointer == (write_pointer + 'b1));
            empty = (read_pointer == write_pointer);
        end

    end else begin

        flag_t next_flags, current_flags, enable_flags;

        std_register_granular #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(flag_t),
            .RESET_VECTOR('b0)
        ) flag_register_inst (
            .clk, .rst,
            .enable(enable_flags),
            .next(next_flags),
            .value(current_flags)
        );

        always_comb begin
            next_flags = 'b0;
            enable_flags = 'b0;

            empty = !current_flags[read_pointer];
            full = current_flags[write_pointer];

            if (read_pointer_enable) begin
                next_flags[read_pointer] = 'b0;
                enable_flags[read_pointer] = 'b1;
            end

            if (write_pointer_enable) begin
                next_flags[write_pointer] = 'b1;
                enable_flags[write_pointer] = 'b1;
            end
        end

    end

    if (FIFO_MODE == STREAM_FIFO_MODE_COMBINATIONAL
            || FIFO_MODE == STREAM_FIFO_MODE_COMBINATIONAL_REGISTERED) begin

        localparam stream_pipeline_mode_t OUTPUT_PIPELINE_MODE = 
                (FIFO_MODE == STREAM_FIFO_MODE_COMBINATIONAL_REGISTERED) ?
                STREAM_PIPELINE_MODE_REGISTERED :
                STREAM_PIPELINE_MODE_TRANSPARENT;

        logic mem_write_enable;

        stream_intf #(.T(T)) stream_next (.clk, .rst);

        mem_combinational #(
            .CLOCK_INFO(CLOCK_INFO),
            .TECHNOLOGY(TECHNOLOGY),
            .DATA_WIDTH($bits(T)),
            .ADDR_WIDTH($clog2(DEPTH)),
            .READ_PORTS(1),
            .AUTO_RESET(0)
        ) mem_combinational_inst (
            .clk, .rst,

            .write_enable({DATA_WIDTH{mem_write_enable}}),
            .write_addr(write_pointer),
            .write_data_in(stream_in.payload),

            .read_addr('{read_pointer}),
            .read_data_out('{stream_next.payload})
        );

        always_comb begin
            // Input stream logic
            stream_in.ready = !full;
            mem_write_enable = stream_in.valid && stream_in.ready;
            write_pointer_enable = mem_write_enable;

            // Output stream logic
            stream_next.valid = !empty;
            read_pointer_enable = stream_next.valid && stream_next.ready;
        end

        stream_stage #(
            .CLOCK_INFO(CLOCK_INFO),
            .PIPELINE_MODE(OUTPUT_PIPELINE_MODE),
            .T(T)
        ) stream_stage_transparent_inst (
            .clk, .rst,
            .stream_in(stream_next), .stream_out
        );

    end else if (FIFO_MODE == STREAM_FIFO_MODE_SEQUENTIAL
            || FIFO_MODE == STREAM_FIFO_MODE_SEQUENTIAL_REGISTERED) begin

        localparam logic ENABLE_OUTPUT_REG = 
                (FIFO_MODE == STREAM_FIFO_MODE_SEQUENTIAL_REGISTERED);

        mem_intf #(.DATA_WIDTH($bits(T)), .ADDR_WIDTH(POINTER_WIDTH)) mem_read_in (.clk, .rst);
        mem_intf #(.DATA_WIDTH($bits(T)), .ADDR_WIDTH(POINTER_WIDTH)) mem_read_out (.clk, .rst);
        mem_intf #(.DATA_WIDTH($bits(T)), .ADDR_WIDTH(POINTER_WIDTH)) mem_write_in (.clk, .rst);

        mem_sequential_read_write #(
            .CLOCK_INFO(CLOCK_INFO),
            .TECHNOLOGY(TECHNOLOGY),
            .MANUAL_ADDR_WIDTH(POINTER_WIDTH),
            .ENABLE_OUTPUT_REG(ENABLE_OUTPUT_REG)
        ) mem_sequential_read_write_inst (
            .clk, .rst,

            .mem_read_in,
            .mem_read_out,
            .mem_write_in
        );

        always_comb begin
            // Write memory interface
            stream_in.ready = !full;
            write_pointer_enable = stream_in.valid && stream_in.ready;
            mem_write_in.valid = write_pointer_enable;
            mem_write_in.addr = write_pointer;
            mem_write_in.data = stream_in.payload;

            // Read in memory interface
            mem_read_in.valid = !empty;
            read_pointer_enable = mem_read_in.valid && mem_read_in.ready;
            mem_read_in.addr = read_pointer;

            // Read out memory interface
            stream_out.valid = mem_read_out.valid;
            mem_read_out.ready = stream_out.ready;
            stream_out.payload = mem_read_out.data;
        end

    end
    endgenerate

endmodule
