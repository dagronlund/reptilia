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
        MESI State, LRU, Tag
*/
module cache_decode
    import std_pkg::*;
    import stream_pkg::*;
    import cache_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,

    parameter int PORTS = 1,

    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int CHILD_DATA_WIDTH = 32,

    parameter int BLOCK_ADDR_WIDTH = 6,
    parameter int INDEX_ADDR_BITS = 6,
    parameter int ASSOCIATIVITY = 1,

    parameter logic IS_COHERENT = 'b0,
    parameter logic IS_LAST_LEVEL = 'b0,
    parameter logic IS_FIRST_LEVEL = 'b0,

    parameter int DATA_WIDTH_RATIO = DATA_WIDTH / CHILD_DATA_WIDTH,
    parameter int SUB_BLOCK_ADDR_WIDTH = BLOCK_ADDR_WIDTH - $clog2(DATA_WIDTH_RATIO)
)(
    input logic clk, rst,
    
    mem_intf.in                child_request,
    input cache_mesi_request_t child_request_info,

    mem_intf.in                 parent_response,
    input cache_mesi_response_t parent_response_info,
    
    mem_intf.out local_request,
    stream_intf.out local_request_meta, // local_meta_t
    stream_intf.out bypass_request // bypass_t
);

    localparam logic HAS_COHERENT_PARENT = (IS_COHERENT && !IS_LAST_LEVEL);
    localparam logic HAS_COHERENT_CHILD = (IS_COHERENT && !IS_FIRST_LEVEL);
    `STATIC_ASSERT(IS_COHERENT -> (!IS_FIRST_LEVEL || !IS_LAST_LEVEL))

    localparam int WORD_BITS = $clog2(DATA_WIDTH/8);
    localparam int CHILD_WORD_BITS = $clog2(CHILD_DATA_WIDTH/8);

    localparam int TAG_BITS = 32 - BLOCK_ADDR_WIDTH - INDEX_ADDR_BITS - WORD_BITS;
    localparam int LRU_BITS = ($clog2(ASSOCIATIVITY) > 1) ? $clog2(ASSOCIATIVITY) : 1;
    localparam int LOCAL_ADDR_WIDTH = BLOCK_ADDR_WIDTH + INDEX_ADDR_BITS + $clog2(ASSOCIATIVITY);

    localparam int ID_WIDTH = $bits(child_request.id);

    `STATIC_ASSERT(ADDR_WIDTH == $bits(child_request.addr))
    `STATIC_ASSERT(LOCAL_ADDR_WIDTH == $bits(local_request.addr))
    `STATIC_ASSERT(ADDR_WIDTH == $bits(parent_response.addr))

    `STATIC_ASSERT(DATA_WIDTH >= CHILD_DATA_WIDTH)
    `STATIC_ASSERT(DATA_WIDTH == $bits(local_request.data))
    `STATIC_ASSERT(CHILD_DATA_WIDTH == $bits(child_request.data))

    `STATIC_ASSERT($bits(child_request.id) == $bits(local_request.id))

    typedef logic [DATA_WIDTH-1:0] data_t;
    typedef logic [(DATA_WIDTH/8)-1:0] mask_t;
    typedef logic [CHILD_DATA_WIDTH-1:0] child_data_t;
    typedef logic [(CHILD_DATA_WIDTH/8)-1:0] child_mask_t;
    typedef logic [ADDR_WIDTH-1:0] addr_t;
    typedef logic [LOCAL_ADDR_WIDTH-1:0] local_addr_t;
    typedef logic [BLOCK_ADDR_WIDTH-1:0] block_t;
    typedef logic [SUB_BLOCK_ADDR_WIDTH-1:0] sub_block_t;
    typedef logic [TAG_BITS-1:0] tag_t;
    typedef logic [LRU_BITS-1:0] lru_t;
    typedef logic [INDEX_ADDR_BITS-1:0] index_t;
    typedef logic [$clog2(PORTS)-1:0] id_t;
    typedef logic [ID_WIDTH-1:0] full_id_t;

    typedef enum logic [1:0] {
        NORMAL,
        BLOCK_READ, BLOCK_READ_RESPONSE,
        BLOCK_WRITE,
        PARENT_SHARED_RESPONSE,
        PARENT_MODIFIED_RESPONSE,
        PARENT_UPGRADE_RESPONSE,
        CHILD_EVICTION_REQUESTS, CHILD_EVICTION_RESPONSES,
        CHILD_EVICTION_DATA_RESPONSE,
        CHILD_INITIATED_EVICTION_DATA,
        PARENT_EVICTION_DATA_RESPONSE,
        CHILD_SHARED_RESPONSE,
        CHILD_MODIFIED_RESPONSE
    } state_t;

    // Identical type in cache_encode
    typedef struct packed {
        logic bypass_id;
        logic send_parent;
        cache_mesi_operation_t op;
        addr_t addr;
    } local_meta_t;

    // Identical type in cache_encode
    typedef struct packed {
        logic bypass_id;
        logic send_parent;
        cache_mesi_operation_t op;
        addr_t addr;
        logic [ID_WIDTH-1:0] id;
        logic last;
    } bypass_t;

    typedef struct packed {
        tag_t tag;
        index_t index;
        block_t block; // Includes unused LSB of address
    } addr_decoded_t;

    typedef struct packed {
        cache_mesi_state_t mesi;
        logic [PORTS-1:0] owners;
        logic [PORTS-1:0] modifiers;
        tag_t tag;
        lru_t lru;
    } line_meta_t;

    typedef struct packed {
        logic valid;
        cache_mesi_operation_t op;
        addr_t addr;
    } parent_request_t;

    typedef struct packed {
        logic valid;
        cache_mesi_operation_t op;
        addr_t addr;
        child_data_t data;
        id_t child_id;
        logic read_enable;
        child_mask_t write_enable;
    } child_request_t;

    function automatic id_t find_next_bit(input logic [PORTS-1:0] ports, id_t start);
        for (id_t i = start; i < PORTS; i++) begin
            if (ports[i]) begin
                return i;
            end
        end
        return 'b0;
    endfunction

    typedef struct packed {
        logic found_hit, found_empty;
        lru_t line, empty, last_used;
    } line_search_t;

    function automatic line_search_t search_line(
        input line_meta_t [ASSOCIATIVITY-1:0] meta,
        input tag_t tag
    );
        line_search_t search = '{default: 'b0};

        // Search associated lines for hit, empty, and last used lines
        for (int i = 0; i < ASSOCIATIVITY; i++) begin
            if (cache_is_mesi_valid(meta[i].mesi) && 
                    meta[i].tag == tag) begin
                search.found_hit = 'b1;
                search.line = i;
            end
            if (!cache_is_mesi_valid(meta[i].mesi)) begin
                search.found_empty = 'b1;
                search.empty = i;
            end
            if (meta[i].lru > meta[search.last_used].lru) begin
                search.last_used = i;
            end
        end

        return search;
    endfunction

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
        input index_t index,
        input block_t block,
        input lru_t assoc
    );
        return (ASSOCIATIVITY > 1) ? {index, assoc, block} : {index, block};
    endfunction

    // Lower LRU means it was modified the latest
    function automatic line_meta_t [ASSOCIATIVITY-1:0] update_lru(
        input line_meta_t [ASSOCIATIVITY-1:0] meta_in,
        input lru_t accessed_index
    );
        lru_t old_lru = meta_in[accessed_index].lru;

        for (int i = 0; i < ASSOCIATIVITY; i++) begin
            if (old_lru >= meta_in[i].lru) begin
                meta_in[i].lru += 'b1;
            end
        end

        meta_in[accessed_index].lru = 'b0;

        return meta_in;
    endfunction

    function automatic id_t get_id(input full_id_t full_id);
        return full_id[$clog2(PORTS)-1:0];
    endfunction

    function automatic mask_t get_write_mask(
        input child_mask_t child_mask, 
        input addr_t child_addr
    );
        return (DATA_WIDTH_RATIO > 1) ? child_mask << (child_addr[$clog2(DATA_WIDTH_RATIO)+CHILD_WORD_BITS-1:CHILD_WORD_BITS] << $clog2(CHILD_DATA_WIDTH/8)) : child_mask;
    endfunction


    logic reset_done, enable;
    logic consume_child, consume_parent;
    logic produce_local_request, produce_local_request_meta, produce_bypass_request;

    stream_intf #(.T(bypass_t)) next_bypass_request (.clk, .rst);
    mem_intf #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(LOCAL_ADDR_WIDTH), 
                .ID_WIDTH($bits(child_request.id))) next_local_request (.clk, .rst);
    stream_intf #(.T(local_meta_t)) next_local_request_meta (.clk, .rst);

    stream_controller_gated #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(3)
    ) stream_controller_gated_inst (
        .clk, .rst,

        .enable_in(reset_done),

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

    logic metadata_write_enable;
    index_t metadata_addr;
    line_meta_t [ASSOCIATIVITY-1:0] metadata_write_data, metadata_read_data, metadata_dummy;

    state_t current_state, next_state;
    sub_block_t current_front_sub_block, next_front_sub_block;
    sub_block_t current_rear_sub_block, next_rear_sub_block;
    logic current_bypass_id, next_bypass_id;

    parent_request_t current_parent_request, next_parent_request;
    child_request_t current_child_request, next_child_request;

    lru_t current_residual_lru, next_residual_lru;
    addr_t current_residual_address, next_residual_address;

    id_t current_child_id, next_child_id;
    id_t current_child_id_skip, next_child_id_skip;
    logic current_child_id_skip_enable, next_child_id_skip_enable;
    logic [PORTS-1:0] current_child_map, next_child_map;
    logic current_response_return, next_response_return;
    logic current_data_response_return, next_data_response_return;

    logic [$bits(state_t)-1:0] current_state_temp;
    assign current_state = state_t'(current_state_temp);

    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(logic [1:0]), .RESET_VECTOR(CACHE_NORMAL)) state_register_inst (.clk, .rst, .enable, .next(next_state), .value(current_state_temp));
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(sub_block_t), .RESET_VECTOR('b0)) front_sub_block_register_inst (.clk, .rst, .enable, .next(next_front_sub_block), .value(current_front_sub_block));
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(sub_block_t), .RESET_VECTOR('b0)) rear_sub_block_register_inst (.clk, .rst, .enable, .next(next_rear_sub_block), .value(current_rear_sub_block));
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(logic), .RESET_VECTOR('b0)) id_register_inst (.clk, .rst, .enable, .next(next_bypass_id), .value(current_bypass_id));
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(parent_request_t), .RESET_VECTOR('{default: 'b0})) parent_request_register_inst (.clk, .rst, .enable, .next(next_parent_request), .value(current_parent_request));
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(child_request_t), .RESET_VECTOR('{default: 'b0})) child_request_register_inst (.clk, .rst, .enable, .next(next_child_request), .value(current_child_request));

    // Stores tag, associative index, and normal index between operations
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(lru_t), .RESET_VECTOR('b0)) residual_lru_register_inst (.clk, .rst, .enable, .next(next_residual_lru), .value(current_residual_lru));
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(addr_t), .RESET_VECTOR('b0)) residual_address_register_inst (.clk, .rst, .enable, .next(next_residual_address), .value(current_residual_address));

    // Child eviction only registers
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(logic [PORTS-1:0]), .RESET_VECTOR('b0)) child_map_register_inst (.clk, .rst, .enable, .next(next_child_map), .value(current_child_map));
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(id_t), .RESET_VECTOR('b0)) child_id_register_inst (.clk, .rst, .enable, .next(next_child_id), .value(current_child_id));
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(logic), .RESET_VECTOR('b0)) child_id_skip_enable_register_inst (.clk, .rst, .enable, .next(next_child_id_skip_enable), .value(current_child_id_skip_enable));
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(id_t), .RESET_VECTOR('b0)) child_id_skip_register_inst (.clk, .rst, .enable, .next(next_child_id_skip), .value(current_child_id_skip));
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(logic), .RESET_VECTOR('b0)) data_response_return_register_inst (.clk, .rst, .enable, .next(next_data_response_return), .value(current_data_response_return) );
    std_register #(.CLOCK_INFO(CLOCK_INFO), .T(logic), .RESET_VECTOR('b0)) response_return_register_inst (.clk, .rst, .enable, .next(next_response_return), .value(current_response_return));

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
        automatic line_search_t search_results;
        automatic id_t modified_child_id = 'b0, owner_child_id = 'b0;

        automatic logic initiate_parent_request = 'b0, initiate_child_request = 'b0;
        automatic logic initiate_complete_eviction = 'b0;
        automatic logic initiate_child_evictions = 'b0, initiate_child_eviction_data = 'b0;

        next_state = current_state;
        next_front_sub_block = current_front_sub_block;
        next_rear_sub_block = current_rear_sub_block;
        next_bypass_id = current_bypass_id;

        next_residual_lru = current_residual_lru;
        next_residual_address = current_residual_address;

        next_parent_request = current_parent_request;
        next_child_request = current_child_request;

        next_child_map = current_child_map;
        next_child_id = current_child_id;
        next_child_id_skip = current_child_id_skip;
        next_child_id_skip_enable = current_child_id_skip_enable;
        next_response_return = current_response_return;
        next_data_response_return = current_data_response_return;

        consume_child = 'b0;
        consume_parent = 'b0;
        produce_local_request = 'b0;
        produce_local_request_meta = 'b0;
        produce_bypass_request = 'b0;

        metadata_write_enable = 'b0;
        
        metadata_addr = decode_address(child_request.addr).index;
        metadata_write_data = metadata_read_data;
        search_results = search_line(metadata_read_data, decode_address(child_request.addr).tag);

        // Set defaults for local_request, where child_request is possibly less
        // wide than the local request and write enable needs to be shifted
        next_local_request.read_enable = child_request.read_enable;
        next_local_request.write_enable = get_write_mask(child_request.write_enable, child_request.addr);
        next_local_request.addr = get_local_address(decoded_addr.index, decoded_addr.block, found_line);
        next_local_request.data = {DATA_WIDTH_RATIO{child_request.data}};
        next_local_request.id = child_request.id;
        next_local_request_meta.payload = '{default: 'b0};
        next_bypass_request.payload = '{default: 'b0};

        case (current_state)        
        NORMAL: begin
            if (current_parent_request.valid) begin // Process pending parent request
                initiate_parent_request = 'b1;
            end else if (current_child_request.valid) begin // Process pending child request
                initiate_child_request = 'b1;
            end else if (parent_response.valid) begin // We have a parent request waiting
                consume_parent = 'b1;
                initiate_parent_request = 'b1;
                next_parent_request = '{
                    valid: 'b1,
                    op: parent_response_info.op,
                    addr: parent_response.addr
                };
            end else begin // Consume a child request
                consume_child = 'b1;
                initiate_child_request = 'b1;
                next_child_request = '{
                    valid: 'b1,
                    op: child_request_info.op,
                    addr: child_request.addr,
                    data: child_request.data,
                    id: get_id(child_request.id),
                    read_enable: child_request.read_enable,
                    write_enable: child_request.write_enable
                };
            end
        end
        BLOCK_WRITE: begin
            next_front_sub_block = current_front_sub_block + 'b1;

            produce_local_request = 'b1;
            produce_local_request_meta = 'b1;
            next_local_request.read_enable = 'b1;
            next_local_request.write_enable = 'b0;
            // Address is the index + association index + the sub-block address we are currently on
            next_local_request.addr = get_local_address(
                decode_address(current_residual_address).index, 
                current_front_sub_block, 
                current_residual_lru);
            next_local_request.last = (next_front_sub_block == 'b0);

            next_local_request_meta.payload = '{
                bypass_id: current_bypass_id,
                send_parent: 'b1,
                default: 'b0
            };
            next_local_request_meta.payload.addr = encode_sub_address(
                    decode_address(current_residual_address).tag, 
                    decode_address(current_residual_address).index, 
                    current_front_sub_block);

            if (next_front_sub_block == 'b0) begin
                next_state = NORMAL;
            end
        end
        BLOCK_READ: begin
            next_front_sub_block = current_front_sub_block + 'b1;

            // Issue bypass requests
            produce_bypass_request = 'b1;
            next_bypass_request.payload = '{
                bypass_id: current_bypass_id,
                send_parent: 'b1
                default: 'b0
            };
            next_bypass_request.payload.addr = encode_sub_address(
                    decode_address(current_residual_address).tag, 
                    decode_address(current_residual_address).index, 
                    current_front_sub_block);

            // Consume parent responses if available
            if (parent_response.valid) begin
                consume_parent = 'b1;
                produce_local_request = 'b1;
                next_rear_sub_block = current_rear_sub_block + 'b1;
            end
            next_local_request.read_enable = 'b0;
            next_local_request.write_enable = {(DATA_WIDTH/8){1'b1}};
            next_local_request.addr = get_local_address(
                decode_address(current_residual_address).index, 
                current_rear_sub_block, 
                current_residual_lru);
            next_local_request.data = parent_response.data;
            next_local_request.last = (next_front_sub_block == 'b0);

            if (next_front_sub_block == 'b0) begin
                next_state =  (next_rear_sub_block == 'b0) ? NORMAL : BLOCK_READ_RESPONSE;
            end
        end
        BLOCK_READ_RESPONSE: begin
            consume_parent = 'b1;
            produce_local_request = 'b1;
            next_rear_sub_block = current_rear_sub_block + 'b1;

            next_local_request.read_enable = 'b0;
            next_local_request.write_enable = {(DATA_WIDTH/8){1'b1}};
            next_local_request.addr = get_local_address(
                decode_address(current_residual_address).index, 
                current_rear_sub_block, 
                current_residual_lru);
            next_local_request.data = parent_response.data;

            if (next_rear_sub_block == 'b0) begin
                next_state = NORMAL;
            end
        end
        CHILD_SHARED_RESPONSE, CHILD_MODIFIED_RESPONSE: begin
            next_front_sub_block = current_front_sub_block + 'b1;

            // Issue a local request to store the data
            produce_local_request = 'b1;
            next_local_request.read_enable = 'b1;
            next_local_request.write_enable = 'b0;
            next_local_request.addr = get_local_address(decode_address(current_child_request.addr).index, 'b0, current_residual_lru);
            next_local_request.data = 'b0;
            next_local_request.id = current_child_request.child_id;
            next_local_request.last = (next_front_sub_block == 'b0);

            produce_local_request_meta = 'b1;
            next_local_request_meta.payload = '{bypass_id: current_bypass_id, send_parent: 'b0, default: 'b0};
            next_local_request_meta.payload.op = (current_state == CHILD_SHARED_RESPONSE) ? CACHE_MESI_OPERATION_SHARED : CACHE_MESI_OPERATION_MODIFIED;

            if (next_front_sub_block == 'b0) begin
                next_state = NORMAL;
            end
        end
        // We are either going to get the response we are looking for or a forced eviction
        PARENT_SHARED_RESPONSE, PARENT_MODIFIED_RESPONSE, PARENT_UPGRADE_RESPONSE: begin
            consume_parent = 'b1;

            case (parent_response_info.op)
            CACHE_MESI_OPERATION_REJECT: begin
                next_state = NORMAL;
                // We got a rejection so we respond and get rid of the child request if we are not first level
                if (!IS_FIRST_LEVEL) begin
                    next_child_request.valid = 'b0;
                    produce_bypass_request = 'b1;
                    next_bypass_request.payload = '{
                        bypass_id: current_bypass_id,
                        send_parent: 'b0,
                        op: CACHE_MESI_OPERATION_REJECT,
                        id: current_child_request.child_id,
                        addr: current_residual_address
                    };
                end
            end
            // We got a sucessful response
            CACHE_MESI_OPERATION_SHARED: begin
                `INLINE_ASSERT(current_state == PARENT_SHARED_RESPONSE)
                // Update metadata table to reflect the response
                metadata_write_enable = (current_front_sub_block == 'b0);
                metadata_write_data[current_residual_lru] = '{
                    mesi: CACHE_MESI_OPERATION_SHARED,
                    tag: decode_address(current_residual_address).tag,
                    default: 'b0
                };
                metadata_write_data = update_lru(metadata_write_data, current_residual_lru);

                // Issue memory write with data
                produce_local_request = 'b1;
                next_local_request.read_enable = 'b0;
                next_local_request.write_enable = parent_response.write_enable;
                next_local_request.addr = get_local_address(
                        decode_address(current_residual_address).index, 
                        current_front_sub_block, 
                        current_residual_lru);
                next_local_request.data = parent_response.data;

                // Update state
                next_front_sub_block = current_front_sub_block + 'b1;
                if (next_front_sub_block == 'b0) begin
                    next_state = NORMAL;
                end
            end
            CACHE_MESI_OPERATION_MODIFIED: begin
                `INLINE_ASSERT(current_state == PARENT_MODIFIED_RESPONSE)

                // Update metadata table to reflect the response
                metadata_write_enable = (current_front_sub_block == 'b0);
                metadata_write_data[current_residual_lru] = '{
                    mesi: CACHE_MESI_OPERATION_MODIFIED,
                    tag: decode_address(current_residual_address).tag,
                    default: 'b0
                };
                metadata_write_data = update_lru(metadata_write_data, current_residual_lru);

                // Issue memory write with data
                produce_local_request = 'b1;
                next_local_request.read_enable = 'b0;
                next_local_request.write_enable = parent_response.write_enable;
                next_local_request.addr = get_local_address(
                        decode_address(current_residual_address).index, 
                        current_front_sub_block, 
                        current_residual_lru);
                next_local_request.data = parent_response.data;
                // Update state
                next_front_sub_block = current_front_sub_block + 'b1;
                if (next_front_sub_block == 'b0) begin
                    next_state = NORMAL;
                end
            end
            CACHE_MESI_OPERATION_UPGRADE: begin
                `INLINE_ASSERT(current_state == PARENT_UPGRADE_RESPONSE)
                next_state = NORMAL;
                // Update metadata table to reflect the response
                metadata_write_enable = 'b1;
                metadata_write_data[current_residual_lru] = '{
                    mesi: CACHE_MESI_OPERATION_MODIFIED,
                    tag: decode_address(current_residual_address).tag,
                    default: 'b0
                };
                metadata_write_data = update_lru(metadata_write_data, current_residual_lru);                
            end
            // We have a parent request, store it temporarily
            CACHE_MESI_OPERATION_FORCE_EVICT, CACHE_MESI_OPERATION_FORCE_EVICT_DATA: begin
                next_parent_request.valid = 'b1;
                next_parent_request.op = parent_response_info;
                next_parent_request.addr = parent_response.addr;
            end
            endcase
        end

        // Issue child eviction requests (we will process responses later)
        CHILD_EVICTION_REQUESTS: begin
            // Issue eviction request to the correct child in current_child_id through bypass
            produce_bypass_request = 'b1;
            next_bypass_request.payload = '{
                bypass_id: current_bypass_id,
                send_parent: 'b0,
                op: CACHE_MESI_OPERATION_FORCE_EVICT,
                id: current_child_id,
                addr: current_residual_address
            };

            // Find what the next child would be
            next_child_id = find_next_bit(current_child_map, current_child_id + 'b1);

            // Possibly we already are at the last child or there are no more children past the current one
            next_state = ((current_child_id == PORTS-1) || (next_child_id == 'b0)) ? 
                    CHILD_EVICTION_RESPONSES : CHILD_EVICTION_REQUESTS;
        end
        // Process child eviction responses with or without data
        CHILD_EVICTION_RESPONSES, CHILD_EVICTION_DATA_RESPONSE: begin
            consume_child = 'b1;

            case (child_request_info.op)
            CACHE_MESI_OPERATION_READ, CACHE_MESI_OPERATION_WRITE, CACHE_MESI_OPERATION_UPGRADE: begin
                // Just send rejections to any requests to clear out the input stream
                produce_bypass_request = 'b1;
                next_bypass_request.payload = '{
                    bypass_id: current_bypass_id,
                    send_parent: 'b0,
                    op: CACHE_MESI_OPERATION_REJECT,
                    addr: child_request.addr, // Tbh this address really does not matter
                    id: child_request.id
                };
            end
            // Service a transient eviction while we are waiting for force eviction responses
            CACHE_MESI_OPERATION_NORMAL_EVICT: begin
                // We already did a metadata lookup based on the child request address
                `INLINE_ASSERT(search_results.found_hit)

                // All we do on a transient eviction is just indicate the cache below does not have the data
                metadata_write_enable = 'b1;
                metadata_write_data[search_results.line].owners[get_id(child_request.id)] = 'b0;

                // Check if the normal eviction pre-empted our forced eviction
                if (search_results.line == current_residual_lru && 
                        decode_address(child_request.addr).index == decode_address(current_residual_address).index) begin
                    `INLINE_ASSERT(current_state == CHILD_EVICTION_RESPONSES)

                    next_child_map[get_id(child_request.id)] = 'b0;
                    next_state = (next_child_map == 'b0) ? NORMAL : CHILD_EVICTION_RESPONSES;
                end
            end
            // Service an eviction with data
            CACHE_MESI_OPERATION_NORMAL_EVICT_DATA: begin
                // We already did a metadata lookup based on the child request address
                `INLINE_ASSERT(search_results.found_hit)

                // Indicate that no children own or have modified versions of this data
                metadata_write_enable = 'b1;
                metadata_write_data[search_results.line].owners = 'b0;
                metadata_write_data[search_results.line].modifiers = 'b0;

                // Move to another state to handle the data
                next_state = CHILD_INITIATED_EVICTION_DATA;
                next_response_return = (current_state == CHILD_EVICTION_RESPONSES);
                next_data_response_return = (current_state == CHILD_EVICTION_DATA_RESPONSE);
                next_front_sub_block = 'b1;

                // Check if the normal data eviction pre-empted our forced data eviction (just go back to normal if so)
                if (search_results.line == current_residual_lru &&
                        decode_address(child_request.addr).index == decode_address(current_residual_address).index) begin
                    next_data_response_return = 'b0;
                end

                // Issue a local request to store the data
                produce_local_request = 'b1;
                next_local_request.read_enable = 'b0;
                next_local_request.write_enable = get_write_mask(child_request.write_enable, child_request.addr);
                next_local_request.addr = get_local_address(
                        decode_address(child_request.addr).index, 
                        current_front_sub_block, 
                        search_results.line);
                next_local_request.data = child_request.data;
            end
            // Mark down a non-data eviction response
            CACHE_MESI_OPERATION_FORCE_EVICT: begin
                `INLINE_ASSERT(current_state == CHILD_EVICTION_RESPONSES)
                next_child_map[get_id(child_request.id)] = 'b0;
                next_state = (next_child_map == 'b0) ? NORMAL : CHILD_EVICTION_RESPONSES;
            end
            // Consume data from a data eviction response
            CACHE_MESI_OPERATION_FORCE_EVICT_DATA: begin
                `INLINE_ASSERT(current_state == CHILD_EVICTION_DATA_RESPONSE)

                // Create local request to store eviction data
                next_local_request.read_enable = 'b0;
                next_local_request.write_enable = get_write_mask(child_request.write_enable, child_request.addr);
                next_local_request.addr = get_local_address(next_residual_index, current_front_sub_block, next_residual_lru);
                next_local_request.data = child_request.data;

                next_front_sub_block = current_front_sub_block + 'b1;
                next_state = (next_front_sub_block == 'b0) ? NORMAL : CHILD_EVICTION_DATA_RESPONSE;
            end
            endcase
        end
        CHILD_INITIATED_EVICTION_DATA: begin
            consume_child = 'b1;
            produce_local_request = 'b1;

            // We are producing a local request to write so we need no id and can use the address coming from the eviction request each cycle
            next_local_request.read_enable = 'b0;
            next_local_request.write_enable = get_write_mask(child_request.write_enable, child_request.addr);
            next_local_request.addr = get_local_address(decode_address(child_request.addr).index, current_front_sub_block, search_results.line);
            next_local_request.data = child_request.data;

            next_front_sub_block = current_front_sub_block + 'b1;
            if (next_front_sub_block == 'b0) begin
                if (current_response_return) begin
                    next_state = CHILD_EVICTION_RESPONSES;
                end else if (current_data_response_return) begin
                    next_state = CHILD_EVICTION_DATA_RESPONSE;
                end else begin
                    next_state = NORMAL;
                end
            end
        end
        // Respond with the data requested by a parent initiated eviction
        PARENT_EVICTION_DATA_RESPONSE: begin
            next_front_sub_block = current_front_sub_block + 'b1;
            produce_local_request = 'b1;
            produce_local_request_meta = 'b1;

            // The data and id do not matter on reading to a parent
            next_local_request.read_enable = 'b1;
            next_local_request.write_enable = 'b0;
            next_local_request.addr = get_local_address(
                    decode_address(current_residual_address).index, 
                    current_front_sub_block, 
                    current_residual_lru);
            next_local_request.last = (next_front_sub_block == 'b0);

            next_local_request_meta.payload = '{
                bypass_id: current_bypass_id,
                send_parent: 'b1,
                op: CACHE_MESI_OPERATION_FORCE_EVICT_DATA,
                addr: 'b0, // Data response, no address
            };
            
            if (next_front_sub_block == 'b0) begin
                next_state = NORMAL;
            end
        end
        default: begin
            `INLINE_ASSERT(0)
        end
        endcase

        // TODO: Reorganize the stuff below

        // Process an existing or new child request
        if (HAS_COHERENT_CHILD && initiate_child_request) begin
            next_residual_lru = search_results.line;
            next_residual_address = next_child_request.addr;

            case (child_request_info.op)
            CACHE_MESI_OPERATION_SHARED: begin
                // The request can be satisifed with local data
                if (search_results.found_hit) begin 
                    // Some child has a modified version of the data
                    if (metadata_read_data[search_results.line].modifiers) begin
                        // Issue eviction request to child with modified data
                        initiate_child_eviction_data = 'b1;                        
                    end else begin
                        // Complete the request, we have the data
                        next_child_request.valid = 'b0;
                        next_state = CHILD_SHARED_RESPONSE;
                        next_front_sub_block = 'b1;
                        // Issue a local request to send the data to the child
                        produce_local_request = 'b1;
                        next_local_request.read_enable = 'b1;
                        next_local_request.write_enable = 'b0;
                        next_local_request.addr = get_local_address(decode_address(next_child_request.addr).index, 'b0, search_results.line);
                        next_local_request.data = 'b0;
                        next_local_request.id = next_child_request.child_id;
                        next_local_request.last = 'b0;
                        produce_local_request_meta = 'b1;
                        next_local_request_meta.payload = '{
                            bypass_id: current_bypass_id,
                            send_parent: 'b0,
                            op: CACHE_MESI_OPERATION_SHARED,
                            addr: 'b0
                        };
                        // Update metadata to recognize child access
                        metadata_write_enable = 'b1;
                        metadata_write_data[search_results.line].owners[next_child_request.child_id] = 'b1;
                        metadata_write_data = update_lru(metadata_write_data, next_child_request.child_id);
                    end
                end else begin // We need to get the data from our parent
                    if (search_results.found_empty) begin
                        if (HAS_COHERENT_PARENT) begin
                            // Issue request for data in shared state
                            produce_bypass_request = 'b1;
                            next_bypass_request.payload = '{bypass_id: current_bypass_id, send_parent: 'b1, op: CACHE_MESI_OPERATION_SHARED, addr: next_residual_address, default: 'b0};
                            next_state = PARENT_SHARED_RESPONSE;
                            next_front_sub_block = 'b0;
                        end else begin
                            // Start issuing block read
                            produce_bypass_request = 'b1;
                            next_bypass_request.payload = '{
                                bypass_id: current_bypass_id,
                                send_parent: 'b1
                                default: 'b0
                            };
                            next_bypass_request.payload.addr = encode_sub_address(
                                    decode_address(next_residual_address).tag, 
                                    decode_address(next_residual_address).index, 
                                    'b0);
                            next_state = BLOCK_READ;
                            next_front_sub_block = 'b1;
                            next_rear_sub_block = 'b0;
                            // Update metadata to recognize we have the data
                            metadata_write_enable = 'b1;
                            metadata_write_data[search_results.empty] = '{
                                mesi: CACHE_MESI_OPERATION_SHARED,
                                tag: decode_address(next_residual_address).tag,
                                default: 'b0
                            };
                            metadata_write_data = update_lru(metadata_write_data, search_results.empty);
                        end
                        next_residual_lru = search_results.empty;
                    end else begin
                        // Issue a set of eviction operations for last used line
                        initiate_complete_eviction = 'b1;
                        next_residual_lru = search_results.last_used;
                    end
                end
            end
            CACHE_MESI_OPERATION_MODIFIED: begin
                if (search_results.found_hit) begin
                    if (metadata_read_data[search_results.line].modifiers) begin
                        // Issue a force data eviction to single child
                        initiate_child_eviction_data = 'b1;
                    end else if (metadata_read_data[search_results.line].owners) begin
                        // Issue a force eviction to multiple children
                        initiate_child_evictions = 'b1;
                        next_child_id_skip_enable = 'b0;
                    // We only need to ask the parent for coherent modified access if it is coherent too
                    end else if (HAS_COHERENT_PARENT && !cache_is_mesi_dirty(metadata_read_data[search_results.line].mesi)) begin 
                        // Issue request for the data to be upgraded
                        produce_bypass_request = 'b1;
                        next_bypass_request.payload = '{bypass_id: current_bypass_id, send_parent: 'b1, op: CACHE_MESI_OPERATION_UPGRADE, addr: next_residual_address, default: 'b0};
                        next_state = PARENT_UPGRADE_RESPONSE;
                        next_front_sub_block = 'b0;
                    end else begin
                        // Complete the request, we have the data
                        next_child_request.valid = 'b0;
                        next_state = CHILD_MODIFIED_RESPONSE;
                        next_front_sub_block = 'b1;
                        // Issue a local request to send the data to the child
                        produce_local_request = 'b1;
                        next_local_request.read_enable = 'b1;
                        next_local_request.write_enable = 'b0;
                        next_local_request.addr = get_local_address(decode_address(next_child_request.addr).index, 'b0, search_results.line);
                        next_local_request.data = 'b0;
                        next_local_request.id = next_child_request.child_id;
                        next_local_request.last = 'b0;
                        produce_local_request_meta = 'b1;
                        next_local_request_meta.payload = '{
                            bypass_id: current_bypass_id,
                            send_parent: 'b0,
                            op: CACHE_MESI_OPERATION_MODIFIED,
                            addr: 'b0
                        };
                        // Update metadata to recognize child access
                        metadata_write_enable = 'b1;
                        // If our parent is not coherent just mark it as modified immediately
                        if (!HAS_COHERENT_PARENT) begin
                            metadata_write_data[search_results.line].mesi = CACHE_MESI_MODIFIED;
                        end
                        metadata_write_data[search_results.line].owners[next_child_request.child_id] = 'b1;
                        metadata_write_data[search_results.line].modifiers[next_child_request.child_id] = 'b1;
                        metadata_write_data = update_lru(metadata_write_data, next_child_request.child_id);
                    end
                end else begin // We need to get the data from our parent
                    if (search_results.found_empty) begin
                        if (HAS_COHERENT_PARENT) begin
                            // Issue request for the data in modified state
                            produce_bypass_request = 'b1;
                            next_bypass_request.payload = '{bypass_id: current_bypass_id, send_parent: 'b1, op: CACHE_MESI_OPERATION_MODIFIED, addr: next_residual_address, default: 'b0};
                            next_state = PARENT_MODIFIED_RESPONSE;
                            next_front_sub_block = 'b0;
                        end else begin
                            // Start issuing block read
                            produce_bypass_request = 'b1;
                            next_bypass_request.payload = '{
                                bypass_id: current_bypass_id,
                                send_parent: 'b1
                                default: 'b0
                            };
                            next_bypass_request.payload.addr = encode_sub_address(
                                    decode_address(next_residual_address).tag, 
                                    decode_address(next_residual_address).index, 
                                    'b0);
                            next_state = BLOCK_READ;
                            next_front_sub_block = 'b1;
                            next_rear_sub_block = 'b0;
                            // Update metadata to recognize we have the data
                            metadata_write_enable = 'b1;
                            metadata_write_data[search_results.empty] = '{
                                mesi: CACHE_MESI_OPERATION_SHARED,
                                tag: decode_address(next_residual_address).tag,
                                default: 'b0
                            };
                            metadata_write_data = update_lru(metadata_write_data, search_results.empty);
                        end
                        next_residual_lru = search_results.empty;
                    end else begin
                        // Issue a set of eviction operations for last used line
                        initiate_complete_eviction = 'b1;
                        next_residual_lru = search_results.last_used;
                    end
                end
            end
            CACHE_MESI_OPERATION_UPGRADE: begin
                `INLINE_ASSET(search_results.found_hit)
                if (metadata_read_data[search_results.line].modifiers) begin
                    // Issue a force data eviction to single child
                    initiate_child_eviction_data = 'b1;
                end else if (metadata_read_data[search_results.line].owners) begin
                    // Issue a force eviction to multiple children (don't evict the child that requested though)
                    initiate_child_evictions = 'b1;
                    next_child_id_skip_enable = 'b1;
                    next_child_id_skip = next_child_request.child_id;
                end else if (!cache_is_mesi_dirty(metadata_read_data[search_results.line].mesi)) begin 
                    // Issue request for the data to be upgraded
                    produce_bypass_request = 'b1;
                    next_bypass_request.payload = '{bypass_id: current_bypass_id, send_parent: 'b1, op: CACHE_MESI_OPERATION_UPGRADE, addr: next_residual_address, default: 'b0};
                    next_state = PARENT_UPGRADE_RESPONSE;
                    next_front_sub_block = 'b0;
                end else begin
                    // Complete the upgrade request
                    next_child_request.valid = 'b0;
                    produce_bypass_request = 'b1;
                    next_bypass_request.payload = '{
                        bypass_id: current_bypass_id,
                        send_parent: 'b0,
                        op: CACHE_MESI_OPERATION_UPGRADE,
                        addr: next_child_request.addr,
                        id: next_child_request.child_id
                    };
                    // Update metadata table to reflect upgrade
                    metadata_write_enable = 'b1;
                    metadata_write_data[search_results.line].owners = 1'b1 << next_child_request.child_id;
                    metadata_write_data[search_results.line].modifiers = 1'b1 << next_child_request.child_id;
                end
            end

            // Service a transient eviction while we are waiting for force eviction responses
            CACHE_MESI_OPERATION_NORMAL_EVICT: begin
                // We already did a metadata lookup based on the child request address
                `INLINE_ASSERT(search_results.found_hit)
                // All we do on a transient eviction is just indicate the cache below does not have the data
                metadata_write_enable = 'b1;
                metadata_write_data[search_results.line].owners[get_id(child_request.id)] = 'b0;
            end
            // Service an eviction with data
            CACHE_MESI_OPERATION_NORMAL_EVICT_DATA: begin
                // We already did a metadata lookup based on the child request address
                `INLINE_ASSERT(search_results.found_hit)

                // Indicate that no children own or have modified versions of this data
                metadata_write_enable = 'b1;
                metadata_write_data[search_results.line].owners = 'b0;
                metadata_write_data[search_results.line].modifiers = 'b0;

                // Move to another state to handle the data
                next_state = CHILD_INITIATED_EVICTION_DATA;
                next_response_return = 'b0;
                next_data_response_return = 'b0;
                next_front_sub_block = 'b1;

                // Issue a local request to store the data
                produce_local_request = 'b1;
                next_local_request.read_enable = 'b0;
                next_local_request.write_enable = get_write_mask(child_request.write_enable, child_request.addr);
                next_local_request.addr = get_local_address(
                        decode_address(child_request.addr).index, 
                        current_front_sub_block, 
                        search_results.line);
                next_local_request.data = child_request.data;
            end
            // We should not see force eviction responses here
            CACHE_MESI_OPERATION_FORCE_EVICT, CACHE_MESI_OPERATION_FORCE_EVICT_DATA: begin
                `INLINE_ASSERT('b0)
            end
            endcase
        end

        // Process request from CPUs or equivalent that can be read, write, or atomic swap
        if (!HAS_COHERENT_CHILD && initiate_child_request) begin
            // The request can be satisifed with local data
            if (search_results.found_hit) begin         
                // Perform write from local cache
                if (HAS_COHERENT_PARENT && next_child_request.write_enable && 
                        !cache_is_mesi_dirty(metadata_read_data[search_results.line].mesi)) begin 
                    // Issue request for the data to be upgraded
                    produce_bypass_request = 'b1;
                    next_bypass_request.payload = '{bypass_id: current_bypass_id, send_parent: 'b1, op: CACHE_MESI_OPERATION_UPGRADE, addr: next_residual_address, default: 'b0};
                    next_state = PARENT_UPGRADE_RESPONSE;
                    next_front_sub_block = 'b0;
                end else begin
                    // Complete the request, we have the data
                    next_child_request.valid = 'b0;

                    // Perform read and/or write from local cache
                    produce_local_request = 'b1;
                    next_local_request.read_enable = next_child_request.read_enable;
                    next_local_request.write_enable = get_write_mask(next_child_request.write_enable, next_child_request.addr);
                    next_local_request.addr = get_local_address(
                        decode_address(next_child_request.addr).index, 
                        decode_address(next_child_request.addr).block, 
                        search_results.line);
                    next_local_request.id = next_child_request.child_id;
                    next_local_request.last = 'b1;
                    produce_local_request_meta = next_child_request.read_enable;
                    next_local_request_meta.payload = '{
                        bypass_id: current_bypass_id,
                        send_parent: 'b0,
                        op: CACHE_MESI_OPERATION_SHARED, // The operation does not matter to a processor
                        addr: 'b0
                    };

                    // Update metadata to recognize child access (and mark it dirty if our parent is incoherent)
                    metadata_write_enable = 'b1;
                    if (!HAS_COHERENT_PARENT && next_child_request.write_enable) begin
                        metadata_write_data[next_child_request.child_id].mesi = CACHE_MESI_MODIFIED;
                    end
                    metadata_write_data = update_lru(metadata_write_data, next_child_request.child_id);
                end
            end else begin // We need to get the data from our parent
                if (search_results.found_empty) begin
                    if (HAS_COHERENT_PARENT) begin
                        // Issue request for data in shared state
                        produce_bypass_request = 'b1;
                        next_bypass_request.payload = '{bypass_id: current_bypass_id, send_parent: 'b1, op: CACHE_MESI_OPERATION_SHARED, addr: next_residual_address, default: 'b0};
                        next_state = next_child_request.write_enable ? PARENT_MODIFIED_RESPONSE : PARENT_SHARED_RESPONSE;
                        next_front_sub_block = 'b0;
                    end else begin
                        // Start issuing block read
                        produce_bypass_request = 'b1;
                        next_bypass_request.payload = '{
                            bypass_id: current_bypass_id,
                            send_parent: 'b1
                            default: 'b0
                        };
                        next_bypass_request.payload.addr = encode_sub_address(
                                decode_address(next_residual_address).tag, 
                                decode_address(next_residual_address).index, 
                                'b0);
                        next_state = BLOCK_READ;
                        next_front_sub_block = 'b1;
                        next_rear_sub_block = 'b0;
                        // Update metadata to recognize we have the data
                        metadata_write_enable = 'b1;
                        metadata_write_data[search_results.empty] = '{
                            mesi: (next_child_request.write_enable ? CACHE_MESI_OPERATION_MODIFIED : CACHE_MESI_OPERATION_SHARED),
                            tag: decode_address(next_residual_address).tag,
                            default: 'b0
                        };
                        metadata_write_data = update_lru(metadata_write_data, search_results.empty);
                    end
                    next_residual_lru = search_results.empty;
                end else begin
                    // Issue a set of eviction operations for last used line
                    initiate_complete_eviction = 'b1;
                    next_residual_lru = search_results.last_used;
                end
            end
        end

        // Process an existing or new parent request --------------------------
        if (initiate_parent_request) begin
            // Find and search for line from parent in metadata table
            metadata_addr = decode_address(next_parent_request.addr).index;
            metadata_write_data = metadata_read_data;
            search_results = search_line(metadata_read_data, decode_address(next_parent_request.addr).tag);

            next_residual_address = next_parent_request.addr;
            next_residual_lru = search_results.line;

            `INLINE_ASSERT(search_results.found_hit)
            `INLINE_ASSERT(metadata_read_data[search_results.line].modifiers)
            `INLINE_ASSERT(next_parent_request.op.op == CACHE_MESI_OPERATION_FORCE_EVICT)

            // If we get a parent eviction request we might still have a miss if it was pre-empted
            if (search_results.found_hit) begin
                // Setup for evicting this cache line
                initiate_complete_eviction = 'b1;
                // If no children have the cache line then we are about to do the final step of eviction
                if (metadata_read_data[search_results.line].owners == 'b0) begin
                    `INLINE_ASSERT(metadata_read_data[search_results.line].modifiers == 'b0)
                    next_parent_request.valid = 'b0;
                end
            end
        end

        // Handle steps for completely removing a cache line from this cache and its children
        // (next_residual_address, next_residual_lru)
        if (initiate_complete_eviction) begin
            `INLINE_ASSERT(cache_is_mesi_valid(metadata_read_data[next_residual_lru]))
            // Evict modified data from child
            if (IS_COHERENT && !IS_FIRST_LEVEL && metadata_read_data[next_residual_lru].modifiers) begin
                initiate_child_eviction_data = 'b1;
            // Evict unmodified data from children
            end else if (IS_COHERENT && !IS_FIRST_LEVEL && metadata_read_data[next_residual_lru].owners) begin
                initiate_child_evictions = 'b1;
                next_child_id_skip_enable = 'b0;
            // Return modified data from cache line
            end else if (cache_is_mesi_dirty(metadata_read_data[next_residual_lru])) begin
                // Issue the start of a parent eviction response
                produce_local_request = 'b1;
                produce_local_request_meta = 'b1;
                next_local_request.read_enable = 'b1;
                next_local_request.write_enable = 'b0;
                // We are starting on block zero
                next_local_request.addr = get_local_address(decode_address(next_residual_address).index, 'b0, next_residual_lru);
                next_local_request.last = 'b0;

                next_local_request_meta.payload = '{
                    bypass_id: current_bypass_id,
                    send_parent: 'b1,
                    default: 'b0
                };
                if (IS_COHERENT && !IS_LAST_LEVEL) begin
                    next_local_request_meta.payload.op = CACHE_MESI_OPERATION_FORCE_EVICT;
                end else begin
                    next_local_request_meta.payload.addr = encode_sub_address(
                            decode_address(next_residual_address).tag, 
                            decode_address(next_residual_address).index, 
                            'b0);
                end

                // Clean the entry in the metadata table
                metadata_write_enable = 'b1;
                metadata_write_data[next_residual_lru].mesi = CACHE_MESI_INVALID;
                // Clear out parent request if we are doing the last thing we need for it
                next_state = (IS_COHERENT && !IS_LAST_LEVEL) ? PARENT_EVICTION_DATA_RESPONSE : BLOCK_WRITE;
                next_front_sub_block = 'b1;
            // Return response for unmodified eviction if we have a parent to send it to
            end else begin
                // Issue single beat parent eviction response
                produce_bypass_request = (IS_COHERENT && !IS_LAST_LEVEL);
                next_bypass_request.payload = '{
                    bypass_id: current_bypass_id,
                    send_parent: 'b1,
                    op: CACHE_MESI_OPERATION_FORCE_EVICT,
                    id: 'b0, // The id does not matter for a response to the parent
                    addr: 'b0 // We are neither sending address nor data
                };
                // Clean the entry in the metadata table
                metadata_write_enable = 'b1;
                metadata_write_data[next_residual_lru].mesi = CACHE_MESI_INVALID;
            end
        end

        // Handle evicting from children, either getting data back or just responses
        // (next_child_id, next_residual_address, next_child_map, next_residual_lru)
        if (initiate_child_evictions) begin
            next_child_map = metadata_read_data[next_residual_lru].owners;
            // Unmark owner in mask if we are going to skip it (used for upgrade requests)
            if (next_child_id_skip_enable) begin
                next_child_map[next_child_id_skip] = 'b0;
            end
            next_child_id = find_next_bit(next_child_map, 'b0);

            // Issue eviction request to the correct child
            produce_bypass_request = 'b1;
            next_bypass_request.payload = '{
                bypass_id: current_bypass_id,
                send_parent: 'b0,
                op: CACHE_MESI_OPERATION_FORCE_EVICT,
                id: next_child_id,
                addr: next_residual_address
            };
            // Updata metadata table that there are no current owners
            metadata_write_enable = 'b1;
            metadata_write_data[next_residual_lru].owners = 'b0;
            metadata_write_data[next_residual_lru].modifiers = 'b0;
            // Possibly we already are at the last child or there are no more children past the current one
            next_state = ((next_child_id == PORTS-1) || (find_next_bit(next_child_map, next_child_id + 'b1) == 'b0)) ? 
                    CHILD_EVICTION_RESPONSES : CHILD_EVICTION_REQUESTS;
            // Find out what the second child id would be
            next_child_id = find_next_bit(next_child_map, next_child_id + 'b1);
        end else if (initiate_child_eviction_data) begin
            next_child_map = metadata_read_data[next_residual_lru].modifiers;
            next_child_id = find_next_bit(next_child_map, 'b0);

            // Issue a force eviction with data to the correct child
            produce_bypass_request = 'b1;
            next_bypass_request.payload = '{
                bypass_id: current_bypass_id,
                send_parent: 'b0,
                op: CACHE_MESI_OPERATION_FORCE_EVICT_DATA,
                id: next_child_id,
                addr: next_residual_address
            };
            // Clear the modifier flags in the metadata table
            metadata_write_enable = 'b1;
            metadata_write_data[next_residual_lru].modifiers = 'b0;
            metadata_write_data[next_residual_lru].owners = 'b0;
            next_state = CHILD_EVICTION_DATA_RESPONSE;
        end

        `INLINE_ASSERT(!initiate_child_request || !initiate_parent_request)
        `INLINE_ASSERT(produce_local_request_meta -> next_local_request.read_enable)
        `INLINE_ASSERT(!produce_local_request_meta || !produce_bypass_request)
        next_bypass_id = current_bypass_id + (produce_bypass_request || produce_local_request_meta);

    end

endmodule
