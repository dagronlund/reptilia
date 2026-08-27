`timescale 1ns/1ps
module mem_split_merge_tb_wrapper (
    input logic clk, rst,
    input logic i0_valid, output logic i0_ready, input logic i0_read, input logic [3:0] i0_write,
    input logic [9:0] i0_addr, input logic [31:0] i0_data, input logic i0_id, input logic i0_last, input logic i0_meta,
    input logic i1_valid, output logic i1_ready, input logic i1_read, input logic [3:0] i1_write,
    input logic [9:0] i1_addr, input logic [31:0] i1_data, input logic i1_id, input logic i1_last, input logic i1_meta,
    output logic o0_valid, input logic o0_ready, output logic o0_read, output logic [3:0] o0_write,
    output logic [9:0] o0_addr, output logic [31:0] o0_data, output logic o0_id, output logic o0_last, output logic o0_meta,
    output logic o1_valid, input logic o1_ready, output logic o1_read, output logic [3:0] o1_write,
    output logic [9:0] o1_addr, output logic [31:0] o1_data, output logic o1_id, output logic o1_last, output logic o1_meta,
    output logic mid_valid, output logic mid_ready, output logic mid_id, output logic mid_last
);
    import std_pkg::*; import stream_pkg::*;
    mem_intf #(.DATA_WIDTH(32),.ADDR_WIDTH(10),.ID_WIDTH(1)) mi[2](.clk,.rst);
    mem_intf #(.DATA_WIDTH(32),.ADDR_WIDTH(10),.ID_WIDTH(2)) mm(.clk,.rst);
    mem_intf #(.DATA_WIDTH(32),.ADDR_WIDTH(10),.ID_WIDTH(1)) mo[2](.clk,.rst);
    logic meta_i[2], meta_m, meta_o[2];
    always_comb begin
        mi[0].valid=i0_valid; i0_ready=mi[0].ready; mi[0].read_enable=i0_read; mi[0].write_enable=i0_write;
        mi[0].addr=i0_addr; mi[0].data=i0_data; mi[0].id=i0_id; mi[0].last=i0_last; meta_i[0]=i0_meta;
        mi[1].valid=i1_valid; i1_ready=mi[1].ready; mi[1].read_enable=i1_read; mi[1].write_enable=i1_write;
        mi[1].addr=i1_addr; mi[1].data=i1_data; mi[1].id=i1_id; mi[1].last=i1_last; meta_i[1]=i1_meta;
        o0_valid=mo[0].valid; mo[0].ready=o0_ready; o0_read=mo[0].read_enable; o0_write=mo[0].write_enable;
        o0_addr=mo[0].addr; o0_data=mo[0].data; o0_id=mo[0].id; o0_last=mo[0].last; o0_meta=meta_o[0];
        o1_valid=mo[1].valid; mo[1].ready=o1_ready; o1_read=mo[1].read_enable; o1_write=mo[1].write_enable;
        o1_addr=mo[1].addr; o1_data=mo[1].data; o1_id=mo[1].id; o1_last=mo[1].last; o1_meta=meta_o[1];
        mid_valid=mm.valid; mid_ready=mm.ready; mid_id=mm.id[1]; mid_last=mm.last;
    end
    mem_merge #(.PORTS(2),.META_WIDTH(1),.USE_LAST(1)) merge_inst(
        .clk,.rst,.mem_in(mi),.mem_in_meta(meta_i),.mem_out(mm),.mem_out_meta(meta_m));
    mem_split #(.PORTS(2),.META_WIDTH(1),.USE_LAST(1)) split_inst(
        .clk,.rst,.mem_in(mm),.mem_in_meta(meta_m),.mem_out(mo),.mem_out_meta(meta_o));
endmodule
