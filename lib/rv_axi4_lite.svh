`ifndef __RV_AXI4_LITE__
`define __RV_AXI4_LITE__

package rv_axi4_lite;

    typedef enum logic [1:0] {
        RV_AXI4_RESP_OKAY = 2'b00, 
        RV_AXI4_RESP_EXOKAY = 2'b01, 
        RV_AXI4_RESP_SLVERR = 2'b10, 
        RV_AXI4_RESP_DECERR = 2'b11
    } rv_axi4_lite_resp;

    typedef enum logic {
        RV_AXI4_UNPRIVILEDGED_ACCESS = 1'b0,
        RV_AXI4_PRIVILEDGED_ACCESS = 1'b1
    } rv_axi4_lite_privilege;

    typedef enum logic {
        RV_AXI4_SECURE_ACCESS = 1'b0,
        RV_AXI4_NONSECURE_ACCESS = 1'b1
    } rv_axi4_lite_security;

    typedef enum logic {
        RV_AXI4_DATA_ACCESS = 1'b0,
        RV_AXI4_INSTRUCTION_ACCESS = 1'b1
    } rv_axi4_lite_access;

    typedef struct packed {
        rv_axi4_lite_access access;
        rv_axi4_lite_security security;
        rv_axi4_lite_privilege privilege;
    } rv_axi4_lite_prot;

endpackage

interface rv_axi4_lite_ar_intf #(
    parameter ADDR_WIDTH = 32,
    parameter USER_WIDTH = 1
)();

    import rv_axi4_lite::*;

    logic                  ARVALID;
    logic                  ARREADY;

    logic [ADDR_WIDTH-1:0] ARADDR;
    rv_axi4_lite_prot            ARPROT;

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

endinterface

interface rv_axi4_lite_aw_intf #(
    parameter ADDR_WIDTH = 32,
    parameter USER_WIDTH = 1
)();

    import rv_axi4_lite::*;

    logic                  AWVALID;
    logic                  AWREADY;

    logic [ADDR_WIDTH-1:0] AWADDR;
    rv_axi4_lite_prot            AWPROT;

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

endinterface

interface rv_axi4_lite_b_intf #(
)();

    import rv_axi4_lite::*;

    logic                  BVALID;
    logic                  BREADY;

    rv_axi4_lite_resp            BRESP;

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

endinterface

interface rv_axi4_lite_r_intf #(
    parameter DATA_WIDTH = 32
)();

    import rv_axi4_lite::*;

    logic                  RVALID;
    logic                  RREADY;

    logic [DATA_WIDTH-1:0] RDATA;
    rv_axi4_lite_resp            RRESP;

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

endinterface

interface rv_axi4_lite_w_intf #(
    parameter DATA_WIDTH = 32,
    parameter STROBE_WIDTH = DATA_WIDTH / 8
)();

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

endinterface

`endif
