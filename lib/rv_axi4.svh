`ifndef __RV_AXI4__
`define __RV_AXI4__

// TODO: Add AXI4 Stream

package rv_axi4;

    typedef enum logic [1:0] {
        RV_AXI4_RESP_OKAY = 2'b00, 
        RV_AXI4_RESP_EXOKAY = 2'b01, 
        RV_AXI4_RESP_SLVERR = 2'b10, 
        RV_AXI4_RESP_DECERR = 2'b11
    } rv_axi4_resp;

    typedef enum logic [1:0] {
        RV_AXI4_BURST_FIXED = 2'b00,
        RV_AXI4_BURST_INCR = 2'b01,
        RV_AXI4_BURST_WRAP = 2'b10,
        RV_AXI4_BURST_UNDEF = 2'b11
    } rv_axi4_burst;

    typedef enum logic {
        RV_AXI4_NON_BUFFERABLE = 1'b0,
        RV_AXI4_BUFFERABLE = 1'b1
    } rv_axi4_bufferable;

    typedef enum logic {
        RV_AXI4_NON_MODIFIABLE = 1'b0,
        RV_AXI4_MODIFIABLE = 1'b1
    } rv_axi4_modifiable;

    typedef enum logic {
        RV_AXI4_UNALLOCATED = 1'b0,
        RV_AXI4_ALLOCATED = 1'b1
    } rv_axi4_allocation;

    typedef struct packed {
        rv_axi4_allocation allocation;
        rv_axi4_allocation other_allocation;
        rv_axi4_modifiable cacheable;
        rv_axi4_bufferable bufferable;
    } rv_axi4_cache;

    typedef enum logic {
        RV_AXI4_LOCK_NORMAL = 1'b0,
        RV_AXI4_LOCK_EXCLUSIVE = 1'b1
    } rv_axi4_lock;

    typedef enum logic {
        RV_AXI4_UNPRIVILEDGED_ACCESS = 1'b0,
        RV_AXI4_PRIVILEDGED_ACCESS = 1'b1
    } rv_axi4_privilege;

    typedef enum logic {
        RV_AXI4_SECURE_ACCESS = 1'b0,
        RV_AXI4_NONSECURE_ACCESS = 1'b1
    } rv_axi4_security;

    typedef enum logic {
        RV_AXI4_DATA_ACCESS = 1'b0,
        RV_AXI4_INSTRUCTION_ACCESS = 1'b1
    } rv_axi4_access;

    typedef struct packed {
        rv_axi4_access access;
        rv_axi4_security security;
        rv_axi4_privilege privilege;
    } rv_axi4_prot;

endpackage

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

`endif
