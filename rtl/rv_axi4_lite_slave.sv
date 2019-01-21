`timescale 1ns/1ps

`include "../lib/rv_util.svh"
`include "../lib/rv_axi4_lite.svh"
`include "../lib/rv_mem.svh"

/*
 * An extremely light, sequential AXI4-Lite write slave, fulfilling the no
 * combinational dependency requirement of AXI between signals on any of the
 * channels.
 */
module rv_axi4_lite_write_slave #()(
    input logic clk, rst,
    
    rv_axi_addr_write_intf.in  axi_aw,
    rv_axi_write_data_intf.in  axi_w,
    rv_axi_write_resp_intf.out axi_b,
    rv_mem_intf.out            mem_w
);

    import rv_axi4_lite::*;
    import rv_mem::*;

    `STATIC_ASSERT(mem_w.DATA_WIDTH == axi_w.DATA_WIDTH)
    `STATIC_ASSERT(mem_w.ADDR_WIDTH <= axi_aw.ADDR_WIDTH)

    localparam SUB_ADDR_WIDTH = mem_w.ADDR_WIDTH;

    logic enable, axi_aw_block, axi_w_block, axi_b_block, mem_w_block;
    rv_seq_flow_controller #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(2)
    ) flow_controller (
        .clk, .rst, .enable,
        .inputs_valid({axi_aw.AWVALID, axi_w.WVALID}), 
        // .inputs_ready({axi_aw.ready, axi_w.ready}),
        .inputs_block({axi_aw_block, axi_w_block}),

        // .outputs_valid({axi_b.valid, mem_w.valid}),
        .outputs_ready({axi_b.BREADY, mem_w.ready}),
        .outputs_block({axi_b_block, mem_w_block})
    );

    typedef enum logic [1:0] {
        ADDR, DATA, MEM, RESP
    } rv_axi4_lite_write_state;

    rv_axi4_lite_write_state cs, ns;
    always_ff @ (posedge clk) begin
        if (rst) begin
            cs <= ADDR;
            mem_w.addr <= 'b0;
            mem_w.data <= 'b0;
        end else if (enable) begin
            cs <= ns;
            if (cs == ADDR) begin
                mem_w.addr <= axi_aw.AWADDR[SUB_ADDR_WIDTH-1:0];
            end
            if (cs == DATA) begin
                mem_w.data <= axi_w.WDATA;
            end
        end
    end

    always_comb begin
        // Set default outputs
        axi_b.RRESP = RV_AXI4_LITE_RESP_OKAY;
        mem_w.op = RV_MEM_WRITE;

        // Only run a single channel in each state
        axi_aw_block = (cs == ADDR);
        axi_w_block = (cs == DATA);
        mem_w_block = (cs == MEM);
        axi_b_block = (cs == RESP);

        // Bypass flow controller for flow signals
        axi_aw.AWREADY = (cs == ADDR);
        awi_w.WREADY = (cs == DATA);
        mem_w.valid = (cs == MEM);
        axi_b.BVALID = (cs == RESP);

        // Simply move to the next state linearly
        case (cs)
        ADDR: ns = DATA;
        DATA: ns = MEM;
        MEM: ns = RESP;
        RESP: ns = ADDR;
        endcase
    end

endmodule
