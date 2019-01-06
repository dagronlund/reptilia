`ifndef __RV_AXI__
`define __RV_AXI__

package rv_axi;

    typedef enum bit [1:0] {
        RV_AXI_RESP_OKAY = 2'b00, 
        RV_AXI_RESP_EXOKAY = 2'b01, 
        RV_AXI_RESP_SLVERR = 2'b10, 
        RV_AXI_RESP_DECERR = 2'b11
    } rv_axi_resp;

    typedef enum bit [1:0] {
        RV_AXI_BURST_FIXED = 2'b00,
        RV_AXI_BURST_INCR = 2'b01,
        RV_AXI_BURST_WRAP = 2'b10,
        RV_AXI_BURST_UNDEF = 2'b11
    } rv_axi_burst;

    typedef struct packed {
        bit other_allocate;
        bit allocate;
        bit modifiable;
        bit bufferable;
    } rv_axi_cache;

    typedef enum bit {
        RV_AXI_LOCK_NORMAL = 1'b0,
        RV_AXI_LOCK_EXCLUSIVE = 1'b1
    } rv_axi_lock;

    typedef enum bit {
        RV_AXI_UNPRIVILEDGED_ACCESS = 1'b0,
        RV_AXI_PRIVILEDGED_ACCESS = 1'b1
    } rv_axi_privilege;

    typedef enum bit {
        RV_AXI_SECURE_ACCESS = 1'b0,
        RV_AXI_NONSECURE_ACCESS = 1'b1
    } rv_axi_security;

    typedef enum bit {
        RV_AXI_DATA_ACCESS = 1'b0,
        RV_AXI_INSTRUCTION_ACCESS = 1'b1
    } rv_axi_access;

    typedef struct packed {
        rv_axi_access access;
        rv_axi_security security;
        rv_axi_privilege privilege;
    } rv_axi_prot;

endpackage

interface rv_axi_addr_read_intf #(
    parameter ADDR_WIDTH = 32,
    parameter USER_WIDTH = 1,
    parameter ID_WIDTH = 1
)();

    import rv_axi::*;

    logic                  ARVALID;
    logic                  ARREADY;

    logic [ADDR_WIDTH-1:0] ARADDR;
    rv_axi_burst           ARBURST;
    rv_axi_cache           ARCACHE;
    logic [7:0]            ARLEN;
    rv_axi_lock            ARLOCK;
    rv_axi_prot            ARPROT;
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

interface rv_axi_addr_write_intf #(
    parameter ADDR_WIDTH = 32,
    parameter USER_WIDTH = 1,
    parameter ID_WIDTH = 1
)();

    import rv_axi::*;

    logic                  AWVALID;
    logic                  AWREADY;

    logic [ADDR_WIDTH-1:0] AWADDR;
    rv_axi_burst           AWBURST;
    rv_axi_cache           AWCACHE;
    logic [7:0]            AWLEN;
    rv_axi_lock            AWLOCK;
    rv_axi_prot            AWPROT;
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

interface rv_axi_write_resp_intf #(
    parameter ID_WIDTH = 1
)();

    logic                  BVALID;
    logic                  BREADY;

    rv_axi_resp            BRESP;
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

interface rv_axi_read_data_intf #(
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH = 1
)();

    logic                  RVALID;
    logic                  RREADY;

    logic [DATA_WIDTH-1:0] RDATA;
    logic                  RLAST;
    rv_axi_resp            RRESP;
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

interface rv_axi_write_data_intf #(
    parameter DATA_WIDTH = 32,
    parameter STROBE_WIDTH = DATA_WIDTH / 8
)();

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

`endif
