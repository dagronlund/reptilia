`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "../mem/mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

/*
    Address Division: Tag, Index, Block
    Cache Metadata:
        Each Cache Line has
        Valid, Dirty, LRU, Tag
*/
module cache_decode
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,

    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int CHILD_DATA_WIDTH = 32,

    parameter int BLOCK_ADDR_WIDTH = 6,
    parameter int INDEX_ADDR_BITS = 6,
    parameter int ASSOCIATIVITY = 1,

    parameter int DATA_WIDTH_RATIO = DATA_WIDTH / CHILD_DATA_WIDTH,
    parameter int SUB_BLOCK_ADDR_WIDTH = BLOCK_ADDR_WIDTH - $clog2(DATA_WIDTH_RATIO)
)(
    input logic clk, rst,
    
    mem_intf.in child_request,
    mem_intf.in parent_response,
    
    mem_intf.out local_request,
    stream_intf.out local_request_meta, // local_meta_t
    stream_intf.out bypass_request // bypass_t
);

    localparam int WORD_BITS = $clog2(DATA_WIDTH/8);
    localparam int CHILD_WORD_BITS = $clog2(CHILD_DATA_WIDTH/8);

    localparam int TAG_BITS = 32 - BLOCK_ADDR_WIDTH - INDEX_ADDR_BITS - WORD_BITS;
    localparam int LRU_BITS = ($clog2(ASSOCIATIVITY) > 1) ? $clog2(ASSOCIATIVITY) : 1;
    localparam int LOCAL_ADDR_WIDTH = BLOCK_ADDR_WIDTH + INDEX_ADDR_BITS;

    `STATIC_ASSERT(ADDR_WIDTH == $bits(child_request.addr))
    `STATIC_ASSERT(LOCAL_ADDR_WIDTH == $bits(local_request.addr))
    `STATIC_ASSERT(ADDR_WIDTH == $bits(parent_response.addr))

    `STATIC_ASSERT(DATA_WIDTH >= CHILD_DATA_WIDTH)
    `STATIC_ASSERT(DATA_WIDTH == $bits(local_request.data))
    `STATIC_ASSERT(CHILD_DATA_WIDTH == $bits(child_request.data))

    `STATIC_ASSERT($bits(child_request.id) == $bits(local_request.id))

    typedef logic [ADDR_WIDTH-1:0] addr_t;
    typedef logic [LOCAL_ADDR_WIDTH-1:0] local_addr_t;
    typedef logic [BLOCK_ADDR_WIDTH-1:0] block_t;
    typedef logic [SUB_BLOCK_ADDR_WIDTH-1:0] sub_block_t;
    typedef logic [TAG_BITS-1:0] tag_t;
    typedef logic [LRU_BITS-1:0] lru_t;
    typedef logic [INDEX_ADDR_BITS-1:0] index_t;
    
    typedef enum logic [1:0] {
        CACHE_NORMAL,
        CACHE_FILL,
        CACHE_EVICT,
        CACHE_PENDING
    } state_t;

    // Identical type in cache_encode
    typedef struct packed {
        logic id;
        logic send_parent;
        addr_t addr;
    } local_meta_t;

    // Identical type in cache_encode
    typedef struct packed {
        logic id;
        addr_t addr;
    } bypass_t;

    typedef struct packed {
        tag_t tag;
        index_t index;
        block_t block; // Includes unused LSB of address
    } addr_decoded_t;

    typedef struct packed {
        logic valid, dirty;
        tag_t tag;
        lru_t lru;
    } line_meta_t;

    // typedef struct packed {
    //     line_meta_t line_meta [ASSOCIATIVITY];
    // } row_meta_t;

    function automatic addr_decoded_t decode_address(
        input addr_t addr
    );
        return '{
            tag: addr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_BITS],
            index: addr[ADDR_WIDTH-TAG_BITS-1:ADDR_WIDTH-TAG_BITS-INDEX_ADDR_BITS],
            block: addr[ADDR_WIDTH-TAG_BITS-INDEX_ADDR_BITS-1:ADDR_WIDTH-TAG_BITS-INDEX_ADDR_BITS-BLOCK_ADDR_WIDTH]
        };
    endfunction

    function automatic addr_t encode_address(
        input tag_t tag,
        input index_t index,
        input block_t block
    );
        return {tag, index, block, {WORD_BITS{1'b0}}};
    endfunction

    function automatic addr_t encode_sub_address(
        input tag_t tag,
        input index_t index,
        input sub_block_t sub_block
    );
        return {tag, index, sub_block, {(WORD_BITS+$clog2(DATA_WIDTH_RATIO)){1'b0}}};
    endfunction

    function automatic local_addr_t get_local_address(
        input addr_t addr
    );
        addr_decoded_t decoded = decode_address(addr);
        return {decoded.index, decoded.block};
    endfunction

    // Lower LRU means it was modified the latest
    function automatic line_meta_t [ASSOCIATIVITY-1:0] update_lru(
        input line_meta_t [ASSOCIATIVITY-1:0] meta_in,
        input lru_t modified_index
    );
        for (int i = 0; i < ASSOCIATIVITY; i++) begin
            if (meta_in[modified_index].lru < meta_in[i].lru) begin
                meta_in[i].lru += 'b1;
            end
        end

        meta_in[modified_index].lru = 'b0;

        return meta_in;
    endfunction

    logic enable;
    logic consume_child, consume_parent;
    logic produce_local_request, produce_local_request_meta, produce_bypass_request;

    stream_intf #(.T(bypass_t)) next_bypass_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(LOCAL_ADDR_WIDTH), 
                .ID_WIDTH($bits(child_request.id))) next_local_request (.clk, .rst);
    stream_intf #(.T(local_meta_t)) next_local_request_meta (.clk, .rst);

    stream_controller #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(3)
    ) stream_controller_inst (
        .clk, .rst,

        .valid_input({child_request.valid, parent_response.valid}),
        .ready_input({child_request.ready, parent_response.ready}),

        .valid_output({next_local_request.valid, next_local_request_meta.valid, next_bypass_request.valid}),
        .ready_output({next_local_request.ready, next_local_request_meta.ready, next_bypass_request.ready}),

        .consume({consume_child, consume_parent}), 
        .produce({produce_local_request, produce_local_request_meta, produce_bypass_request}), 
        .enable
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(bypass_t)
    ) bypass_request_stream_stage_inst (
        .clk, .rst,
        .stream_in(next_bypass_request), .stream_out(bypass_request)
    );

    mem_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE)
    ) local_request_stream_stage_inst (
        .clk, .rst,
        .mem_in(next_local_request), .mem_out(local_request)
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(local_meta_t)
    ) local_request_meta_stream_stage_inst (
        .clk, .rst,
        .stream_in(next_local_request_meta), .stream_out(local_request_meta)
    );

    logic reset_done;

    logic metadata_write_enable;
    index_t metadata_addr;
    line_meta_t [ASSOCIATIVITY-1:0] metadata_write_data, metadata_read_data, metadata_dummy;

    state_t current_state, next_state;
    tag_t current_residual_tag, next_residual_tag;
    sub_block_t current_front_sub_block, next_front_sub_block;
    sub_block_t current_rear_sub_block, next_rear_sub_block;
    logic current_id, next_id;

    logic [$bits(state_t)-1:0] current_state_temp;
    assign current_state = state_t'(current_state_temp);

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic [1:0]),
        .RESET_VECTOR(CACHE_NORMAL)
    ) state_register_inst (
        .clk, .rst,
        .enable,
        .next(next_state),
        .value(current_state_temp)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(sub_block_t),
        .RESET_VECTOR('b0)
    ) front_sub_block_register_inst (
        .clk, .rst,
        .enable,
        .next(next_front_sub_block),
        .value(current_front_sub_block)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(sub_block_t),
        .RESET_VECTOR('b0)
    ) rear_sub_block_register_inst (
        .clk, .rst,
        .enable,
        .next(next_rear_sub_block),
        .value(current_rear_sub_block)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(tag_t),
        .RESET_VECTOR('b0)
    ) residual_tag_register_inst (
        .clk, .rst,
        .enable,
        .next(next_residual_tag),
        .value(current_residual_tag)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic),
        .RESET_VECTOR('b0)
    ) id_register_inst (
        .clk, .rst,
        .enable,
        .next(next_id),
        .value(current_id)
    );

    // Cache metadata storage
    mem_combinational #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .DATA_WIDTH($bits(metadata_write_data)),
        .ADDR_WIDTH(INDEX_ADDR_BITS),
        .READ_PORTS(1),
        .AUTO_RESET(1)
    ) cache_metadata_inst (
        .clk, .rst,

        .write_enable(enable && metadata_write_enable),
        .write_addr(metadata_addr),
        .write_data_in(metadata_write_data),
        .write_data_out(metadata_read_data),

        .read_addr({metadata_addr}),
        .read_data_out({metadata_dummy}),

        .reset_done
    );

    always_comb begin
        automatic logic miss = 'b1, has_empty = 'b0;
        automatic lru_t found_line = 'b0, empty_line = 'b0, last_used_line = 'b0;
        automatic addr_decoded_t decoded_addr = decode_address(child_request.addr);

        next_state = current_state;
        next_front_sub_block = current_front_sub_block;
        next_rear_sub_block = current_rear_sub_block;
        next_residual_tag = current_residual_tag;
        next_id = current_id;

        consume_child = 'b0;
        consume_parent = 'b0;
        produce_local_request = 'b0;
        produce_local_request_meta = 'b0;
        produce_bypass_request = 'b0;

        metadata_write_enable = 'b0;
        metadata_addr = decoded_addr.index;
        metadata_write_data = metadata_read_data;

        // Set defaults for local_request, where child_request is possibly less
        // wide than the local request and write enable needs to be shifted
        next_local_request.read_enable = child_request.read_enable;
        if (DATA_WIDTH_RATIO > 1) begin
            next_local_request.write_enable = child_request.write_enable << 
                    (child_request.addr[$clog2(DATA_WIDTH_RATIO)+CHILD_WORD_BITS-1:CHILD_WORD_BITS] 
                    << $clog2(CHILD_DATA_WIDTH/8));        
        end else begin
            next_local_request.write_enable = child_request.write_enable;
        end
        next_local_request.addr = get_local_address(child_request.addr);
        next_local_request.data = {DATA_WIDTH_RATIO{child_request.data}};
        next_local_request.id = child_request.id;

        // Search associated lines for hit, empty, and last used lines
        for (int i = 0; i < ASSOCIATIVITY; i++) begin
            if (metadata_read_data[i].valid && 
                    metadata_read_data[i].tag == decoded_addr.tag) begin
                miss = 'b0;
                found_line = i;
            end
            if (!metadata_read_data[i].valid) begin
                has_empty = 'b1;
                empty_line = i;
            end
            if (metadata_read_data[i].lru > metadata_read_data[last_used_line].lru) begin
                last_used_line = i;
            end
        end

        if (reset_done) begin
            case (current_state)
            CACHE_NORMAL: begin
                if (child_request.valid) begin
                    if (miss) begin
                        if (has_empty) begin // Empty line to fill
                            metadata_write_enable = 'b1;
                            metadata_write_data[empty_line].valid = 'b1;
                            metadata_write_data[empty_line].dirty = 'b0;
                            metadata_write_data[empty_line].tag = decoded_addr.tag;

                            next_state = CACHE_FILL;
                        end else begin // No empty line to fill
                            metadata_write_enable = 'b1;
                            metadata_write_data[last_used_line].valid = 'b1;
                            metadata_write_data[last_used_line].dirty = 'b0;
                            metadata_write_data[last_used_line].tag = decoded_addr.tag;

                            if (!metadata_read_data[last_used_line].dirty) begin
                                next_state = CACHE_FILL; // No need to evict clean line
                            end else begin
                                next_state = CACHE_EVICT;
                            end
                        end

                        next_front_sub_block = 'b0;
                        next_rear_sub_block = 'b0;
                        // We only need the tag from a line being evicted
                        next_residual_tag = metadata_read_data[last_used_line].tag;
                    end else begin // Hit
                        consume_child = 'b1;

                        // Update LRU and dirty bit in table
                        metadata_write_enable = 'b1;
                        metadata_write_data = update_lru(metadata_read_data, found_line);
                        metadata_write_data[found_line].dirty |= (|child_request.write_enable);

                        // Send default local memory request
                        produce_local_request = 'b1;
                        produce_local_request_meta = child_request.read_enable;

                        // We really only need to fill out the id
                        next_local_request_meta.payload.id = current_id;
                        next_local_request_meta.payload.send_parent = 'b0;
                        next_local_request_meta.payload.addr = child_request.addr;

                        next_id = current_id + 'b1;
                    end
                end
            end
            CACHE_EVICT: begin
                produce_local_request = 'b1;
                produce_local_request_meta = 'b1;

                next_local_request.read_enable = 'b1;
                next_local_request.write_enable = 'b0;
                // Address is the index + the sub-block address we are currently on
                next_local_request.addr = {decoded_addr.index, current_front_sub_block};
                next_local_request.data = child_request.data; // The data does not matter here

                next_local_request_meta.payload.id = current_id;
                next_local_request_meta.payload.send_parent = 'b1;
                next_local_request_meta.payload.addr = encode_sub_address(
                        current_residual_tag, decoded_addr.index, current_front_sub_block);

                next_id = current_id + 'b1;

                next_front_sub_block = current_front_sub_block + 'b1;

                if (next_front_sub_block == 'b0) begin
                    next_state = CACHE_FILL;
                end
            end
            CACHE_FILL: begin
                // Issue bypass requests
                produce_bypass_request = 'b1;
                next_bypass_request.payload = '{
                    id: current_id,
                    addr: encode_sub_address(decoded_addr.tag, decoded_addr.index, current_front_sub_block)
                };
                next_id = current_id + 'b1;

                next_front_sub_block = current_front_sub_block + 'b1;

                if (next_front_sub_block == 'b0) begin
                    next_state = CACHE_PENDING;
                end

                // Consume parent responses if available
                if (parent_response.valid) begin
                    consume_parent = 'b1;
                    produce_local_request = 'b1;
                    next_rear_sub_block = current_rear_sub_block + 'b1;
                end
                next_local_request.read_enable = 'b0;
                next_local_request.write_enable = {(DATA_WIDTH/8){1'b1}};
                next_local_request.addr = {decoded_addr.index, current_rear_sub_block};
                next_local_request.data = parent_response.data;
            end
            CACHE_PENDING: begin
                // Pend completely on the parent responses
                consume_parent = 'b1;
                produce_local_request = 'b1;
                next_rear_sub_block = current_rear_sub_block + 'b1;

                next_local_request.read_enable = 'b0;
                next_local_request.write_enable = {(DATA_WIDTH/8){1'b1}};
                next_local_request.addr = {decoded_addr.index, current_rear_sub_block};
                next_local_request.data = parent_response.data;

                if (next_rear_sub_block == 'b0) begin
                    next_state = CACHE_NORMAL;
                end
            end
            endcase
        end
    end

endmodule
