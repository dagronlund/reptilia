`timescale 1ns/1ps

`include "../../lib/axi/axi4.svh"

interface axi4_ar_intf 
    import axi4::*;
#(
    parameter ADDR_WIDTH = 32,
    parameter USER_WIDTH = 1,
    parameter ID_WIDTH = 1
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                  arvalid, arready;
    logic [ADDR_WIDTH-1:0] araddr;
    axi4_burst_t           arburst;
    axi4_cache_t           arcache;
    axi4_len_t             arlen;
    axi4_lock_t            arlock;
    axi4_prot_t            arprot;
    axi4_qos_t             arqos;
    axi4_size_t            arsize;
    logic [USER_WIDTH-1:0] aruser;
    logic [ID_WIDTH-1:0]   arid;

    modport out(
        output arvalid, 
        input arready, 
        output araddr, arburst, arcache, arlen, arlock, arprot, arqos, arsize, aruser, arid
    );

    modport in(
        input arvalid, 
        output arready, 
        input araddr, arburst, arcache, arlen, arlock, arprot, arqos, arsize, aruser, arid
    );

    modport view(
        input arvalid, arready,
        input araddr, arburst, arcache, arlen, arlock, arprot, arqos, arsize, aruser, arid
    );

    task send(
        input logic [ADDR_WIDTH-1:0] araddr_in,
        input axi4_burst_t           arburst_in,
        input axi4_cache_t           arcache_in,
        input axi4_len_t             arlen_in,
        input axi4_lock_t            arlock_in,
        input axi4_prot_t            arprot_in,
        input axi4_qos_t             arqos_in,
        input axi4_size_t            arsize_in,
        input logic [USER_WIDTH-1:0] aruser_in,
        input logic [ID_WIDTH-1:0]   arid_in
    );
        araddr <= araddr_in;
        arburst <= arburst_in;
        arcache <= arcache_in;
        arlen <= arlen_in;
        arlock <= arlock_in;
        arprot <= arprot_in;
        arqos <= arqos_in;
        arsize <= arsize_in;
        aruser <= aruser_in;
        arid <= arid_in;

        arvalid <= 1'b1;
        @ (posedge clk);
        while (!arready) @ (posedge clk);
        arvalid <= 1'b0;
    endtask

    task recv(
        output logic [ADDR_WIDTH-1:0] araddr_out,
        output axi4_burst_t           arburst_out,
        output axi4_cache_t           arcache_out,
        output axi4_len_t             arlen_out,
        output axi4_lock_t            arlock_out,
        output axi4_prot_t            arprot_out,
        output axi4_qos_t             arqos_out,
        output axi4_size_t            arsize_out,
        output logic [USER_WIDTH-1:0] aruser_out,
        output logic [ID_WIDTH-1:0]   arid_out
    );
        arready <= 1'b1;
        @ (posedge clk);
        while (!arvalid) @ (posedge clk);
        arready <= 1'b0;

        araddr_out = araddr;
        arburst_out = arburst;
        arcache_out = arcache;
        arlen_out = arlen;
        arlock_out = arlock;
        arprot_out = arprot;
        arqos_out = arqos;
        arsize_out = arsize;
        aruser_out = aruser;
        arid_out = arid;
    endtask

endinterface

interface axi4_aw_intf 
    import axi4::*;
#(
    parameter ADDR_WIDTH = 32,
    parameter USER_WIDTH = 1,
    parameter ID_WIDTH = 1
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                  awvalid, awready;
    logic [ADDR_WIDTH-1:0] awaddr;
    axi4_burst_t           awburst;
    axi4_cache_t           awcache;
    axi4_len_t             awlen;
    axi4_lock_t            awlock;
    axi4_prot_t            awprot;
    axi4_qos_t             awqos;
    axi4_size_t            awsize;
    logic [USER_WIDTH-1:0] awuser;
    logic [ID_WIDTH-1:0]   awid;

    modport out(
        output awvalid,
        input awready,
        output awaddr, awburst, awcache, awlen, awlock, awprot, awqos, awsize, awuser, awid
    );

    modport in(
        input awvalid,
        output awready,
        input awaddr, awburst, awcache, awlen, awlock, awprot, awqos, awsize, awuser, awid
    );

    modport view(
        input awvalid, awready,
        input awaddr, awburst, awcache, awlen, awlock, awprot, awqos, awsize, awuser, awid
    );

    task send(
        input logic [ADDR_WIDTH-1:0] awaddr_in,
        input axi4_burst_t           awburst_in,
        input axi4_cache_t           awcache_in,
        input axi4_len_t             awlen_in,
        input axi4_lock_t            awlock_in,
        input axi4_prot_t            awprot_in,
        input axi4_qos_t             awqos_in,
        input axi4_size_t            awsize_in,
        input logic [USER_WIDTH-1:0] awuser_in,
        input logic [ID_WIDTH-1:0]   awid_in
    );
        awaddr <= awaddr_in;
        awburst <= awburst_in;
        awcache <= awcache_in;
        awlen <= awlen_in;
        awlock <= awlock_in;
        awprot <= awprot_in;
        awqos <= awqos_in;
        awsize <= awsize_in;
        awuser <= awuser_in;
        awid <= awid_in;

        awvalid <= 1'b1;
        @ (posedge clk);
        while (!awready) @ (posedge clk);
        awvalid <= 1'b0;
    endtask

    task recv(
        output logic [ADDR_WIDTH-1:0] awaddr_out,
        output axi4_burst_t           awburst_out,
        output axi4_cache_t           awcache_out,
        output axi4_len_t             awlen_out,
        output axi4_lock_t            awlock_out,
        output axi4_prot_t            awprot_out,
        output axi4_qos_t             awqos_out,
        output axi4_size_t            awsize_out,
        output logic [USER_WIDTH-1:0] awuser_out,
        output logic [ID_WIDTH-1:0]   awid_out
    );
        awready <= 1'b1;
        @ (posedge clk);
        while (!awvalid) @ (posedge clk);
        awready <= 1'b0;

        awaddr_out = awaddr;
        awburst_out = awburst;
        awcache_out = awcache;
        awlen_out = awlen;
        awlock_out = awlock;
        awprot_out = awprot;
        awqos_out = awqos;
        awsize_out = awsize;
        awuser_out = awuser;
        awid_out = awid;
    endtask

