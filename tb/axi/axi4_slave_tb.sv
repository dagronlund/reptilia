`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"
`include "../../lib/axi/axi4.svh"

module axi4_slave_tb
#()();

    import axi4::*;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    axi4_ar_intf axi_ar(.clk, .rst);
    axi4_aw_intf axi_aw(.clk, .rst);
    axi4_w_intf axi_w(.clk, .rst);
    axi4_r_intf axi_r(.clk, .rst);
    axi4_b_intf axi_b(.clk, .rst);

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_request (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) mem_response (.clk, .rst);

    axi4_slave #(
    ) axi4_slave_inst (
        .clk, .rst,

        .axi_ar, .axi_aw, .axi_w, .axi_r, .axi_b,
        .mem_request, .mem_response
    );

    // localparam int PORTS = 2;

    // // std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) masters [PORTS] (.clk, .rst);
    // // std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) slaves [PORTS] (.clk, .rst);

    // std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) slave0 (.clk, .rst);
    // std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) slave1 (.clk, .rst);

    // std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) master0 (.clk, .rst);
    // std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) master1 (.clk, .rst);

    // mem_crossbar #(
    //     .ADDR_WIDTH(32),
    //     .DATA_WIDTH(32),
    //     .SLAVE_PORTS(PORTS),
    //     .MASTER_PORTS(PORTS),
    //     .ADDR_MAP_BEGIN('{32'h0, 32'h8000_0000}),
    //     .ADDR_MAP_END('{32'h7FFF_FFFF, 32'hFFFF_FFFF})
    // ) mem_crossbar_inst (
    //     .clk, .rst,
    //     .slaves('{slave0, slave1}),
    //     .masters('{master0, master1})
    // );

    logic re;
    logic [3:0] we; 
    logic [31:0] data, addr;
    logic id;

    axi4_resp_t temp_resp;
    logic [31:0] temp_data;
    logic temp_last;
    logic temp_id;

    initial begin
        axi_ar.arvalid = 'b0;
        axi_aw.awvalid = 'b0;
        axi_w.wvalid = 'b0;
        mem_response.valid = 'b0;
        axi_b.bready = 'b0;
        axi_r.rready = 'b0;
        mem_request.ready = 'b0;
        while (rst) @ (posedge clk);

        fork
        begin
            axi_aw.send('h50000400, 
                    AXI4_BURST_INCR, 
                    axi4_cache_t'(4'b0), 
                    'h1, 
                    AXI4_LOCK_NORMAL, 
                    axi4_prot_t'(3'b0), 
                    'b0, 
                    'h2, 
                    'b0, 
                    'b0);

            axi_w.send('h42, 'hF, 'h1);
            axi_w.send('h69, 'hF, 'h1);

            axi_ar.send('h400, 
                    AXI4_BURST_INCR, 
                    axi4_cache_t'(4'b0), 
                    'h1, 
                    AXI4_LOCK_NORMAL, 
                    axi4_prot_t'(3'b0), 
                    'b0, 
                    'h2, 
                    'b0, 
                    'b0);

        end
        begin
            mem_request.recv(re, we, addr, data, id);
            mem_request.recv(re, we, addr, data, id);

            mem_request.recv(re, we, addr, data, id);
            mem_response.send('b0, 'b0, 'b0, addr << 1, 'b0);

            mem_request.recv(re, we, addr, data, id);
            mem_response.send('b0, 'b0, 'b0, addr << 1, 'b0);
        end
        begin
            axi_b.recv(temp_resp, temp_id); 

        end
        begin
            axi_r.recv(temp_data, temp_last, temp_resp, temp_id);
            axi_r.recv(temp_data, temp_last, temp_resp, temp_id);
        end
        join

    end

endmodule
