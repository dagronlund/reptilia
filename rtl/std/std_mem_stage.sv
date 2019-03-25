`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

/*
 * Implements a variable length pipeline stage
 */
module std_mem_stage #(
    parameter int LATENCY = 1
)(
    input logic clk, rst,
    std_mem_intf.in data_in,
    std_mem_intf.out data_out
);

    `STATIC_ASSERT($size(data_in.addr) == $size(data_out.addr))
    `STATIC_ASSERT($size(data_in.data) == $size(data_out.data))

    localparam ADDR_WIDTH = $bits(data_in.addr);
    localparam DATA_WIDTH = $bits(data_in.data);
    localparam MASK_WIDTH = $bits(data_in.write_enable);
    
    typedef logic [ADDR_WIDTH-1:0] addr_t;
    typedef logic [DATA_WIDTH-1:0] data_t;
    typedef logic [MASK_WIDTH-1:0] mask_t;

    genvar k;
    generate
    if (LATENCY == 0) begin
        assign data_out.valid = data_in.valid;
        assign data_in.ready = data_out.ready;

        assign data_out.read_enable = data_in.read_enable;
        assign data_out.write_enable = data_in.write_enable;
        assign data_out.addr = data_in.addr;
        assign data_out.data = data_in.data;
    end else begin
        logic data_in_valid [LATENCY];
        logic data_in_ready [LATENCY];

        logic data_in_read_enable [LATENCY];
        mask_t data_in_write_enable [LATENCY];
        addr_t data_in_addr [LATENCY];
        data_t data_in_data [LATENCY];

        logic data_out_valid [LATENCY];
        logic data_out_ready [LATENCY];

        logic data_out_read_enable [LATENCY];
        mask_t data_out_write_enable [LATENCY];
        addr_t data_out_addr [LATENCY];
        data_t data_out_data [LATENCY];

        for (k = 0; k < LATENCY; k++) begin
            if (k == 0) begin
                assign data_in_valid[k] = data_in.valid;
                assign data_in.ready = data_in_ready[k];

                assign data_in_read_enable[k] = data_in.read_enable;
                assign data_in_write_enable[k] = data_in.write_enable;
                assign data_in_addr[k] = data_in.addr;
                assign data_in_data[k] = data_in.data;
            end else begin
                assign data_in_valid[k] = data_out_valid[k-1];
                assign data_out_ready[k-1] = data_in_ready[k];

                assign data_in_read_enable[k] = data_out_read_enable[k-1];
                assign data_in_write_enable[k] = data_out_write_enable[k-1];
                assign data_in_addr[k] = data_out_addr[k-1];
                assign data_in_data[k] = data_out_data[k-1];
            end

            if (k == LATENCY - 1) begin
                assign data_out.valid = data_out_valid[k];
                assign data_out_ready[k] = data_out.ready;

                assign data_out.read_enable = data_out_read_enable[k];
                assign data_out.write_enable = data_out_write_enable[k];
                assign data_out.addr = data_out_addr[k];
                assign data_out.data = data_out_data[k];
            end

            logic enable, enable_output_null;

            // Flow Controller
            std_flow #(
                .NUM_INPUTS(1),
                .NUM_OUTPUTS(1)
            ) std_flow_inst (
                .clk, .rst,

                .valid_input({data_in_valid[k]}),
                .ready_input({data_in_ready[k]}),
                
                .valid_output({data_out_valid[k]}),
                .ready_output({data_out_ready[k]}),

                .consume({1'b1}), .produce({1'b1}), .enable,
                .enable_output(enable_output_null)
            );

            always_ff @(posedge clk) begin
                if (enable) begin
                    data_out_read_enable[k] <= data_in_read_enable[k];
                    data_out_write_enable[k] <= data_in_write_enable[k];
                    data_out_addr[k] <= data_in_addr[k];
                    data_out_data[k] <= data_in_data[k]; 
                end
            end
        end
    end
    endgenerate

endmodule
