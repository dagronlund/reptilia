`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

module mem_crossbar #(
    parameter int SLAVE_PORTS = 1,
    parameter int MASTER_PORTS = 1,
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int MASK_WIDTH = DATA_WIDTH / 8,
    parameter logic [ADDR_WIDTH-1:0] ADDR_MAP_BEGIN [MASTER_PORTS] = 
            '{MASTER_PORTS{0}},
    parameter logic [ADDR_WIDTH-1:0] ADDR_MAP_END [MASTER_PORTS] = 
            '{MASTER_PORTS{-1}}
)(
    input logic clk, rst,

    std_mem_intf.in slaves [SLAVE_PORTS],
    std_mem_intf.out masters [MASTER_PORTS]
);

    `STATIC_ASSERT(SLAVE_PORTS > 0)
    `STATIC_ASSERT(MASTER_PORTS > 0)

    localparam SLAVE_INDEX_WIDTH = $clog2(SLAVE_PORTS);
    localparam MASTER_INDEX_WIDTH = $clog2(MASTER_PORTS);
    typedef logic [SLAVE_INDEX_WIDTH-1:0] slave_t;
    typedef logic [MASTER_INDEX_WIDTH-1:0] master_t;

    function automatic slave_t get_next_priority(
            input slave_t current_priority,
            input slave_t incr
    );
        slave_t incr_priority = current_priority + incr;
        if (incr_priority >= SLAVE_PORTS) begin
            return 'b0;
        end
        return incr_priority;
    endfunction

    typedef struct packed {
        logic read_enable;
        logic [MASK_WIDTH-1:0] write_enable;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
    } mem_t;

    logic [SLAVE_PORTS-1:0] slaves_valid, slaves_ready;
    mem_t                   slaves_payload [SLAVE_PORTS];

    logic [MASTER_PORTS-1:0] masters_valid, masters_ready;
    mem_t                    masters_payload [MASTER_PORTS];

    // Copy interfaces into arrays
    generate
    genvar k;
    for (k = 0; k < SLAVE_PORTS; k++) begin

        `PROCEDURAL_ASSERT(ADDR_WIDTH == $bits(slaves[k].addr))
        `PROCEDURAL_ASSERT(MASK_WIDTH == $bits(slaves[k].write_enable))
        `PROCEDURAL_ASSERT(DATA_WIDTH == $bits(slaves[k].data))

        always_comb begin
            slaves_valid[k] = slaves[k].valid;
            slaves_payload[k].read_enable = slaves[k].read_enable;
            slaves_payload[k].write_enable = slaves[k].write_enable;
            slaves_payload[k].addr = slaves[k].addr;
            slaves_payload[k].data = slaves[k].data;
            slaves[k].ready = slaves_ready[k];
        end
    end
    for (k = 0; k < MASTER_PORTS; k++) begin

        `PROCEDURAL_ASSERT(ADDR_WIDTH == $bits(masters[k].addr))
        `PROCEDURAL_ASSERT(MASK_WIDTH == $bits(masters[k].write_enable))
        `PROCEDURAL_ASSERT(DATA_WIDTH == $bits(masters[k].data))

        always_comb begin
            masters[k].valid = masters_valid[k];
            masters[k].read_enable = masters_payload[k].read_enable;
            masters[k].write_enable = masters_payload[k].write_enable;
            masters[k].addr = masters_payload[k].addr;
            masters[k].data = masters_payload[k].data;
            masters_ready[k] = masters[k].ready;
        end
    end
    endgenerate

    logic enable;
    logic [SLAVE_PORTS-1:0] consume;
    logic [MASTER_PORTS-1:0] produce, enable_output;
    
    std_flow #(
        .NUM_INPUTS(SLAVE_PORTS),
        .NUM_OUTPUTS(MASTER_PORTS)
    ) std_flow_inst (
        .clk, .rst,

        .valid_input(slaves_valid),
        .ready_input(slaves_ready),

        .valid_output(masters_valid),
        .ready_output(masters_ready),

        .consume, .produce,
        .enable, .enable_output
    );

    mem_t masters_payload_next [MASTER_PORTS];
    slave_t current_priority, next_priority;

    always_ff @(posedge clk) begin
        if(rst) begin
            current_priority <= 'b0;
        end else if (enable) begin
            current_priority <= next_priority;
        end

        for (int i = 0; i < MASTER_PORTS; i++) begin
            if (enable_output[i]) begin
                masters_payload[i] <= masters_payload_next[i];
            end
        end
    end

    always_comb begin
        automatic slave_t slave_index;
        automatic int master_index, incr;

        consume = 'b0;
        produce = 'b0;
        next_priority = current_priority;

        // Set default master payloads, better than just zeros
        for (master_index = 'b0; master_index < MASTER_PORTS; master_index++) begin
            masters_payload_next[master_index] = slaves_payload[0];
        end

        // Go through slaves starting at current priority
        for (incr = 'b0; incr < SLAVE_PORTS; incr++) begin
            slave_index = get_next_priority(current_priority, incr);
            // Go through all masters in order
            for (master_index = 'b0; master_index < MASTER_PORTS; master_index++) begin
                // Process slave only if it is valid
                if (slaves_valid[slave_index]) begin
                    // Slave request is in address range
                    if (slaves_payload[slave_index].addr >= ADDR_MAP_BEGIN[master_index] &&
                            slaves_payload[slave_index].addr <= ADDR_MAP_END[master_index]) begin
                        // Master has not been written to
                        if (!produce[master_index]) begin
                            consume[slave_index] = 'b1;
                            produce[master_index] = 'b1;
                            masters_payload_next[master_index] = slaves_payload[slave_index];
                            next_priority = get_next_priority(slave_index, 'b1);
                        end
                    end
                end
            end
        end
    end

endmodule
