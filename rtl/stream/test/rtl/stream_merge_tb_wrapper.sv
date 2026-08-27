`timescale 1ns/1ps
module stream_merge_tb_wrapper (
    input logic clk, rst,
    input logic o0_valid, input logic [31:0] o0_payload, input logic [1:0] o0_id, output logic o0_ready,
    input logic o1_valid, input logic [31:0] o1_payload, input logic [1:0] o1_id, output logic o1_ready,
    input logic o2_valid, input logic [31:0] o2_payload, input logic [1:0] o2_id, output logic o2_ready,
    input logic o3_valid, input logic [31:0] o3_payload, input logic [1:0] o3_id, output logic o3_ready,
    output logic oo_valid, output logic [31:0] oo_payload, output logic [1:0] oo_id, input logic oo_ready
);
    import std_pkg::*;
    import stream_pkg::*;

    stream_intf #(.T(logic[31:0])) stream_in[4](.clk,.rst), stream_out(.clk,.rst);
    logic [1:0] stream_in_id[4], stream_out_id;
    logic stream_in_last[4], stream_out_last;

    always_comb begin
        stream_in[0].valid = o0_valid;
        stream_in[0].payload = o0_payload;
        stream_in_id[0] = o0_id;
        stream_in_last[0] = 1;
        o0_ready = stream_in[0].ready;

        stream_in[1].valid = o1_valid;
        stream_in[1].payload = o1_payload;
        stream_in_id[1] = o1_id;
        stream_in_last[1] = 1;
        o1_ready = stream_in[1].ready;

        stream_in[2].valid = o2_valid;
        stream_in[2].payload = o2_payload;
        stream_in_id[2] = o2_id;
        stream_in_last[2] = 1;
        o2_ready = stream_in[2].ready;

        stream_in[3].valid = o3_valid;
        stream_in[3].payload = o3_payload;
        stream_in_id[3] = o3_id;
        stream_in_last[3] = 1;
        o3_ready = stream_in[3].ready;

        oo_valid = stream_out.valid;
        oo_payload = stream_out.payload;
        oo_id = stream_out_id;
        stream_out.ready = oo_ready;
    end

    stream_merge #(
        .PORTS(4),
        .ID_WIDTH(2),
        .STREAM_SELECT_MODE(STREAM_SELECT_MODE_ORDERED)
    ) ordered_merge (
        .clk,
        .rst,
        .stream_in,
        .stream_in_id,
        .stream_in_last,
        .stream_out,
        .stream_out_id,
        .stream_out_last
    );
endmodule
