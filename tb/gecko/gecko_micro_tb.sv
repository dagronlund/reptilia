`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

module gecko_micro_tb
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#()();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    logic faulted_flag, finished_flag;

    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) supervisor_request (.clk, .rst);
    std_mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) supervisor_response (.clk, .rst);

    std_stream_intf #(.T(logic [7:0])) print_out (.clk, .rst);
    assign print_out.ready = 'b1;

    gecko_micro #(
        .INST_LATENCY(1),
        .DATA_LATENCY(1)
    ) gecko_micro_inst (
        .clk, .rst,
        .faulted_flag, .finished_flag,
        .supervisor_request, .supervisor_response,
        .print_out
    );

    logic re;
    logic [3:0] we; 
    logic [31:0] data, addr;
    logic id;

    initial begin
        supervisor_request.valid = 'b0;
        supervisor_response.ready = 'b0;
        while (rst) @ (posedge clk);

        while (!finished_flag) @ (posedge clk);
        
        fork
        begin
            supervisor_request.send('b1, 'b0, 'h400, 'h0, 'b0);
            supervisor_request.send('b1, 'b0, 'h404, 'h0, 'b0);
            supervisor_request.send('b1, 'b0, 'h000, 'h0, 'b0);
            supervisor_request.send('b1, 'b0, 'h000, 'h0, 'b0);

            supervisor_request.send('b1, 'b0, 'h000, 'h0, 'b0);
            supervisor_request.send('b1, 'b0, 'h000, 'h0, 'b0);
            supervisor_request.send('b1, 'b0, 'h000, 'h0, 'b0);
            supervisor_request.send('b1, 'b0, 'h000, 'h0, 'b0);
        end
        begin
            supervisor_response.recv(re, we, data, addr, id);
            supervisor_response.recv(re, we, data, addr, id);
            supervisor_response.recv(re, we, data, addr, id);
            supervisor_response.recv(re, we, data, addr, id);

            supervisor_response.recv(re, we, data, addr, id);
            supervisor_response.recv(re, we, data, addr, id);
            supervisor_response.recv(re, we, data, addr, id);
            supervisor_response.recv(re, we, data, addr, id);
        end
        join

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

        $finish();
    end

endmodule
