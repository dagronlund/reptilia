`timescale 1ns/1ps

`include "../lib/rv_axi4.svh"

interface rv_axi4_ar_intf #(
    parameter ADDR_WIDTH = 32,
    parameter USER_WIDTH = 1,
    parameter ID_WIDTH = 1
)();

    import rv_axi4::*;

    logic                  ARVALID;
    logic                  ARREADY;

    logic [ADDR_WIDTH-1:0] ARADDR;
    rv_axi4_burst           ARBURST;
    rv_axi4_cache           ARCACHE;
    logic [7:0]            ARLEN;
    rv_axi4_lock            ARLOCK;
    rv_axi4_prot            ARPROT;
    logic [3:0]            ARQOS;
    logic [2:0]            ARSIZE;
    logic [USER_WIDTH-1:0] ARUSER;
    logic [ID_WIDTH-1:0]   ARID;

    modport out(
        output ARVALID, 
        input ARREADY, 
        output ARADDR, ARBURST, ARCACHE, ARLEN, ARLOCK, ARPROT, ARQOS, ARSIZE, ARUSER, ARID
    );

    modport in(
        input ARVALID, 
        output ARREADY, 
        input ARADDR, ARBURST, ARCACHE, ARLEN, ARLOCK, ARPROT, ARQOS, ARSIZE, ARUSER, ARID
    );

    modport view(
        input ARVALID, ARREADY,
        input ARADDR, ARBURST, ARCACHE, ARLEN, ARLOCK, ARPROT, ARQOS, ARSIZE, ARUSER, ARID
    );

endinterface

interface rv_axi4_aw_intf #(
    parameter ADDR_WIDTH = 32,
    parameter USER_WIDTH = 1,
    parameter ID_WIDTH = 1
)();

    import rv_axi4::*;

    logic                  AWVALID;
    logic                  AWREADY;

    logic [ADDR_WIDTH-1:0] AWADDR;
    rv_axi4_burst           AWBURST;
    rv_axi4_cache           AWCACHE;
    logic [7:0]            AWLEN;
    rv_axi4_lock            AWLOCK;
    rv_axi4_prot            AWPROT;
    logic [3:0]            AWQOS;
    logic [2:0]            AWSIZE;
    logic [USER_WIDTH-1:0] AWUSER;
    logic [ID_WIDTH-1:0]   AWID;

    modport out(
        output AWVALID,
        input AWREADY,
        output AWADDR, AWBURST, AWCACHE, AWLEN, AWLOCK, AWPROT, AWQOS, AWSIZE, AWUSER, AWID
    );

    modport in(
        input AWVALID,
        output AWREADY,
        input AWADDR, AWBURST, AWCACHE, AWLEN, AWLOCK, AWPROT, AWQOS, AWSIZE, AWUSER, AWID
    );

    modport view(
        input AWVALID, AWREADY,
        input AWADDR, AWBURST, AWCACHE, AWLEN, AWLOCK, AWPROT, AWQOS, AWSIZE, AWUSER, AWID
    );

endinterface

interface rv_axi4_b_intf #(
    parameter ID_WIDTH = 1
)();

    import rv_axi4::*;

    logic                  BVALID;
    logic                  BREADY;

    rv_axi4_resp            BRESP;
    logic [ID_WIDTH-1:0]   BID;

    modport out(
        output BVALID,
        input BREADY,
        output BRESP, BID
    );

    modport in(
        input BVALID,
        output BREADY,
        input BRESP, BID
    );

    modport view(
        input BVALID, BREADY,
        input BRESP, BID
    );

endinterface

interface rv_axi4_r_intf #(
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH = 1
)();

    import rv_axi4::*;

    logic                  RVALID;
    logic                  RREADY;

    logic [DATA_WIDTH-1:0] RDATA;
    logic                  RLAST;
    rv_axi4_resp            RRESP;
    logic [ID_WIDTH-1:0]   RID;

    modport out(
        output RVALID,
        input RREADY,
        output RDATA, RLAST, RRESP, RID
    );

    modport in(
        input RVALID,
        output RREADY,
        input RDATA, RLAST, RRESP, RID
    );

    modport view(
        input RVALID, RREADY,
        input RDATA, RLAST, RRESP, RID
    );

endinterface

interface rv_axi4_w_intf #(
    parameter DATA_WIDTH = 32,
    parameter STROBE_WIDTH = DATA_WIDTH / 8
)();

    import rv_axi4::*;

    logic                    WVALID;
    logic                    WREADY;

    logic [DATA_WIDTH-1:0]   WDATA;
    logic [STROBE_WIDTH-1:0] WSTRB;
    logic                    WLAST;

    modport out(
        output WVALID,
        input WREADY,
        output WDATA, WSTRB, WLAST
    );

    modport in(
        input WVALID,
        output WREADY,
        input WDATA, WSTRB, WLAST
    );

    modport view(
        input WVALID, WREADY,
        input WDATA, WSTRB, WLAST
    );

endinterface