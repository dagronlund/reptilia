`timescale 1ns/1ps

module gecko_compute_wrapper #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter STROBE_WIDTH = DATA_WIDTH / 8,
    parameter USER_WIDTH = 1,
    parameter ID_WIDTH = 1,

    parameter ADDR_SPACE_WIDTH = 13,
    parameter INST_LATENCY = 2,
    parameter DATA_LATENCY = 2,
    parameter [31:0] START_ADDR = 'h0,
    parameter ENABLE_PERFORMANCE_COUNTERS = 1
)(
    input wire clk, rst,
    
    input wire                    axi_arvalid, 
    output wire                   axi_arready,
    input wire [ADDR_WIDTH-1:0]   axi_araddr,
    input wire [1:0]              axi_arburst,
    input wire [3:0]              axi_arcache,
    input wire [7:0]              axi_arlen,
    input wire                    axi_arlock,
    input wire [2:0]              axi_arprot,
    input wire [3:0]              axi_arqos,
    input wire [2:0]              axi_arsize,
    input wire [USER_WIDTH-1:0]   axi_aruser,
    input wire [ID_WIDTH-1:0]     axi_arid,
    input wire                    axi_awvalid,
    output wire                   axi_awready,
    input wire [ADDR_WIDTH-1:0]   axi_awaddr,
    input wire [1:0]              axi_awburst,
    input wire [3:0]              axi_awcache,
    input wire [7:0]              axi_awlen,
    input wire                    axi_awlock,
    input wire [2:0]              axi_awprot,
    input wire [3:0]              axi_awqos,
    input wire [2:0]              axi_awsize,
    input wire [USER_WIDTH-1:0]   axi_awuser,
    input wire [ID_WIDTH-1:0]     axi_awid,
    input wire                    axi_wvalid,
    output wire                   axi_wready,
    input wire [DATA_WIDTH-1:0]   axi_wdata,
    input wire [STROBE_WIDTH-1:0] axi_wstrb,
    input wire                    axi_wlast,
    output wire                   axi_bvalid,
    input wire                    axi_bready,
    output wire [1:0]             axi_bresp,
    output wire [ID_WIDTH-1:0]    axi_bid,
    output wire                   axi_rvalid,
    input wire                    axi_rready,
    output wire [DATA_WIDTH-1:0]  axi_rdata,
    output wire                   axi_rlast,
    output wire [1:0]             axi_rresp,
    output wire [ID_WIDTH-1:0]    axi_rid,

    output wire faulted_flag, finished_flag
);


    gecko_compute_wrapper_sv #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .STROBE_WIDTH(STROBE_WIDTH),
        .USER_WIDTH(USER_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .ADDR_SPACE_WIDTH(ADDR_SPACE_WIDTH),
        .INST_LATENCY(INST_LATENCY),
        .DATA_LATENCY(DATA_LATENCY),
        .START_ADDR(START_ADDR),
        .ENABLE_PERFORMANCE_COUNTERS(ENABLE_PERFORMANCE_COUNTERS)
    ) gecko_compute_wrapper_sv_inst (
        .clk(clk), .rst(rst),

        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),
        .axi_araddr(axi_araddr),
        .axi_arburst(axi_arburst),
        .axi_arcache(axi_arcache),
        .axi_arlen(axi_arlen),
        .axi_arlock(axi_arlock),
        .axi_arprot(axi_arprot),
        .axi_arqos(axi_arqos),
        .axi_arsize(axi_arsize),
        .axi_aruser(axi_aruser),
        .axi_arid(axi_arid),

        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),
        .axi_awaddr(axi_awaddr),
        .axi_awburst(axi_awburst),
        .axi_awcache(axi_awcache),
        .axi_awlen(axi_awlen),
        .axi_awlock(axi_awlock),
        .axi_awprot(axi_awprot),
        .axi_awqos(axi_awqos),
        .axi_awsize(axi_awsize),
        .axi_awuser(axi_awuser),
        .axi_awid(axi_awid),

        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wlast(axi_wlast),

        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready),
        .axi_bresp(axi_bresp),
        .axi_bid(axi_bid),

        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready),
        .axi_rdata(axi_rdata),
        .axi_rlast(axi_rlast),
        .axi_rresp(axi_rresp),
        .axi_rid(axi_rid),

        .faulted_flag(faulted_flag),
        .finished_flag(finished_flag)
    );

endmodule
