`timescale 1ns/1ps

`include "../lib/rv_axi4_lite.svh"

interface rv_axi4_lite_ar_intf #(
    parameter ADDR_WIDTH = 32
)(
    input logic clk = 'b0, rst = 'b0
);

    import rv_axi4_lite::*;

    logic                  ARVALID;
    logic                  ARREADY;

    logic [ADDR_WIDTH-1:0] ARADDR;
    rv_axi4_lite_prot      ARPROT;

    modport out(
        output ARVALID, 
        input ARREADY, 
        output ARADDR, ARPROT
    );

    modport in(
        input ARVALID, 
        output ARREADY, 
        input ARADDR, ARPROT
    );

    modport view(
        input ARVALID, ARREADY,
        input ARADDR, ARPROT
    );

    task send(input logic [ADDR_WIDTH-1:0] addr, input rv_axi4_lite_prot prot);
        ARADDR <= addr;
        ARPROT <= prot; 
        ARVALID <= 1'b1; 
        @ (posedge clk); 
        while (!ARREADY) @ (posedge clk); 
        ARVALID <= 1'b0;
    endtask

    task recv(output logic [ADDR_WIDTH-1:0] addr, output rv_axi4_lite_prot prot);
        ARREADY <= 1'b1; 
        @ (posedge clk); 
        while (!ARVALID) @ (posedge clk); 
        ARREADY <= 1'b0; 
        addr = ARADDR;
        prot = ARPROT;
    endtask

endinterface

interface rv_axi4_lite_aw_intf #(
    parameter ADDR_WIDTH = 32
)(
    input logic clk = 'b0, rst = 'b0
);

    import rv_axi4_lite::*;

    logic                  AWVALID;
    logic                  AWREADY;

    logic [ADDR_WIDTH-1:0] AWADDR;
    rv_axi4_lite_prot      AWPROT;

    modport out(
        output AWVALID,
        input AWREADY,
        output AWADDR, AWPROT
    );

    modport in(
        input AWVALID,
        output AWREADY,
        input AWADDR, AWPROT
    );

    modport view(
        input AWVALID, AWREADY,
        input AWADDR, AWPROT
    );

    task send(input logic [ADDR_WIDTH-1:0] addr, input rv_axi4_lite_prot prot);
        AWADDR <= addr;
        AWPROT <= prot; 
        AWVALID <= 1'b1; 
        @ (posedge clk); 
        while (!AWREADY) @ (posedge clk); 
        AWVALID <= 1'b0;
    endtask

    task recv(output logic [ADDR_WIDTH-1:0] addr, output rv_axi4_lite_prot prot);
        AWREADY <= 1'b1; 
        @ (posedge clk); 
        while (!AWVALID) @ (posedge clk); 
        AWREADY <= 1'b0; 
        addr = AWADDR;
        prot = AWPROT;
    endtask

endinterface

interface rv_axi4_lite_b_intf #(
)(
    input logic clk = 'b0, rst = 'b0
);

    import rv_axi4_lite::*;

    logic             BVALID;
    logic             BREADY;

    rv_axi4_lite_resp BRESP;

    modport out(
        output BVALID,
        input BREADY,
        output BRESP
    );

    modport in(
        input BVALID,
        output BREADY,
        input BRESP
    );

    modport view(
        input BVALID, BREADY,
        input BRESP
    );

    task send(input rv_axi4_lite_resp resp);
        BRESP <= resp; 
        BVALID <= 1'b1; 
        @ (posedge clk); 
        while (!BREADY) @ (posedge clk); 
        BVALID <= 1'b0;
    endtask

    task recv(output rv_axi4_lite_resp resp);
        BREADY <= 1'b1; 
        @ (posedge clk); 
        while (!BVALID) @ (posedge clk); 
        BREADY <= 1'b0; 
        resp = BRESP;
    endtask

endinterface

interface rv_axi4_lite_r_intf #(
    parameter DATA_WIDTH = 32
)(
    input logic clk = 'b0, rst = 'b0
);

    import rv_axi4_lite::*;

    logic                  RVALID;
    logic                  RREADY;

    logic [DATA_WIDTH-1:0] RDATA;
    rv_axi4_lite_resp      RRESP;

    modport out(
        output RVALID,
        input RREADY,
        output RDATA, RRESP
    );

    modport in(
        input RVALID,
        output RREADY,
        input RDATA, RRESP
    );

    modport view(
        input RVALID, RREADY,
        input RDATA, RRESP
    );

    task send(input logic [DATA_WIDTH-1:0] data, input rv_axi4_lite_resp resp);
        RDATA <= data;
        RRESP <= resp; 
        RVALID <= 1'b1; 
        @ (posedge clk); 
        while (!RREADY) @ (posedge clk); 
        RVALID <= 1'b0;
    endtask

    task recv(output logic [DATA_WIDTH-1:0] data, output rv_axi4_lite_resp resp);
        RREADY <= 1'b1; 
        @ (posedge clk); 
        while (!RVALID) @ (posedge clk); 
        RREADY <= 1'b0; 
        data = RDATA;
        resp = RRESP;
    endtask

endinterface

interface rv_axi4_lite_w_intf #(
    parameter DATA_WIDTH = 32,
    parameter STROBE_WIDTH = DATA_WIDTH / 8
)(
    input logic clk = 'b0, rst = 'b0
);

    import rv_axi4_lite::*;

    logic                    WVALID;
    logic                    WREADY;

    logic [DATA_WIDTH-1:0]   WDATA;
    logic [STROBE_WIDTH-1:0] WSTRB;

    modport out(
        output WVALID,
        input WREADY,
        output WDATA, WSTRB
    );

    modport in(
        input WVALID,
        output WREADY,
        input WDATA, WSTRB
    );

    modport view(
        input WVALID, WREADY,
        input WDATA, WSTRB
    );

    task send(input logic [DATA_WIDTH-1:0] data, input logic [STROBE_WIDTH-1:0] strb);
        WDATA <= data;
        WSTRB <= strb; 
        WVALID <= 1'b1; 
        @ (posedge clk); 
        while (!WREADY) @ (posedge clk); 
        WVALID <= 1'b0;
    endtask

    task recv(output logic [DATA_WIDTH-1:0] data, output logic [STROBE_WIDTH-1:0] strb);
        WREADY <= 1'b1; 
        @ (posedge clk); 
        while (!WVALID) @ (posedge clk); 
        WREADY <= 1'b0; 
        data = WDATA;
        strb = WSTRB;
    endtask

endinterface
