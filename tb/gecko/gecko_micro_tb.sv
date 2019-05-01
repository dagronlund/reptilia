`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

`include "../../lib/axi/axi4.svh"

module gecko_micro_tb
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
    import axi4::*;
#()();

    logic clk, rst_start, rst_mid, rst;
    clk_rst_gen #(.START_DELAY(120)) clk_rst_gen_inst(.clk, .rst(rst_start));
    assign rst = rst_start || rst_mid;

    logic faulted_flag, finished_flag;

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) supervisor_request (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) supervisor_response (.clk, .rst);

    std_stream_intf #(.T(logic [7:0])) print_out (.clk, .rst);
    assign print_out.ready = 'b1;

    gecko_micro #(
        .INST_LATENCY(1),
        .DATA_LATENCY(1),
        .ADDR_SPACE_WIDTH(13)
    ) gecko_micro_inst (
        .clk, .rst,
        .faulted_flag, .finished_flag,
        .supervisor_request, .supervisor_response,
        .print_out
    );

    axi4_ar_intf axi_ar(.clk, .rst);
    axi4_aw_intf axi_aw(.clk, .rst);
    axi4_w_intf axi_w(.clk, .rst);
    axi4_r_intf axi_r(.clk, .rst);
    axi4_b_intf axi_b(.clk, .rst);

    axi4_slave #() axi4_slave_inst (
        .clk, .rst,

        .axi_ar, .axi_aw, .axi_w, .axi_r, .axi_b,
        .mem_request(supervisor_request),
        .mem_response(supervisor_response)
    );

    logic re;
    logic [3:0] we; 
    logic [31:0] data, addr;
    logic id;

    axi4_resp_t temp_resp;
    logic [31:0] temp_data;
    logic temp_last;
    logic temp_id;

    initial begin
        rst_mid = 'b0;
        // supervisor_request.valid = 'b0;
        // supervisor_response.ready = 'b0;

        axi_aw.awvalid = 'b0;
        axi_ar.arvalid = 'b0;
        axi_w.wvalid = 'b0;
        axi_r.rready = 'b0;
        axi_b.bready = 'b0;
        @ (posedge clk);
        while (rst) @ (posedge clk);

        while (!finished_flag && !faulted_flag) @ (posedge clk);
        
        fork
        begin
            axi_ar.send('h0, 
                    AXI4_BURST_INCR, 
                    axi4_cache_t'(4'b0), 
                    'h0, AXI4_LOCK_NORMAL, 
                    axi4_prot_t'(3'b0), 
                    'b0, 'h2, 'b0, 'b0);
            // axi_ar.send('h4, 
            //         AXI4_BURST_INCR, 
            //         axi4_cache_t'(4'b0), 
            //         'h0, AXI4_LOCK_NORMAL, 
            //         axi4_prot_t'(3'b0), 
            //         'b0, 'h2, 'b0, 'b0);
            // axi_ar.send('h8, 
            //         AXI4_BURST_INCR, 
            //         axi4_cache_t'(4'b0), 
            //         'h0, AXI4_LOCK_NORMAL, 
            //         axi4_prot_t'(3'b0), 
            //         'b0, 'h2, 'b0, 'b0);
            // axi_ar.send('hC, 
            //         AXI4_BURST_INCR, 
            //         axi4_cache_t'(4'b0), 
            //         'h0, AXI4_LOCK_NORMAL, 
            //         axi4_prot_t'(3'b0), 
            //         'b0, 'h2, 'b0, 'b0);

            axi_aw.send('h0, 
                    AXI4_BURST_INCR, 
                    axi4_cache_t'(4'b0), 
                    'h0, AXI4_LOCK_NORMAL, 
                    axi4_prot_t'(3'b0), 
                    'b0, 'h2, 'b0, 'b0);

            axi_w.send('h0, 'hf, 'h1);
        end
        begin
            axi_r.recv(temp_data, temp_last, temp_resp, temp_id);
            // axi_r.recv(temp_data, temp_last, temp_resp, temp_id);
            // axi_r.recv(temp_data, temp_last, temp_resp, temp_id);
            // axi_r.recv(temp_data, temp_last, temp_resp, temp_id);
        end
        begin
            axi_b.recv(temp_resp, temp_id);
        end
        join

        // $finish();

        @ (posedge clk);
        @ (posedge clk);
        rst_mid <= 'b1;
        for (int i = 0; i < 20; i++) begin
            @ (posedge clk);
        end
        rst_mid <= 'b0;
        @ (posedge clk);
        @ (posedge clk);
        while (!finished_flag && !faulted_flag) @ (posedge clk);

        fork
        begin
            axi_aw.send('h0, 
                    AXI4_BURST_INCR, 
                    axi4_cache_t'(4'b0), 
                    'h0, AXI4_LOCK_NORMAL, 
                    axi4_prot_t'(3'b0), 
                    'b0, 'h2, 'b0, 'b0);

            axi_w.send(temp_data, 'hf, 'h1);
        end
        begin
            axi_b.recv(temp_resp, temp_id);
        end
        join        

        @ (posedge clk);
        @ (posedge clk);
        rst_mid <= 'b1;
        for (int i = 0; i < 20; i++) begin
            @ (posedge clk);
        end
        rst_mid <= 'b0;
        @ (posedge clk);
        @ (posedge clk);
        while (!finished_flag && !faulted_flag) @ (posedge clk);


        // fork
        // begin
        //     supervisor_request.send('b1, 'b0, 'h400, 'h0, 'b0);
        //     supervisor_request.send('b1, 'b0, 'h404, 'h0, 'b0);
        //     supervisor_request.send('b1, 'b0, 'h000, 'h0, 'b0);
        //     supervisor_request.send('b1, 'b0, 'h000, 'h0, 'b0);

        //     supervisor_request.send('b1, 'b0, 'h000, 'h0, 'b0);
        //     supervisor_request.send('b1, 'b0, 'h000, 'h0, 'b0);
        //     supervisor_request.send('b1, 'b0, 'h000, 'h0, 'b0);
        //     supervisor_request.send('b1, 'b0, 'h000, 'h0, 'b0);
        // end
        // begin
        //     supervisor_response.recv(re, we, data, addr, id);
        //     supervisor_response.recv(re, we, data, addr, id);
        //     supervisor_response.recv(re, we, data, addr, id);
        //     supervisor_response.recv(re, we, data, addr, id);

        //     supervisor_response.recv(re, we, data, addr, id);
        //     supervisor_response.recv(re, we, data, addr, id);
        //     supervisor_response.recv(re, we, data, addr, id);
        //     supervisor_response.recv(re, we, data, addr, id);
        // end
        // join

        // fork
        // begin
        //     for (int i = 0; i < (1<<30); i+=4) begin
        //         supervisor_request.send('b1, 'b0, 'b0, i, 'b0);
        //     end
        // end
        // begin
        //     for (int i = 0; i < (1<<30); i+=4) begin
        //         supervisor_response.recv(re, we, data, addr, id);
        //     end
        // end
        // join

        @ (posedge clk);
        @ (posedge clk);
        $finish();
    end

endmodule
