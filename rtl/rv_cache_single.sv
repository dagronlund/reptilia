`timescale 1ns/1ps

`include "../lib/rv_util.svh"
`include "../lib/rv_mem.svh"
`include "../lib/rv_cache.svh"

/*
 * Implements a single cycle cache using a simple addressing model of
 * tag, index, and block index in that order. This cache is best used
 * as the cache for a small processor or as L1 for a mid-size processor.
 * Block and row are used as interchangable terms in this module. The cache 
 * meta-memory is implemented as a zero-cyle registered memory file, and the 
 * memory is a dual port single-cycle device memory block. The memory uses a 
 * single port to handle both normal read and write requests, and another for 
 * handling cache load and flush commands. It also lacks any coherency 
 * protocol, requiring a manual flush.
 * 
 * Caches are much faster if allowed to double cycle, stay tuned...
 */
module rv_cache_single #(
    parameter BLOCK_SIZE_BYTES = 64,
    parameter SETS = 64,
    parameter ASSOCIATIVITY = 1
    // parameter ASSOC_BITS = 0, // Direct Associative
    // parameter BLOCK_BITS = 6, // 64 byte cache block/row
    // parameter INDEX_BITS = 6 // Uses 4 kB block RAM
)(
    input logic clk, rst,
    rv_mem_intf.in command, // Inbound Commands
    rv_mem_intf.out result, // Outbound Results
    
    rv_mem_intf.out cache_command, // Outbound Cache Commands
    rv_mem_intf.in cache_result, // Inbound Cache Results

    rv_interrupt_intf.in flush_command // Inbound Flush Commands
);

    import rv_mem::*;

    `STATIC_ASSERT(command.ADDR_BYTE_SHIFTED)
    `STATIC_ASSERT(!command.DATA_ONLY && !cache_command.DATA_ONLY)
    `STATIC_ASSERT(result.DATA_ONLY && cache_result.DATA_ONLY)

    `STATIC_MATCH_MEM(command, result)
    `STATIC_MATCH_MEM(command, cache_command)
    `STATIC_MATCH_MEM(command, cache_result)

    // How wide is the main memory data
    localparam DATA_WIDTH = $bits(command.data);
    // How wide is the main memory address
    localparam ADDR_WIDTH = $bits(command.addr);

    // How many bits are needed for the associative address
    localparam ASSOC_BITS = $clog2(ASSOCIATIVITY);
    // How many associative entries are there (rounded up)
    localparam ASSOC_WIDTH = 2**ASSOC_BITS;

    // How many bits are needed for the index address
    localparam INDEX_BITS = $clog2(SETS);
    // How many index entries are there (rounded up)
    localparam INDEX_WIDTH = 2**INDEX_BITS;

    // How many bits of address are consumed by the data width
    localparam DATA_ADDR_BITS = $clog2(DATA_WIDTH / 8);

    // How many bits wide is the block address (subtract the data width)
    localparam BLOCK_BITS = $clog2(BLOCK_SIZE_BYTES) - DATA_ADDR_BITS;
    // How many block entries are there (rounded up)
    localparam BLOCK_WIDTH = 2**BLOCK_BITS;
    // Shortcut for last block
    localparam logic [BLOCK_BITS:0] MAX_BLOCK = {1'b0, {BLOCK_BITS{1'b1}}};
    // Shortcut for last block
    localparam logic [BLOCK_BITS:0] OVERFLOW_BLOCK = {1'b1, {BLOCK_BITS{1'b0}}};

    // How wide is backing memory address
    localparam LOCAL_ADDR_WIDTH = INDEX_BITS + ASSOC_BITS + BLOCK_BITS;
    // How wide is the cache tag
    localparam TAG_BITS = (ADDR_WIDTH - DATA_ADDR_BITS) - BLOCK_BITS - INDEX_BITS;
    `STATIC_ASSERT(TAG_BITS >= 0)

    // // How deep is the backing memory
    // localparam LOCAL_DATA_LENGTH = 2**LOCAL_ADDR_WIDTH;

    localparam SAFE_ASSOC_BITS = MAX(1, ASSOC_BITS);

    // logic enable, command_block, result_block, 
    //         cache_command_block, cache_result_block;
    // rv_seq_flow_controller #(
    //     .NUM_INPUTS(2),
    //     .NUM_OUTPUTS(2)
    // ) flow_controller_inst (
    //     .clk, .rst, .enable(enable),
    //     .inputs_valid({command.valid, cache_result.valid}), 
    //     .inputs_ready({command.ready, cache_result.ready}),
    //     .inputs_block({command_block, cache_result_block}),

    //     .outputs_valid({result.valid, cache_command.valid}),
    //     .outputs_ready({result.ready, cache_command.ready}),
    //     .outputs_block({result_block, cache_command_block})
    // );

    // TODO: Consider making seperate flow controller endpoints for cache_command and cache_result

    // Only runs memory requests normally
    logic enable, command_block, result_block;
    rv_seq_flow_controller #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) flow_controller_inst (
        .clk, .rst, .enable(enable),
        .inputs_valid({command.valid}), 
        .inputs_ready({command.ready}),
        .inputs_block({command_block}),

        .outputs_valid({result.valid}),
        .outputs_ready({result.ready}),
        .outputs_block({result_block})
    );

    typedef logic [SAFE_ASSOC_BITS-1:0] cache_meta_lru;
    typedef logic [SAFE_ASSOC_BITS-1:0] cache_meta_assoc_index;
    parameter cache_meta_lru MAX_LRU = {SAFE_ASSOC_BITS{1'b1}};

    typedef struct packed {
        logic exists;
        cache_meta_assoc_index index;
    } cache_meta_result;

    typedef struct packed {
        logic valid, dirty;
        logic [TAG_BITS-1:0] tag;
        // The smallest lru is the least recently used
        cache_meta_lru lru; // Uses 1 bit if direct associative
    } cache_meta_entry;

    typedef cache_meta_entry cache_meta_set [ASSOC_WIDTH];
    // typedef cache_meta_set cache_meta [INDEX_WIDTH];

    typedef enum logic [2:0] {
        CACHE_RESET, // Resetting cache metadata
        CACHE_NORMAL, // Normally responding to requests
        CACHE_LOAD, // Cache block being loaded
        CACHE_STORE, // Cache block being saved back to memory
        CACHE_FLUSH // Entire cache being flushed
    } cache_state;

    cache_state cs, ns;

    // // TODO: Replace with distributed RAM, requires dedicated reset state
    // cache_meta_entry meta_entries [INDEX_WIDTH] [ASSOC_WIDTH];

    // {TAG, INDEX, OFFSET}
    function [TAG_BITS-1:0] get_tag(input logic [ADDR_WIDTH-1:0] addr);
        return addr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_BITS];
    endfunction

    function [INDEX_BITS-1:0] get_index(input logic [ADDR_WIDTH-1:0] addr);
        return addr[ADDR_WIDTH-TAG_BITS-1:BLOCK_BITS+DATA_ADDR_BITS];
    endfunction

    function [BLOCK_BITS-1:0] get_offset(input logic [ADDR_WIDTH-1:0] addr);
        return addr[BLOCK_BITS+DATA_ADDR_BITS-1:DATA_ADDR_BITS];
    endfunction

    function automatic cache_meta_set find_set(
        input cache_meta_entry meta_entries [INDEX_WIDTH] [ASSOC_WIDTH],
        input [ADDR_WIDTH-1:0] addr
    );
        return meta_entries[get_index(addr)];
    endfunction

    // function automatic logic valid_block_exists(
    //     input cache_meta_set meta_set,
    //     input [ADDR_WIDTH-1:0] addr
    // );
    //     // Search for valid entries with the same tag
    //     cache_meta_entry entry;
    //     for (int i = 0; i < ASSOC_WIDTH; i++) begin
    //         if (meta_set[i].valid && meta_set[i].tag == get_tag(addr)) begin
    //             return 'b1;
    //         end
    //     end
    //     return 'b0;
    // endfunction

    function automatic cache_meta_result find_valid_block(
        input cache_meta_set meta_set,
        input [ADDR_WIDTH-1:0] addr
    );
        // Search for valid entries with the same tag
        for (int i = 0; i < ASSOC_WIDTH; i++) begin
            if (meta_set[i].valid && meta_set[i].tag == get_tag(addr)) begin
                return '{exists: 'b1, index: i};
            end
        end
        return '{exists: 'b0, index: 'b0};
    endfunction

    function automatic logic [LOCAL_ADDR_WIDTH-1:0] find_local_cache_address(
        input cache_meta_assoc_index assoc_index,
        input cache_meta_set meta_set,
        input [ADDR_WIDTH-1:0] addr
    );
        // Cover the case of a directly associative cache
        if (ASSOC_BITS == 0) begin
            return {get_index(addr), get_offset(addr)};
        end else begin
            return {get_index(addr), assoc_index, get_offset(addr)};
        end
    endfunction

    function automatic cache_meta_result find_available_block(
        input cache_meta_set meta_set
    );
        // Search for invalid entries
        for (int i = 0; i < ASSOC_WIDTH; i++) begin
            if (!meta_set[i].valid || !meta_set[i].dirty) begin
                return '{exists: 'b1, index: i};
            end
        end
        return '{exists: 'b0, index: 'b0};
    endfunction

    function automatic cache_meta_result find_lru_block(
        input cache_meta_set meta_set
    );
        // Search for lru entry
        cache_meta_result result = '{exists: 'b1, index: 'b0};
        cache_meta_lru lru = MAX_LRU;
        for (int i = 0; i < ASSOC_WIDTH; i++) begin
            if (meta_set[i].lru <= lru) begin
                result.index = i;
                lru = meta_set[i].lru;
            end
        end
        return result;
    endfunction

    function automatic cache_meta_set update_lru_blocks(
        input cache_meta_set meta_set,
        input cache_meta_assoc_index updated_index
    );
        // Decrement all LRU entries greater than the updated entry 
        for (int i = 0; i < ASSOC_WIDTH; i++) begin
            if (meta_set[i].lru > meta_set[updated_index].lru) begin
                meta_set[i].lru--;
            end
        end

        // Set updated block to max lru value
        meta_set[updated_index].lru = MAX_LRU;

        return meta_set;
    endfunction

    function automatic cache_meta_set clear_lru_blocks();
        cache_meta_set cleared_set;

        for (int i = 0; i < ASSOC_WIDTH; i++) begin
            cleared_set[i].valid = 'b0;
            cleared_set[i].dirty = 'b0;
            cleared_set[i].lru = i[SAFE_ASSOC_BITS-1:0];
        end

        return cleared_set;
    endfunction

    logic normal_mem_enable, cache_mem_enable;
    logic normal_mem_write_enable, cache_mem_write_enable;
    logic [LOCAL_ADDR_WIDTH-1:0] normal_mem_addr, cache_mem_addr;
    rv_memory_double_port #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(LOCAL_ADDR_WIDTH)
    ) cache_data_inst (
        .clk, .rst,

        // Memory values do not get reset on the device after startup,
        // so avoid writing to them during normal reset
        .enable0(!rst && normal_mem_enable),
        .write_enable0(normal_mem_write_enable),
        .addr_in0(normal_mem_addr),
        .data_in0(command.data),
        .data_out0(result.data),

        .enable1(!rst && cache_mem_enable),
        .write_enable1(cache_mem_write_enable),
        .addr_in1(cache_mem_addr),
        .data_in1(cache_result.data),
        .data_out1(cache_command.data)
    );

    logic meta_write_enable;
    logic [INDEX_BITS-1:0] meta_address;
    cache_meta_set meta_data_in, meta_data_out;

    // TODO: Breakup the write enables on the distributed-RAM
    rv_memory_distributed #(
        .DATA_WIDTH($size(cache_meta_set)),
        .ADDR_WIDTH(INDEX_BITS),
        .READ_PORTS(0)
    ) cache_meta_inst (
        .clk, .rst,

        .write_enable(meta_write_enable),
        .write_addr(meta_address),

        .write_data_in(meta_data_in),
        .write_data_out(cache_meta_set'(meta_data_out))
    );

    logic index_enable;
    logic [INDEX_BITS-1:0] index_current, index_next;
    rv_register #(.WIDTH(INDEX_BITS)) index_register_inst (
        .clk, .rst, .enable(index_enable),
        .next_value(index_next), .value(index_current)
    );

    logic assoc_enable;
    logic [SAFE_ASSOC_BITS-1:0] assoc_current, assoc_next;
    rv_register #(.WIDTH(SAFE_ASSOC_BITS)) assoc_register_inst (
        .clk, .rst, .enable(assoc_enable),
        .next_value(assoc_next), .value(assoc_current)
    );

    // Extra bit for being done recieving blocks
    logic block_in_enable;
    logic [BLOCK_BITS:0] block_in_current, block_in_next;
    rv_register #(.WIDTH(BLOCK_BITS + 1)) block_in_register_inst (
        .clk, .rst, .enable(block_in_enable),
        .next_value(block_in_next), .value(block_in_current)
    );

    // Extra bit for being done sending blocks
    logic block_out_enable;
    logic [BLOCK_BITS:0] block_out_current, block_out_next;
    rv_register #(.WIDTH(BLOCK_BITS + 1)) block_out_register_inst (
        .clk, .rst, .enable(block_out_enable),
        .next_value(block_out_next), .value(block_out_current)
    );

    logic tag_enable;
    logic [TAG_BITS-1:0] tag_current, tag_next;
    rv_register #(.WIDTH(TAG_BITS)) tag_register_inst (
        .clk, .rst, .enable(tag_enable),
        .next_value(tag_next), .value(tag_current)
    );

    always_ff @ (posedge clk) begin
        if (rst) begin
            cs <= CACHE_RESET;
        end else if (enable) begin
            cs <= ns;
        end
    end

    always_comb begin

        // Used for tracking loads and stores
        automatic logic block_in_done, block_out_done;
        // Used for looking through metadata
        automatic cache_meta_result valid_result;
        automatic logic [LOCAL_ADDR_WIDTH-1:0] local_addr;
        // Used for looking through a single cache set
        automatic cache_meta_result empty_result, lru_result;

        // Find cache location based on address
        meta_address = get_index(command.addr);

        valid_result = find_valid_block(meta_data_out, command.addr);
        local_addr = find_local_cache_address(valid_result.index, 
                meta_data_out, command.addr);
        normal_mem_addr = local_addr;

        empty_result = find_available_block(meta_data_out);
        lru_result = find_lru_block(meta_data_out);

        // Track loads and stores for the entire block
        if (cs == CACHE_LOAD || cs == CACHE_STORE || cs == CACHE_FLUSH) begin
            cache_command.valid = (block_out_current != OVERFLOW_BLOCK); 
            cache_result.ready = (block_in_current != OVERFLOW_BLOCK);

            block_out_done = (block_out_current == OVERFLOW_BLOCK) || 
                    ((block_out_current == MAX_BLOCK) && cache_command.ready);

            block_in_done = (block_in_current == OVERFLOW_BLOCK) || 
                    ((block_in_current == MAX_BLOCK) && cache_result.valid);

            if (block_out_done && block_in_done) begin
                block_in_enable = 'b1;
                block_out_enable = 'b1;

                block_in_next = 'b0;
                block_out_next = 'b0;
            end else begin
                block_in_enable = cache_result.valid && 
                        block_in_current != OVERFLOW_BLOCK;
                block_out_enable = cache_command.ready && 
                        block_out_current != OVERFLOW_BLOCK;

                block_in_next = block_in_current + 'b1;
                block_out_next = block_out_current + 'b1;
            end
        end else begin
            cache_command.valid = 'b0;
            cache_command.ready = 'b0;
            block_in_enable = 'b0;
            block_out_enable = 'b0;
            block_in_done = 'b0;
            block_out_done = 'b0;
            block_in_next = 'b0;
            block_out_next = 'b0;
        end

        // Handle state transitions
        case(cs)
        // Need to individually reset the contents of the distributed-RAM
        CACHE_RESET: begin
            index_enable = 'b1;
            index_next = index_current + 'b1;

            meta_write_enable = 'b1;
            meta_data_in = clear_lru_blocks();

            if (index_next == 'b0) begin
                ns = CACHE_NORMAL;
            end else begin
                ns = CACHE_RESET;
            end
        end
        // Normally respond to requests if its in the cache
        CACHE_NORMAL: begin
            
            command_block = valid_result.exists;

            if (flush_command.valid) begin
                block_in_enable = 'b1;
                block_in_next = 'b0;

                block_out_enable = 'b1;
                block_out_next = 'b0;

                index_enable = 'b1;
                index_next = 'b0;

                assoc_next = empty_result.index;
                    tag_next = get_tag(command.addr);

                ns = CACHE_FLUSH;
            end else if (valid_result.exists) begin
                ns = CACHE_NORMAL;
            end else begin
                block_in_enable = 'b1;
                block_in_next = 'b0;

                block_out_enable = 'b1;
                block_out_next = 'b0;

                index_enable = 'b1;
                index_next = get_index(command.addr);

                {assoc_enable, tag_enable} = 2'b11;
                if (empty_result.exists) begin
                    // Start loading into available block
                    assoc_next = empty_result.index;
                    tag_next = get_tag(command.addr);

                    ns = CACHE_LOAD;
                end else begin
                    // Start storing dirty LRU block
                    assoc_next = lru_result.index;
                    tag_next = found_set[lru_result.index].tag;

                    ns = CACHE_STORE;
                end
            end
        end
        // Load data into the cache from memory
        CACHE_LOAD: begin
            if (block_out_done && block_in_done) begin
                ns = CACHE_NORMAL;
            end else begin
                ns = CACHE_LOAD;
            end
        end
        // Store data from the cache into memory
        CACHE_STORE: begin
            if (block_out_done && block_in_done) begin
                // Start loading into available block
                assoc_enable = 'b1;
                assoc_next = empty_result.index;

                tag_enable = 'b1;
                tag_next = get_tag(command.addr);

                ns = CACHE_LOAD;
            end else begin
                ns = CACHE_STORE;
            end

        end
        CACHE_FLUSH: begin

        end
        endcase

        // Tie outbound command address to counters and tag register
        cache_command.addr = {tag_current, index_current,
            block_out_current, {DATA_ADDR_BITS{1'b0}}};

        if (ns == CACHE_STORE) begin
            // Tie memory address to match outgoing cache commands
            cache_mem_addr = {tag_next, index_next, 
                block_in_next, {DATA_ADDR_BITS{1'b0}}};
        end else begin
            // Tie memory address to match inbound cache results
            cache_mem_addr = {tag_current, index_current, 
                block_in_current, {DATA_ADDR_BITS{1'b0}}};
        end
        
    end

endmodule

// /*
//  * Functional representation for simulation purposes
//  */
// module rv_cache_single_ref #(
//     parameter ASSOC_BITS = 0, // Direct Associative
//     parameter BLOCK_BITS = 6, // 64 byte cache block/row
//     parameter INDEX_BITS = 6 // Uses 4 kB block RAM
// )(
//     input logic clk, rst,
//     rv_mem_intf.in command, // Inbound Commands
//     rv_mem_intf.out result, // Outbound Results
    
//     rv_mem_intf.out cache_command, // Outbound Cache Commands
//     rv_mem_intf.in cache_result // Inbound Cache Results
// );



// endmodule
