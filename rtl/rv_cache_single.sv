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
    rv_mem_intf.in cache_result // Inbound Cache Results
);

    import rv_mem::*;

    `STATIC_ASSERT(command.ADDR_BYTE_SHIFTED)
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

    // How wide is backing memory address
    localparam LOCAL_ADDR_WIDTH = INDEX_BITS + ASSOC_BITS + BLOCK_BITS;
    // How wide is the cache tag
    localparam TAG_BITS = (ADDR_WIDTH - DATA_ADDR_BITS) - BLOCK_BITS - INDEX_BITS;
    `STATIC_ASSERT(TAG_BITS >= 0)

    // // How deep is the backing memory
    // localparam LOCAL_DATA_LENGTH = 2**LOCAL_ADDR_WIDTH;

    localparam SAFE_ASSOC_BITS = MAX(1, ASSOC_BITS);

    logic enable, command_block, result_block, 
            cache_command_block, cache_result_block;
    rv_seq_flow_controller #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(2)
    ) flow_controller_inst (
        .clk, .rst, .enable(enable),
        .inputs_valid({command.valid, cache_result.valid}), 
        .inputs_ready({command.ready, cache_result.ready}),
        .inputs_block({command_block, cache_result_block}),

        .outputs_valid({result.valid, cache_command.valid}),
        .outputs_ready({result.ready, cache_command.ready}),
        .outputs_block({result_block, cache_command_block})
    );


    typedef logic [SAFE_ASSOC_BITS-1:0] cache_meta_lru;
    parameter cache_meta_lru MAX_LRU = {SAFE_ASSOC_BITS{1'b1}};

    typedef struct packed {
        logic valid, dirty;
        logic [TAG_BITS-1:0] tag;
        // The smallest lru is the least recently used
        cache_meta_lru lru; // Uses 1 bit if direct associative
    } cache_meta_entry;

    typedef cache_meta_entry cache_meta_set [ASSOC_WIDTH];
    typedef cache_meta_set cache_meta [INDEX_WIDTH];

    typedef enum logic [1:0] {
        CACHE_NORMAL, // Data is in cache
        CACHE_LOAD, // Cache block being loaded
        CACHE_STORE, // Cache block being saved back to memory
        CACHE_FLUSH // Entire cache being flushed
    } cache_state;

    cache_state cs, ns;

    logic bit_enable, bit_clear, bit_counter_done;
    logic [3:0] current_bit;
    rv_counter #(.WIDTH(BLOCK_BITS)) block_counter_inst (
        .clk, .rst,
        .enable(bit_enable), .clear(bit_clear),
        .value(current_bit),
        .max(4'd8), .complete(bit_counter_done)
    );

    // Rough size for a 4kB 2-way cache is 2 (assoc) * 32 (index) or 64 entries
    cache_meta_entry meta_entries [INDEX_WIDTH] [ASSOC_WIDTH];

    task reset_meta_entries();
        for (int i = 0; i < ASSOC_WIDTH; i++) begin
            for (int j = 0; j < INDEX_WIDTH; j++) begin
                meta_entries[i][j].valid <= 'b0;
                meta_entries[i][j].dirty <= 'b0;
            end
        end
    endtask

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

    function automatic logic exists_valid_block(
        input cache_meta_set meta_set,
        input [ADDR_WIDTH-1:0] addr
    );
        // Search for valid entries with the same tag
        cache_meta_entry entry;
        for (int i = 0; i < ASSOC_WIDTH; i++) begin
            if (meta_set[i].valid && meta_set[i].tag == get_tag(addr)) begin
                return 'b1;
            end
        end
        return 'b0;
    endfunction

    function automatic cache_meta_lru find_valid_block(
        input cache_meta_set meta_set,
        input [ADDR_WIDTH-1:0] addr
    );
        // Search for valid entries with the same tag
        cache_meta_lru index = 'b0;
        for (int i = 0; i < ASSOC_WIDTH; i++) begin
            if (meta_set[i].valid && meta_set[i].tag == get_tag(addr)) begin
                return index;
            end
        end
        return index;
    endfunction

    function automatic cache_meta_lru find_empty_block(
        input cache_meta_set meta_set
    );
        // Search for invalid entries
        for (int i = 0; i < ASSOC_WIDTH; i++) begin
            if (!meta_set[i].valid) begin
                return i;
            end
        end
    endfunction

    function automatic cache_meta_lru find_lru_block(
        input cache_meta_set meta_set
    );
        // Search for lru entry
        cache_meta_lru index = 0;
        cache_meta_lru lru = MAX_LRU;
        for (int i = 0; i < ASSOC_WIDTH; i++) begin
            if (meta_set[i].lru <= lru) begin
                index = i;
                lru = meta_set[i].lru;
            end
        end
        return index;
    endfunction

    function automatic cache_meta_set update_lru_blocks(
        input cache_meta_set meta_set,
        input cache_meta_lru updated_index
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

    logic normal_mem_enable, cache_mem_enable;
    logic normal_mem_write_enable, cache_mem_write_enable;
    rv_memory_double_port #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(LOCAL_ADDR_WIDTH)
    ) rv_memory_double_port_inst (
        .clk, .rst,

        // Memory values do not get reset on the device after startup,
        // so avoid writing to them during normal reset
        .enable0(!rst && normal_mem_enable),
        .write_enable0(normal_mem_write_enable),
        .addr_in0(),
        .data_in0(),
        .data_out0(),

        .enable1(!rst && cache_mem_enable),
        .write_enable1(cache_mem_write_enable),
        .addr_in1(),
        .data_in1(),
        .data_out1()
    );



    always_ff @ (posedge clk) begin
        if (rst) begin
            cs <= CACHE_NORMAL;
            reset_meta_entries();
        end else if (enable) begin
            cs <= CACHE_LOAD;
        end
    end

    always_comb begin
    
    end

endmodule

/*
 * Functional representation for simulation purposes
 */
module rv_cache_single_ref #(
    parameter ASSOC_BITS = 0, // Direct Associative
    parameter BLOCK_BITS = 6, // 64 byte cache block/row
    parameter INDEX_BITS = 6 // Uses 4 kB block RAM
)(
    input logic clk, rst,
    rv_mem_intf.in command, // Inbound Commands
    rv_mem_intf.out result, // Outbound Results
    
    rv_mem_intf.out cache_command, // Outbound Cache Commands
    rv_mem_intf.in cache_result // Inbound Cache Results
);



endmodule