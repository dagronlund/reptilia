`timescale 1ns/1ps
module rv_i2c_controller_wrapper_sv #(
    parameter DEFAULT_CYCLES = 10'd249,
    parameter DEFAULT_DELAY = 10'd0
)(
    input logic clk, rst,
    input wire axi_AWVALID, output wire axi_AWREADY, 
    input wire [32-1:0] axi_AWADDR, 
    input wire [2:0]            axi_AWPROT, 
    input wire axi_WVALID, output wire axi_WREADY, 
    input wire [32-1:0]     axi_WDATA, 
    input wire [(32/8)-1:0] axi_WSTRB, 
    output wire axi_BVALID, input wire axi_BREADY, 
    output wire [1:0]          axi_BRESP, 
    input wire axi_ARVALID, output wire axi_ARREADY, 
    input wire [32-1:0] axi_ARADDR, 
    input wire [2:0]            axi_ARPROT, 
    output wire axi_RVALID, input wire axi_RREADY, 
    output wire [32-1:0] axi_RDATA, 
    output wire [1:0]            axi_RRESP,
    output logic scl_t, scl_o,
    input logic scl_i,
    output logic sda_t, sda_o,
    input logic sda_i
);
    rv_axi4_lite_aw_intf #(.ADDR_WIDTH(32)) axi_aw (); 
    rv_axi4_lite_w_intf #(.DATA_WIDTH(32))  axi_w (); 
    rv_axi4_lite_b_intf #()                 axi_b (); 
    rv_axi4_lite_ar_intf #(.ADDR_WIDTH(32)) axi_ar (); 
    rv_axi4_lite_r_intf #(.DATA_WIDTH(32))  axi_r ();
    assign axi_aw.AWVALID = axi_AWVALID; 
    assign axi_AWREADY  = axi_aw.AWREADY; 
    assign axi_aw.AWADDR  = axi_AWADDR; 
    assign axi_aw.AWPROT  = rv_axi4_lite::rv_axi4_lite_prot'(axi_AWPROT); 
    assign axi_w.WVALID = axi_WVALID; 
    assign axi_WREADY  = axi_w.WREADY; 
    assign axi_w.WDATA  = axi_WDATA; 
    assign axi_w.WSTRB  = axi_WSTRB; 
    assign axi_BVALID = axi_b.BVALID; 
    assign axi_b.BREADY  = axi_BREADY; 
    assign axi_BRESP  = rv_axi4_lite::rv_axi4_lite_resp'(axi_b.BRESP); 
    assign axi_ar.ARVALID = axi_ARVALID; 
    assign axi_ARREADY  = axi_ar.ARREADY; 
    assign axi_ar.ARADDR  = axi_ARADDR; 
    assign axi_ar.ARPROT  = rv_axi4_lite::rv_axi4_lite_prot'(axi_ARPROT); 
    assign axi_RVALID = axi_r.RVALID; 
    assign axi_r.RREADY  = axi_RREADY; 
    assign axi_RDATA  = axi_r.RDATA; 
    assign axi_RRESP  = rv_axi4_lite::rv_axi4_lite_resp'(axi_r.RRESP);
    rv_io_intf scl();
    rv_io_intf sda();
    assign scl_o = scl.o;
    assign scl_t = scl.t;
    assign scl.i = scl_i;
    assign sda_o = sda.o;
    assign sda_t = sda.t;
    assign sda.i = sda_i;
    rv_i2c_controller #(
        .DEFAULT_CYCLES(DEFAULT_CYCLES),
        .DEFAULT_DELAY(DEFAULT_DELAY)
    ) rv_i2c_controller_inst (.*);
endmodule
