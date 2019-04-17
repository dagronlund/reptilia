`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/axi/axi4.svh"

/*
 * Implements a bridge from an AXI4 bus to a lighter-weight memory bus.
 */
module axi4_slave
    import axi4::*;
#(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int AXI_ID_WIDTH = 1,
    parameter int AXI_USER_WIDTH = 1,

    parameter int MEM_ADDR_WIDTH = 32,
    parameter int MEM_DATA_WIDTH = 32,
    parameter int MEM_MASK_WIDTH = MEM_DATA_WIDTH / 8
)(
    input logic clk, rst,

    axi4_ar_intf.in axi_ar,
    axi4_aw_intf.in axi_aw,
    axi4_w_intf.in axi_w,
    axi4_r_intf.out axi_r, // Buffered
    axi4_b_intf.out axi_b, // Buffered
    
    std_mem_intf.out mem_request, // Buffered
    std_mem_intf.in mem_response
);

    // Check AXI interface parameters
    `STATIC_ASSERT(AXI_ADDR_WIDTH == $bits(axi_ar.araddr) && AXI_ADDR_WIDTH == $bits(axi_aw.awaddr))
    `STATIC_ASSERT(AXI_USER_WIDTH == $bits(axi_ar.aruser) && AXI_USER_WIDTH == $bits(axi_aw.awuser))
    `STATIC_ASSERT(AXI_ID_WIDTH == $bits(axi_ar.arid) && AXI_ID_WIDTH == $bits(axi_aw.awid) &&
            AXI_ID_WIDTH == $bits(axi_r.rid) && AXI_ID_WIDTH == $bits(axi_b.bid))
    `STATIC_ASSERT(AXI_DATA_WIDTH == $bits(axi_w.wdata) && AXI_DATA_WIDTH == $bits(axi_r.rdata))

    // Check memory interface parameters
    `STATIC_ASSERT(MEM_DATA_WIDTH == $bits(mem_request.data) && MEM_DATA_WIDTH == $bits(mem_response.data))
    `STATIC_ASSERT(MEM_ADDR_WIDTH == $bits(mem_request.addr) && MEM_ADDR_WIDTH == $bits(mem_response.addr))

    // Check memory-to-AXI parameters
    `STATIC_ASSERT(MEM_DATA_WIDTH == AXI_DATA_WIDTH)

    // localparam int AXI_ADDR_OFFSET = $clog2($bits(axi_ar.araddr));
    localparam int AXI_ADDR_PAGE_WIDTH = (AXI_ADDR_WIDTH > 12) ? 12 : AXI_ADDR_WIDTH;

    typedef logic [AXI_ADDR_WIDTH-1:0] base_addr_t;
    typedef logic [AXI_ADDR_PAGE_WIDTH-1:0] page_addr_t;

    typedef logic [AXI_ID_WIDTH-1:0] id_t;

    function automatic base_addr_t get_actual_address(
            input base_addr_t base_addr,
            input page_addr_t page_addr
    );
        base_addr_t mask = ~('hFFF);
        return (base_addr & mask) | page_addr;
    endfunction

    typedef struct packed {
        logic                      read_enable;
        logic [MEM_MASK_WIDTH-1:0] write_enable;
        logic [MEM_ADDR_WIDTH-1:0] addr;
        logic [MEM_DATA_WIDTH-1:0] data;
    } mem_t;

    typedef struct packed {
        logic [AXI_DATA_WIDTH-1:0] rdata;
        logic                      rlast;
        axi4_resp_t                rresp;
        logic [AXI_ID_WIDTH-1:0]   rid;
    } axi_r_t;

    typedef struct packed {
        axi4_resp_t              bresp;
        logic [AXI_ID_WIDTH-1:0] bid;
    } axi_b_t;

    logic enable;
    logic consume_axi_ar, consume_axi_aw, consume_axi_w, consume_mem_response;
    logic produce_axi_r, produce_axi_b, produce_mem_request;

    std_stream_intf #(.T(mem_t)) mem_request_mid (.clk, .rst);
    std_stream_intf #(.T(mem_t)) mem_request_packed (.clk, .rst);

    std_stream_intf #(.T(axi_r_t)) axi_r_mid (.clk, .rst);
    std_stream_intf #(.T(axi_r_t)) axi_r_packed (.clk, .rst);

    std_stream_intf #(.T(axi_b_t)) axi_b_mid (.clk, .rst);
    std_stream_intf #(.T(axi_b_t)) axi_b_packed (.clk, .rst);

    always_comb begin
        mem_request.valid = mem_request_packed.valid;
        mem_request.read_enable = mem_request_packed.payload.read_enable;
        mem_request.write_enable = mem_request_packed.payload.write_enable;
        mem_request.addr = mem_request_packed.payload.addr;
        mem_request.data = mem_request_packed.payload.data;
        // mem_request.id = mem_request_packed.payload.id;
        mem_request_packed.ready = mem_request.ready;

        axi_r.rvalid = axi_r_packed.valid;
        axi_r.rdata = axi_r_packed.payload.rdata;
        axi_r.rlast = axi_r_packed.payload.rlast;
        axi_r.rresp = axi_r_packed.payload.rresp;
        axi_r.rid = axi_r_packed.payload.rid;
        axi_r_packed.ready = axi_r.rready;

        axi_b.bvalid = axi_b_packed.valid;
        axi_b.bresp = axi_b_packed.payload.bresp;
        axi_b.bid = axi_b_packed.payload.bid;
        axi_b_packed.ready = axi_b.bready;
    end

    std_flow_lite #(
        .NUM_INPUTS(4),
        .NUM_OUTPUTS(3)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({axi_ar.arvalid, axi_aw.awvalid, axi_w.wvalid, mem_response.valid}),
        .ready_input({axi_ar.arready, axi_aw.awready, axi_w.wready, mem_response.ready}),

        .valid_output({axi_r_mid.valid, axi_b_mid.valid, mem_request_mid.valid}),
        .ready_output({axi_r_mid.ready, axi_b_mid.ready, mem_request_mid.ready}),

        .consume({consume_axi_ar, consume_axi_aw, consume_axi_w, consume_mem_response}),
        .produce({produce_axi_r, produce_axi_b, produce_mem_request}),
        .enable
    );

    std_flow_stage #(
        .T(mem_t),
        .MODE(2)
    ) std_flow_stage_mem_request_inst (
        .clk, .rst,
        .stream_in(mem_request_mid),
        .stream_out(mem_request_packed)
    );

    std_flow_stage #(
        .T(axi_r_t),
        .MODE(2)
    ) std_flow_stage_axi_r_inst (
        .clk, .rst,
        .stream_in(axi_r_mid),
        .stream_out(axi_r_packed)
    );

    std_flow_stage #(
        .T(axi_b_t),
        .MODE(2)
    ) std_flow_stage_axi_b_inst (
        .clk, .rst,
        .stream_in(axi_b_mid),
        .stream_out(axi_b_packed)
    );

    typedef enum logic [2:0] {
        IDLE = 3'b000,
        WRITE = 3'b001,
        WRITE_FIXED = 3'b010,
        READ = 3'b011,
        READ_FIXED = 3'b100,
        UNDEF = 3'bXXX
    } state_t;

    base_addr_t current_base_addr, next_base_addr;
    page_addr_t current_page_addr, next_page_addr;
    page_addr_t current_page_step, next_page_step;

    axi4_len_t current_burst_limit, next_burst_limit;
    axi4_len_t current_burst, next_burst;
    axi4_len_t current_burst_read, next_burst_read;

    id_t current_id, next_id;

    logic current_read_request_done, next_read_request_done;

    state_t current_state, next_state;

    always_ff @(posedge clk) begin
        if (rst) begin
            current_base_addr <= 'b0;
            current_page_addr <= 'b0;
            current_page_step <= 'b1;

            current_burst_limit <= 'b0;
            current_burst <= 'b0;
            current_burst_read <= 'b0;

            current_id <= 'b0;

            current_read_request_done <= 'b0;

            current_state <= IDLE;
        end else if (enable) begin
            current_base_addr <= next_base_addr;
            current_page_addr <= next_page_addr;
            current_page_step <= next_page_step;

            current_burst_limit <= next_burst_limit;
            current_burst <= next_burst;
            current_burst_read <= next_burst_read;

            current_id <= next_id;

            current_read_request_done <= next_read_request_done;
            
            current_state <= next_state;
        end
    end

    always_comb begin
        automatic mem_t next_mem_request = '{default: 'b0};
        automatic axi_r_t next_axi_r = '{default: 'b0};
        automatic axi_b_t next_axi_b = '{default: 'b0};

        consume_axi_ar = 'b0;
        consume_axi_aw = 'b0;
        consume_axi_w = 'b0;
        consume_mem_response = 'b0;
        
        produce_axi_r = 'b0;
        produce_axi_b = 'b0;
        produce_mem_request = 'b0;

        next_state = current_state;

        next_base_addr = current_base_addr;
        next_page_addr = current_page_addr;
        next_page_step = current_page_step;

        next_burst_limit = current_burst_limit;
        next_burst = current_burst;
        next_burst_read = current_burst_read;

        next_id = current_id;

        next_read_request_done = current_read_request_done;

        next_axi_r.rlast = 'b0;
        next_axi_r.rdata = mem_response.data;
        next_axi_r.rresp = AXI4_RESP_OKAY;
        next_axi_r.rid = current_id;
        next_axi_b.bresp = AXI4_RESP_OKAY;
        next_axi_b.bid = current_id;
        next_mem_request.addr = get_actual_address(next_base_addr, next_page_addr);
        next_mem_request.data = axi_w.wdata;

        case (next_state)
        IDLE: begin
            next_burst = 'b0;
            if (axi_aw.awvalid) begin
                consume_axi_aw = 'b1;
                next_state = (axi_aw.awburst == AXI4_BURST_FIXED) ? WRITE_FIXED : WRITE;
                
                next_base_addr = axi_aw.awaddr;
                next_page_addr = axi_aw.awaddr;
                next_page_step = axi4_len_from_size(axi_aw.awsize);

                next_burst_limit = axi_aw.awlen;

                next_id = axi_aw.awid;
            end else if (axi_ar.arvalid) begin
                consume_axi_ar = 'b1;
                next_state = (axi_ar.arburst == AXI4_BURST_FIXED) ? READ_FIXED : READ;

                next_base_addr = axi_ar.araddr;
                next_page_addr = axi_ar.araddr;
                next_page_step = axi4_len_from_size(axi_ar.arsize);
                
                next_burst_limit = axi_ar.arlen;

                next_id = axi_ar.arid;

                next_read_request_done = 'b0;
            end
        end
        WRITE, WRITE_FIXED: begin
            consume_axi_w = 'b1;
            produce_mem_request = 'b1;

            next_mem_request.read_enable = 'b0;
            next_mem_request.write_enable = axi_w.wstrb;

            if (next_burst == next_burst_limit) begin
                produce_axi_b = 'b1;
                next_state = IDLE;
            end else begin
                next_burst += 1;
            end

            next_page_addr += (next_state == WRITE) ? next_page_step : 'b0;
        end
        READ, READ_FIXED: begin
            produce_mem_request = (!next_read_request_done);

            next_mem_request.read_enable = 'b1;
            next_mem_request.write_enable = 'b0;

            if (next_burst == next_burst_limit) begin
                next_read_request_done = 'b1;
            end else begin
                next_burst += 1;
            end

            if (mem_response.valid) begin
                produce_axi_r = 'b1;
                consume_mem_response = 'b1;
                
                if (next_burst_read == next_burst_limit) begin
                    next_axi_r.rlast = 'b1;
                    next_state = IDLE;
                end else begin
                    next_burst_read += 1;
                end
            end
            
            next_page_addr += (next_state == READ) ? next_page_step : 'b0;
        end

        endcase

        mem_request_mid.payload = next_mem_request;
        axi_r_mid.payload = next_axi_r;
        axi_b_mid.payload = next_axi_b;
    end

    // logic [ADDR_WIDTH-1:0] araddr;
    // axi4_burst_t           arburst;
    // axi4_len_t             arlen;
    // // axi4_size_t            arsize;
    // logic [ID_WIDTH-1:0]   arid; // Forwarded to rid

    // logic [DATA_WIDTH-1:0] rdata;
    // logic                  rlast;
    // axi4_resp_t            rresp; // Tied to AXI4_RESP_OKAY
    // logic [ID_WIDTH-1:0]   rid;

    // logic [ADDR_WIDTH-1:0] awaddr;
    // axi4_burst_t           awburst;
    // axi4_len_t             awlen;
    // // axi4_size_t            awsize;
    // logic [ID_WIDTH-1:0]   awid; // Forwarded to bid

    // logic [DATA_WIDTH-1:0]   wdata;
    // logic [STROBE_WIDTH-1:0] wstrb;
    // logic                    wlast;

    // axi4_resp_t          bresp; // Tied to AXI4_RESP_OKAY
    // logic [ID_WIDTH-1:0] bid;

endmodule

// axi4_slave_inbound axi4_slave_inbound_inst(
//     .clk, .rst,
//     .axi_ar, .axi_aw, .axi_w, .axi_b,
//     .mem_request
// );

// axi4_slave_outbound axi4_slave_outbound_inst(
//     .clk, .rst,
//     .axi_r,
//     .mem_response
// );

// module axi4_slave_inbound
//     import axi4::*;
// #()(
//     input logic clk, rst,

//     axi4_ar_intf.in axi_ar,
//     axi4_aw_intf.in axi_aw,
//     axi4_w_intf.in axi_w,
//     axi4_b_intf.out axi_b,
    
//     std_mem_intf.out mem_request
// );

// endmodule

// module axi4_slave_outbound
//     import axi4::*;
// #()(
//     input logic clk, rst,
    
//     std_mem_intf.in mem_response,

//     axi4_r_intf.out axi_r
// );

// endmodule
