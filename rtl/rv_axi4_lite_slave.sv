`timescale 1ns/1ps

`include "../lib/rv_util.svh"
`include "../lib/rv_axi4_lite.svh"
`include "../lib/rv_mem.svh"

/*
 * A set of extremely light, sequential AXI4-Lite slaves, fulfilling the
 * no combinational dependency requirement of AXI between signals on any of the
 * channels. This does however require the address to be available before or
 * at the same time as the data, which means the interconnect cannot require
 * the data be accepted before providing the address.
 * 
 * rv_axi4_lite_write_slave:
 * ...
 * rv_axi4_lite_read_slave:
 * ...
 * rv_axi4_lite_slave:
 * ...
 */

module rv_axi4_lite_write_slave #()(
    input logic clk, rst,
    
    rv_axi4_lite_aw_intf.in axi_aw,
    rv_axi4_lite_w_intf.in  axi_w,
    rv_axi4_lite_b_intf.out axi_b,
    rv_mem_intf.out         mem_write_command
);

    import rv_axi4_lite::*;
    import rv_mem::*;

    `STATIC_ASSERT(mem_write_command.DATA_WIDTH == axi_w.DATA_WIDTH)
    `STATIC_ASSERT(mem_write_command.ADDR_WIDTH <= axi_aw.ADDR_WIDTH)

    localparam SUB_ADDR_WIDTH = $bits(mem_write_command.addr);

    logic enable, axi_aw_block, axi_w_block, axi_b_block, mem_write_command_block;
    rv_seq_flow_controller #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(2)
    ) flow_controller (
        .clk, .rst, .enable,
        .inputs_valid({axi_aw.AWVALID, axi_w.WVALID}), 
        .inputs_block({axi_aw_block, axi_w_block}),

        .outputs_ready({axi_b.BREADY, mem_write_command.ready}),
        .outputs_block({axi_b_block, mem_write_command_block})
    );

    typedef enum logic [1:0] {
        ADDR, DATA, MEM, RESP
    } rv_axi4_lite_write_state;

    rv_axi4_lite_write_state cs, ns;
    always_ff @ (posedge clk) begin
        if (rst) begin
            cs <= ADDR;
            mem_write_command.addr <= 'b0;
            mem_write_command.data <= 'b0;
        end else if (enable) begin
            cs <= ns;
            if (cs == ADDR) begin
                mem_write_command.addr <= axi_aw.AWADDR[SUB_ADDR_WIDTH-1:0];
            end
            if (cs == DATA) begin
                mem_write_command.data <= axi_w.WDATA;
            end
        end
    end

    always_comb begin
        // Set default outputs
        axi_b.BRESP = RV_AXI4_LITE_RESP_OKAY;
        mem_write_command.op = RV_MEM_WRITE;

        // Only run a single channel in each state
        axi_aw_block = (cs == ADDR);
        axi_w_block = (cs == DATA);
        mem_write_command_block = (cs == MEM);
        axi_b_block = (cs == RESP);

        // Bypass flow controller for flow signals
        axi_aw.AWREADY = (cs == ADDR);
        axi_w.WREADY = (cs == DATA);
        mem_write_command.valid = (cs == MEM);
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

module rv_axi4_lite_read_slave #()(
    input logic clk, rst,
    
    rv_axi4_lite_ar_intf.in axi_ar,
    rv_axi4_lite_r_intf.out axi_r,

    rv_mem_intf.out         mem_read_command,
    rv_mem_intf.in          mem_read_result
);

    import rv_axi4_lite::*;
    import rv_mem::*;

    `STATIC_ASSERT(mem_read_command.DATA_WIDTH == axi_r.DATA_WIDTH)
    `STATIC_ASSERT(mem_read_result.DATA_WIDTH == axi_r.DATA_WIDTH)
    `STATIC_ASSERT(mem_read_command.ADDR_WIDTH <= axi_ar.ADDR_WIDTH)
    `STATIC_ASSERT(mem_read_command.ADDR_WIDTH == mem_read_result.ADDR_WIDTH)

    localparam SUB_ADDR_WIDTH = $bits(mem_read_command.addr);

    logic enable, axi_ar_block, axi_r_block, 
            mem_read_command_block, mem_read_result_block;
    rv_seq_flow_controller #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(2)
    ) flow_controller (
        .clk, .rst, .enable,
        .inputs_valid({axi_ar.ARVALID, mem_read_result.valid}), 
        .inputs_block({axi_ar_block, mem_read_result_block}),

        .outputs_ready({axi_r.RREADY, mem_read_command.ready}),
        .outputs_block({axi_r_block, mem_read_command_block})
    );

    typedef enum logic [1:0] {
        ADDR, MEM_COMMAND, MEM_RESULT, DATA
    } rv_axi4_lite_read_state;

    rv_axi4_lite_read_state cs, ns;
    always_ff @ (posedge clk) begin
        if (rst) begin
            cs <= ADDR;
            mem_read_command.addr <= 'b0;
            axi_r.RDATA <= 'b0;
        end else if (enable) begin
            cs <= ns;
            if (cs == ADDR) begin
                mem_read_command.addr <= axi_ar.ARADDR[SUB_ADDR_WIDTH-1:0];
            end
            if (cs == MEM_RESULT) begin
                axi_r.RDATA <= mem_read_result.data;
            end
        end
    end

    always_comb begin
        // Set default outputs
        axi_r.RRESP = RV_AXI4_LITE_RESP_OKAY;
        mem_read_command.op = RV_MEM_READ;
        mem_read_command.data = 'b0;

        // Only run a single channel in each state
        axi_ar_block = (cs == ADDR);
        mem_read_command_block = (cs == MEM_COMMAND);
        mem_read_result_block = (cs == MEM_RESULT);
        axi_r_block = (cs == DATA);

        // Bypass flow controller for flow signals
        axi_ar.ARREADY = (cs == ADDR);
        mem_read_command.valid = (cs == MEM_COMMAND);
        mem_read_result.ready = (cs == MEM_RESULT);
        axi_r.RVALID = (cs == DATA);

        // Simply move to the next state linearly
        case (cs)
        ADDR: ns = MEM_COMMAND;
        MEM_COMMAND: ns = MEM_RESULT;
        MEM_RESULT: ns = DATA;
        DATA: ns = ADDR;
        endcase
    end