endinterface

interface axi4_b_intf 
    import axi4::*;
#(
    parameter ID_WIDTH = 1
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                bvalid, bready;
    axi4_resp_t          bresp;
    logic [ID_WIDTH-1:0] bid;

    modport out(
        output bvalid,
        input bready,
        output bresp, bid
    );

    modport in(
        input bvalid,
        output bready,
        input bresp, bid
    );

    modport view(
        input bvalid, bready,
        input bresp, bid
    );

    task send(
        input axi4_resp_t            bresp_in,
        input logic [ID_WIDTH-1:0]   bid_in
    );
        bresp <= bresp_in;
        bid <= bid_in;

        bvalid <= 1'b1;
        @ (posedge clk);
        while (!bready) @ (posedge clk);
        bvalid <= 1'b0;
    endtask

    task recv(
        output axi4_resp_t            bresp_out,
        output logic [ID_WIDTH-1:0]   bid_out
    );
        bready <= 1'b1;
        @ (posedge clk);
        while (!bvalid) @ (posedge clk);
        bready <= 1'b0;

        bresp_out = bresp;
        bid_out = bid;
    endtask

endinterface

interface axi4_r_intf 
    import axi4::*;
#(
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH = 1
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                  rvalid, rready;
    logic [DATA_WIDTH-1:0] rdata;
    logic                  rlast;
    axi4_resp_t            rresp;
    logic [ID_WIDTH-1:0]   rid;

    modport out(
        output rvalid,
        input rready,
        output rdata, rlast, rresp, rid
    );

    modport in(
        input rvalid,
        output rready,
        input rdata, rlast, rresp, rid
    );

    modport view(
        input rvalid, rready,
        input rdata, rlast, rresp, rid
    );

    task send(
        input logic [DATA_WIDTH-1:0] rdata_in,
        input logic                  rlast_in,
        input axi4_resp_t            rresp_in,
        input logic [ID_WIDTH-1:0]   rid_in
    );
        rdata <= rdata_in;
        rlast <= rlast_in;
        rresp <= rresp_in;
        rid <= rid_in;

        rvalid <= 1'b1;
        @ (posedge clk);
        while (!rready) @ (posedge clk);
        rvalid <= 1'b0;
    endtask

    task recv(
        output logic [DATA_WIDTH-1:0] rdata_out,
        output logic                  rlast_out,
        output axi4_resp_t            rresp_out,
        output logic [ID_WIDTH-1:0]   rid_out
    );
        rready <= 1'b1;
        @ (posedge clk);
        while (!rvalid) @ (posedge clk);
        rready <= 1'b0;

        rdata_out = rdata;
        rlast_out = rlast;
        rresp_out = rresp;
        rid_out = rid;
    endtask

endinterface

interface axi4_w_intf 
    import axi4::*;
#(
    parameter DATA_WIDTH = 32,
    parameter STROBE_WIDTH = DATA_WIDTH / 8
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                    wvalid, wready;
    logic [DATA_WIDTH-1:0]   wdata;
    logic [STROBE_WIDTH-1:0] wstrb;
    logic                    wlast;

    modport out(
        output wvalid,
        input wready,
        output wdata, wstrb, wlast
    );

    modport in(
        input wvalid,
        output wready,
        input wdata, wstrb, wlast
    );

    modport view(
        input wvalid, wready,
        input wdata, wstrb, wlast
    );

    task send(
        input logic [DATA_WIDTH-1:0]   wdata_in,
        input logic [STROBE_WIDTH-1:0] wstrb_in,
        input logic                    wlast_in
    );
        wdata <= wdata_in;
        wstrb <= wstrb_in;
        wlast <= wlast_in;

        wvalid <= 1'b1;
        @ (posedge clk);
        while (!wready) @ (posedge clk);
        wvalid <= 1'b0;
    endtask

    task recv(
        output logic [DATA_WIDTH-1:0]   wdata_out,
        output logic [STROBE_WIDTH-1:0] wstrb_out,
        output logic                    wlast_out
    );
        wready <= 1'b1;
        @ (posedge clk);
        while (!wvalid) @ (posedge clk);
        wready <= 1'b0;

        wdata_out = wdata;
        wstrb_out = wstrb;
        wlast_out = wlast;
    endtask

endinterface
