`timescale 1ns/1ps
module stream_split_merge_tb_wrapper (
    input logic clk, rst,
    input logic rr0_valid, input logic [31:0] rr0_payload, input logic rr0_last, output logic rr0_ready,
    input logic rr1_valid, input logic [31:0] rr1_payload, input logic rr1_last, output logic rr1_ready,
    output logic rr0o_valid, output logic [31:0] rr0o_payload, output logic rr0o_last, input logic rr0o_ready,
    output logic rr1o_valid, output logic [31:0] rr1o_payload, output logic rr1o_last, input logic rr1o_ready,
    output logic rr_mid_valid, output logic rr_mid_ready, output logic rr_mid_id,
    output logic [31:0] rr_mid_payload, output logic rr_mid_last
);
    import std_pkg::*; import stream_pkg::*;
    stream_intf #(.T(logic[31:0])) ri[2](.clk,.rst), mid(.clk,.rst), rout[2](.clk,.rst);
    logic rid[2], rlast[2], mid_id, mid_last, rout_id[2], rout_last[2];
    always_comb begin
        ri[0].valid=rr0_valid; ri[0].payload=rr0_payload; rid[0]=0; rlast[0]=rr0_last; rr0_ready=ri[0].ready;
        ri[1].valid=rr1_valid; ri[1].payload=rr1_payload; rid[1]=0; rlast[1]=rr1_last; rr1_ready=ri[1].ready;
        rr0o_valid=rout[0].valid; rr0o_payload=rout[0].payload; rr0o_last=rout_last[0]; rout[0].ready=rr0o_ready;
        rr1o_valid=rout[1].valid; rr1o_payload=rout[1].payload; rr1o_last=rout_last[1]; rout[1].ready=rr1o_ready;
        rr_mid_valid=mid.valid; rr_mid_ready=mid.ready; rr_mid_id=mid_id; rr_mid_payload=mid.payload; rr_mid_last=mid_last;
    end
    stream_merge #(.PORTS(2),.USE_LAST(1)) rr_merge(.clk,.rst,.stream_in(ri),.stream_in_id(rid),.stream_in_last(rlast),.stream_out(mid),.stream_out_id(mid_id),.stream_out_last(mid_last));
    stream_split #(.PORTS(2),.USE_LAST(1)) rr_split(.clk,.rst,.stream_in(mid),.stream_in_id(mid_id),.stream_in_last(mid_last),.stream_out(rout),.stream_out_id(rout_id),.stream_out_last(rout_last));
endmodule