endmodule

module rv_axi4_lite_slave #()(
    input logic clk, rst,

    rv_axi4_lite_aw_intf.in axi_aw,
    rv_axi4_lite_w_intf.in  axi_w,
    rv_axi4_lite_b_intf.out axi_b,
    rv_axi4_lite_ar_intf.in axi_ar,
    rv_axi4_lite_r_intf.out axi_r,

    rv_mem_intf.out mem_command,
    rv_mem_intf.in mem_result
);

    import rv_mem::*;

    `STATIC_ASSERT(axi_aw.ADDR_WIDTH == axi_ar.ADDR_WIDTH)
    `STATIC_ASSERT(axi_w.DATA_WIDTH == axi_r.DATA_WIDTH)

    `STATIC_ASSERT(mem_command.DATA_WIDTH == mem_result.DATA_WIDTH)
    `STATIC_ASSERT(mem_command.ADDR_WIDTH == mem_result.ADDR_WIDTH)

    localparam SUB_ADDR_WIDTH = $bits(mem_command.addr);
    localparam SUB_DATA_WIDTH = $bits(mem_command.data);

    rv_mem_intf #(
        .ADDR_WIDTH(SUB_ADDR_WIDTH),
        .DATA_WIDTH(SUB_DATA_WIDTH)
    ) mem_write_command (.clk, .rst);

    rv_mem_intf #(
        .ADDR_WIDTH(SUB_ADDR_WIDTH),
        .DATA_WIDTH(SUB_DATA_WIDTH)
    ) mem_read_command (.clk, .rst);

    rv_mem_intf #(
        .ADDR_WIDTH(SUB_ADDR_WIDTH),
        .DATA_WIDTH(SUB_DATA_WIDTH)
    ) mem_read_result (.clk, .rst);

    rv_axi4_lite_write_slave rv_axi4_lite_write_slave_inst (
        .clk, .rst,
        .axi_aw, .axi_w, .axi_b,
        .mem_write_command
    );

    rv_axi4_lite_read_slave rv_axi4_lite_read_slave_inst (
        .clk, .rst,
        .axi_ar, .axi_r,
        .mem_read_command, .mem_read_result
    );

    // Merges memory interfaces together, gives priority
    // to write requests over read requests
    always_comb begin
        if (mem_write_command.valid) begin
            // Flow
            mem_command.valid = 1'b1;
            mem_command.op = RV_MEM_WRITE;
            mem_command.addr = mem_write_command.addr;
            mem_command.data = mem_write_command.data;
            // Backflow
            mem_write_command.ready = mem_command.ready;
            mem_read_command.ready = 1'b0;
        end else if (mem_read_command.valid) begin
            // Flow
            mem_command.valid = 1'b1;
            mem_command.op = RV_MEM_READ;
            mem_command.addr = mem_read_command.addr;
            mem_command.data = mem_read_command.data;
            // Backflow
            mem_write_command.ready = 1'b0;
            mem_read_command.ready = mem_command.ready;
        end else begin
            // Flow
            mem_command.valid = 1'b0;
            mem_command.op = RV_MEM_WRITE;
            mem_command.addr = mem_write_command.addr;
            mem_command.data = mem_write_command.data;
            // Backflow
            mem_write_command.ready = 1'b0;
            mem_read_command.ready = 1'b0;
        end

        // Ties mem_result to mem_read_result
        // Flow
        mem_read_result.valid = mem_result.valid;
        mem_read_result.op = RV_MEM_READ;
        mem_read_result.addr = mem_result.addr;
        mem_read_result.data = mem_result.data;
        // Backflow
        mem_result.ready = mem_read_result.ready;
    end

endmodule

