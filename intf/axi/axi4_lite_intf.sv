`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/axi/axi4_lite.svh"

`else 

`include "axi4_lite.svh"

`endif

interface axi4_lite_ar_intf 
    import axi4_lite::*;
#(
    parameter ADDR_WIDTH = 32
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                  arvalid, arready;
    logic [ADDR_WIDTH-1:0] araddr;
    axi4_lite_prot_t    arprot;

    modport out(
        output arvalid, 
        input arready, 
        output araddr, arprot
    );

    modport in(
        input arvalid, 
        output arready, 
        input araddr, arprot
    );

    modport view(
        input arvalid, arready,
        input araddr, arprot
    );

    task send(
        input logic [ADDR_WIDTH-1:0] araddr_in, 
        input axi4_lite_prot_t arprot_in
    );
        araddr <= araddr_in;
        arprot <= arprot_in;
        
        arvalid <= 1'b1; 
        @ (posedge clk); 
        while (!arready) @ (posedge clk); 
        arvalid <= 1'b0;
    endtask

    task recv(
        output logic [ADDR_WIDTH-1:0] araddr_out, 
        output axi4_lite_prot_t arprot_out
    );
        arready <= 1'b1; 
        @ (posedge clk); 
        while (!arvalid) @ (posedge clk); 
        arready <= 1'b0;

        araddr_out = araddr;
        arprot_out = arprot;
    endtask

endinterface

interface axi4_lite_aw_intf 
    import axi4_lite::*;
#(
    parameter ADDR_WIDTH = 32
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                  awvalid, awready;
    logic [ADDR_WIDTH-1:0] awaddr;
    axi4_lite_prot_t    awprot;

    modport out(
        output awvalid,
        input awready,
        output awaddr, awprot
    );

    modport in(
        input awvalid,
        output awready,
        input awaddr, awprot
    );

    modport view(
        input awvalid, awready,
        input awaddr, awprot
    );

    task send(
        input logic [ADDR_WIDTH-1:0] awaddr_in, 
        input axi4_lite_prot_t awprot_in
    );
        awaddr <= awaddr_in;
        awprot <= awprot_in; 
        
        awvalid <= 1'b1; 
        @ (posedge clk); 
        while (!awready) @ (posedge clk); 
        awvalid <= 1'b0;
    endtask

    task recv(
        output logic [ADDR_WIDTH-1:0] awaddr_out,
        output axi4_lite_prot_t awprot_out
    );
        awready <= 1'b1; 
        @ (posedge clk); 
        while (!awvalid) @ (posedge clk); 
        awready <= 1'b0;

        awaddr_out = awaddr;
        awprot_out = awprot;
    endtask

endinterface

interface axi4_lite_b_intf 
    import axi4_lite::*;
#()(
    input logic clk = 'b0, rst = 'b0
);    

    logic               bvalid, bready;
    axi4_lite_resp_t bresp;

    modport out(
        output bvalid,
        input bready,
        output bresp
    );

    modport in(
        input bvalid,
        output bready,
        input bresp
    );

    modport view(
        input bvalid, bready,
        input bresp
    );

    task send(
        input axi4_lite_resp_t bresp_in
    );
        bresp <= bresp_in;

        bvalid <= 1'b1; 
        @ (posedge clk); 
        while (!bready) @ (posedge clk); 
        bvalid <= 1'b0;
    endtask

    task recv(
        output axi4_lite_resp_t bresp_out
    );
        bready <= 1'b1; 
        @ (posedge clk); 
        while (!bvalid) @ (posedge clk); 
        bready <= 1'b0;

        bresp_out = bresp;
    endtask

endinterface

interface axi4_lite_r_intf 
    import axi4_lite::*;
#(
    parameter DATA_WIDTH = 32
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                  rvalid, rready;
    logic [DATA_WIDTH-1:0] rdata;
    axi4_lite_resp_t    rresp;

    modport out(
        output rvalid,
        input rready,
        output rdata, rresp
    );

    modport in(
        input rvalid,
        output rready,
        input rdata, rresp
    );

    modport view(
        input rvalid, rready,
        input rdata, rresp
    );

    task send(
        input logic [DATA_WIDTH-1:0] rdata_in, 
        input axi4_lite_resp_t rresp_in
    );
        rdata <= rdata_in;
        rresp <= rresp_in; 

        rvalid <= 1'b1; 
        @ (posedge clk); 
        while (!rready) @ (posedge clk); 
        rvalid <= 1'b0;
    endtask

    task recv(
        output logic [DATA_WIDTH-1:0] rdata_out, 
        output axi4_lite_resp_t rresp_out
    );
        rready <= 1'b1; 
        @ (posedge clk); 
        while (!rvalid) @ (posedge clk); 
        rready <= 1'b0; 

        rdata_out = rdata;
        rresp_out = rresp;
    endtask

endinterface

interface axi4_lite_w_intf 
    import axi4_lite::*;
#(
    parameter DATA_WIDTH = 32,
    parameter STROBE_WIDTH = DATA_WIDTH / 8
)(
    input logic clk = 'b0, rst = 'b0
);

    logic                    wvalid, wready;
    logic [DATA_WIDTH-1:0]   wdata;
    logic [STROBE_WIDTH-1:0] wstrb;

    modport out(
        output wvalid,
        input wready,
        output wdata, wstrb
    );

    modport in(
        input wvalid,
        output wready,
        input wdata, wstrb
    );

    modport view(
        input wvalid, wready,
        input wdata, wstrb
    );

    task send(
        input logic [DATA_WIDTH-1:0] wdata_in, 
        input logic [STROBE_WIDTH-1:0] wstrb_in
    );
        wdata <= wdata_in;
        wstrb <= wstrb_in; 
        
        wvalid <= 1'b1; 
        @ (posedge clk); 
        while (!wready) @ (posedge clk); 
        wvalid <= 1'b0;
    endtask

    task recv(
        output logic [DATA_WIDTH-1:0] wdata_out,
        output logic [STROBE_WIDTH-1:0] wstrb_out
    );
        wready <= 1'b1; 
        @ (posedge clk); 
        while (!wvalid) @ (posedge clk); 
        wready <= 1'b0; 
        
        wdata_out = wdata;
        wstrb_out = wstrb;
    endtask

endinterface
