`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "../mem/mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

module cache_encode
    import std_pkg::*;
    import stream_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
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
    
    mem_intf.in local_response,
    stream_intf.in local_response_meta, // local_meta_t
    stream_intf.in bypass_response, // bypass_t

    mem_intf.out child_response,
    mem_intf.out parent_request
);

    `STATIC_ASSERT(ADDR_WIDTH == $bits(child_response.addr))
    `STATIC_ASSERT(ADDR_WIDTH == $bits(parent_request.addr))

    `STATIC_ASSERT(DATA_WIDTH >= CHILD_DATA_WIDTH)
    `STATIC_ASSERT(CHILD_DATA_WIDTH == $bits(child_response.data))
    `STATIC_ASSERT(DATA_WIDTH == $bits(parent_request.data))

    `STATIC_ASSERT($bits(local_response.id) == $bits(child_response.id))

    localparam int WORD_BITS = $clog2(DATA_WIDTH/8);
    localparam int CHILD_WORD_BITS = $clog2(CHILD_DATA_WIDTH/8);

    typedef logic [ADDR_WIDTH-1:0] addr_t;
    typedef logic [$clog2(DATA_WIDTH_RATIO)-1:0] sub_word_addr_t;
    typedef logic [DATA_WIDTH-1:0] word_t;
    typedef logic [CHILD_DATA_WIDTH-1:0] sub_word_t;

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

    function automatic sub_word_t get_sub_word(
        input word_t word,
        input sub_word_addr_t addr
    );
        sub_word_t sub_word = 'b0;
        for (int i = 0; i < CHILD_DATA_WIDTH; i++) begin
            sub_word[i] = word[(addr*CHILD_DATA_WIDTH)+i];
        end
        return sub_word;
    endfunction

    mem_intf #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), 
            .ID_WIDTH($bits(local_response.id))) next_child_response (.clk, .rst);
    mem_intf #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) next_parent_request (.clk, .rst);
    
    logic enable;
    logic consume_local_response, consume_bypass_response;
    logic produce_child_response, produce_parent_request;

    stream_controller #(
        .NUM_INPUTS(3),
        .NUM_OUTPUTS(2)
    ) stream_controller_inst (
        .clk, .rst,

        .valid_input({local_response.valid, local_response_meta.valid, bypass_response.valid}),
        .ready_input({local_response.ready, local_response_meta.ready, bypass_response.ready}),

        .valid_output({next_child_response.valid, next_parent_request.valid}),
        .ready_output({next_child_response.ready, next_parent_request.ready}),

        .consume({consume_local_response, consume_local_response, consume_bypass_response}), 
        .produce({produce_child_response, produce_parent_request}), 
        .enable
    );

    mem_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE)
    ) child_response_stream_stage_inst (
        .clk, .rst,
        .mem_in(next_child_response), .mem_out(child_response)
    );

    mem_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_BUFFERED)
    ) parent_request_stream_stage_inst (
        .clk, .rst,
        .mem_in(next_parent_request), .mem_out(parent_request)
    );

    logic current_id, next_id;

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

    always_comb begin
        consume_local_response = 'b0;
        consume_bypass_response = 'b0;
        produce_child_response = 'b0;
        produce_parent_request = 'b0;

        next_id = current_id;

        next_child_response.read_enable = 'b0;
        next_child_response.write_enable = 'b0;
        next_child_response.addr = 'b0;
        if (DATA_WIDTH_RATIO > 1) begin
            next_child_response.data = get_sub_word(local_response.data,
                    local_response_meta.payload.addr[$clog2(DATA_WIDTH_RATIO)+CHILD_WORD_BITS-1:CHILD_WORD_BITS]);
        end else begin
            next_child_response.data = local_response.data;
        end
        next_child_response.id = local_response.id;

        next_parent_request.read_enable = 'b0;
        next_parent_request.write_enable = 'b0;
        next_parent_request.addr = local_response_meta.payload.addr;
        next_parent_request.data = local_response.data;
        next_parent_request.id = 'b0;

        if (bypass_response.valid && bypass_response.payload.id == current_id) begin
            consume_bypass_response = 'b1;
            next_id = current_id + 'b1;

            produce_parent_request = 'b1;

            next_parent_request.read_enable = 'b1;
            next_parent_request.write_enable = 'b0;
            next_parent_request.addr = bypass_response.payload.addr;
        end else if (local_response_meta.valid && local_response_meta.payload.id == current_id) begin
            consume_local_response = 'b1;
            next_id = current_id + 'b1;

            next_parent_request.read_enable = 'b0;
            next_parent_request.write_enable = {(DATA_WIDTH/8){1'b1}};
            next_parent_request.addr = local_response_meta.payload.addr;

            if (local_response_meta.payload.send_parent) begin
                produce_parent_request = 'b1;
            end else begin
                produce_child_response = 'b1;

            end
        end
    end

endmodule