module rv_axi4_lite_slave_independent_tb();

    import rv_axi4_lite::*;
    import rv_mem::*;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    // Test Write Slave
    rv_axi4_lite_aw_intf axi_aw(.clk, .rst);
    rv_axi4_lite_w_intf  axi_w(.clk, .rst);
    rv_axi4_lite_b_intf  axi_b(.clk, .rst);
    rv_mem_intf          mem_write_command(.clk, .rst);

    rv_axi4_lite_write_slave write_slave_inst (
        .clk, .rst,
        .axi_aw, .axi_w, .axi_b, .mem_write_command
    );

    logic [9:0] addr_temp;
    logic [31:0] data_temp;
    rv_memory_op op_temp;
    rv_axi4_lite_resp resp_temp;

    initial begin
        axi_aw.AWVALID = 'b0;
        axi_w.WVALID = 'b0;
        axi_b.BREADY = 'b0;
        mem_write_command.ready = 'b0;
        while (rst) @ (posedge clk);

        fork
            axi_aw.send('h42, rv_axi4_lite_prot'(3'b0));
            axi_w.send('h69, 'he);
            axi_b.recv(resp_temp);
            mem_write_command.recv(op_temp, addr_temp, data_temp);
        join
    end

    // Test Read Slave
    rv_axi4_lite_ar_intf axi_ar(.clk, .rst);
    rv_axi4_lite_r_intf  axi_r(.clk, .rst);
    rv_mem_intf          mem_read_command(.clk, .rst);
    rv_mem_intf          mem_read_result(.clk, .rst);    

    rv_axi4_lite_read_slave read_slave_inst (
        .clk, .rst,
        .axi_ar, .axi_r, .mem_read_command, .mem_read_result
    );

    logic [31:0] read_result_temp;
    rv_axi4_lite_resp read_resp_temp;

    rv_memory_op read_op_temp;
    logic [9:0] read_addr_temp;
    logic [31:0] read_data_temp;

    initial begin
        axi_ar.ARVALID = 'b0;
        mem_read_result.valid = 'b0;
        axi_r.RREADY = 'b0;
        mem_read_command.ready = 'b0;
        while (rst) @ (posedge clk);

        fork
            axi_ar.send('h42, rv_axi4_lite_prot'(3'b0));
            axi_r.recv(read_result_temp, read_resp_temp);
            begin
                mem_read_command.recv(read_op_temp, read_addr_temp, read_data_temp);
                mem_read_result.send(read_op_temp, read_addr_temp, read_data_temp + read_addr_temp);
            end
        join
    end

endmodule

module rv_axi4_lite_slave_tb();

    import rv_axi4_lite::*;
    import rv_mem::*;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    rv_axi4_lite_aw_intf axi_aw(.clk, .rst);
    rv_axi4_lite_w_intf  axi_w(.clk, .rst);
    rv_axi4_lite_b_intf  axi_b(.clk, .rst);
    rv_axi4_lite_ar_intf axi_ar(.clk, .rst);
    rv_axi4_lite_r_intf  axi_r(.clk, .rst);
    rv_mem_intf          mem_command(.clk, .rst);
    rv_mem_intf          mem_result(.clk, .rst);

    rv_axi4_lite_slave slave_inst (
        .clk, .rst,
        .axi_aw, .axi_w, .axi_b, .axi_ar, .axi_r, 
        .mem_command, .mem_result
    );

    rv_memory_op op_temp;
    logic [9:0] addr_temp;
    logic [31:0] data_temp;

    rv_axi4_lite_resp resp_temp;

    rv_memory_op read_op_temp;
    logic [9:0] read_addr_temp;
    logic [31:0] read_data_temp;

    initial begin
        axi_aw.AWVALID = 'b0;
        axi_w.WVALID = 'b0;
        axi_b.BREADY = 'b0;
        axi_ar.ARVALID = 'b0;
        axi_r.RREADY = 'b0;
        mem_result.valid = 'b0;
        mem_command.ready = 'b0;
        while (rst) @ (posedge clk);

        // Test Write
        fork
            axi_aw.send('h42, rv_axi4_lite_prot'(3'b0));
            axi_w.send('h69, 'he);
            axi_b.recv(resp_temp);
            mem_command.recv(op_temp, addr_temp, data_temp);
        join

        // Test Read
        fork
            axi_ar.send('h42, rv_axi4_lite_prot'(3'b0));
            axi_r.recv(data_temp, resp_temp);
            begin
                mem_command.recv(read_op_temp, read_addr_temp, read_data_temp);
                mem_result.send(read_op_temp, read_addr_temp, read_data_temp + read_addr_temp);
            end
        join

        // Test Simultaneous
        fork
            axi_aw.send('h42, rv_axi4_lite_prot'(3'b0));
            axi_w.send('h69, 'he);
            axi_b.recv(resp_temp);
            axi_ar.send('h42, rv_axi4_lite_prot'(3'b0));
            axi_r.recv(data_temp, resp_temp);

            begin
                mem_command.recv(op_temp, addr_temp, data_temp);
                if (op_temp == RV_MEM_READ) begin
                    mem_result.send(RV_MEM_READ, addr_temp, 'h1234);
                end

                mem_command.recv(op_temp, addr_temp, data_temp);
                if (op_temp == RV_MEM_READ) begin
                    mem_result.send(RV_MEM_READ, addr_temp, 'h1234);
                end

            end
        join
    end

endmodule