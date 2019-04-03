`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

module stream_tb
#()();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    localparam int PORTS = 2;

    std_stream_intf #(.T(int)) stream_in0 (.clk, .rst);
    std_stream_intf #(.T(int)) stream_in1 (.clk, .rst);

    logic stream_mid_id;
    std_stream_intf #(.T(int)) stream_mid (.clk, .rst);

    std_stream_intf #(.T(int)) stream_out0 (.clk, .rst);
    std_stream_intf #(.T(int)) stream_out1 (.clk, .rst);

    stream_merge #(
        .PORTS(PORTS)
    ) stream_merge_inst (
        .clk, .rst,
        .stream_in('{stream_in0, stream_in1}),
        .stream_out(stream_mid),
        .stream_out_id(stream_mid_id)
    );

    stream_split #(
        .PORTS(PORTS)
    ) stream_split_inst(
        .clk, .rst,

        .stream_in(stream_mid),
        .stream_in_id(stream_mid_id),

        .stream_out('{stream_out0, stream_out1})
    );

    int i_out;

    initial begin
        stream_in0.valid = 'b0;
        stream_in1.valid = 'b0;
        stream_out0.ready = 'b0;
        stream_out1.ready = 'b0;
        while (rst) @ (posedge clk);

        fork
        begin
            stream_in0.send(1);
            stream_in0.send(2);
        end
        begin
            stream_in1.send(3);
            stream_in1.send(4);
        end
        begin
            stream_out0.recv(i_out);
            stream_out1.recv(i_out);
            stream_out0.recv(i_out);
            stream_out1.recv(i_out);
        end
        begin
        end
        join

    end

endmodule
