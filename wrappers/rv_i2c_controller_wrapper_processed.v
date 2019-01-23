`timescale 1ns/1ps
module rv_i2c_controller_wrapper #(
    parameter DEFAULT_CYCLES = 10'd249,
    parameter DEFAULT_DELAY = 10'd0
)(
    input wire clk, rst,
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
    output wire s_scl_t, s_scl_o,
    input wire s_scl_i,
    output wire s_sda_t, s_sda_o,
    input wire s_sda_i
);
    rv_i2c_controller_wrapper_sv #(
        .DEFAULT_CYCLES(DEFAULT_CYCLES),
        .DEFAULT_DELAY(DEFAULT_DELAY)
    ) rv_i2c_controller_wrapper_sv_inst (
        .clk(clk), .rst(rst),
    .axi_AWVALID(axi_AWVALID), 
    .axi_AWREADY(axi_AWREADY), 
    .axi_AWADDR(axi_AWADDR), 
    .axi_AWPROT(axi_AWPROT), 
    .axi_WVALID(axi_WVALID), 
    .axi_WREADY(axi_WREADY), 
    .axi_WDATA(axi_WDATA), 
    .axi_WSTRB(axi_WSTRB), 
    .axi_BVALID(axi_BVALID), 
    .axi_BREADY(axi_BREADY), 
    .axi_BRESP(axi_BRESP), 
    .axi_ARVALID(axi_ARVALID), 
    .axi_ARREADY(axi_ARREADY), 
    .axi_ARADDR(axi_ARADDR), 
    .axi_ARPROT(axi_ARPROT), 
    .axi_RVALID(axi_RVALID), 
    .axi_RREADY(axi_RREADY), 
    .axi_RDATA(axi_RDATA), 
    .axi_RRESP(axi_RRESP),
        .scl_t(s_scl_t),
        .scl_o(s_scl_o),
        .scl_i(s_scl_i),
        .sda_t(s_sda_t),
        .sda_o(s_sda_o),
        .sda_i(s_sda_i)
    );
endmodule
