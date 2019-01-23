`ifndef __RV_AXI4_LITE__
`define __RV_AXI4_LITE__

package rv_axi4_lite;

    typedef enum logic [1:0] {
        RV_AXI4_LITE_RESP_OKAY = 2'b00, 
        RV_AXI4_LITE_RESP_EXOKAY = 2'b01, 
        RV_AXI4_LITE_RESP_SLVERR = 2'b10, 
        RV_AXI4_LITE_RESP_DECERR = 2'b11
    } rv_axi4_lite_resp;

    typedef enum logic {
        RV_AXI4_LITE_UNPRIVILEDGED_ACCESS = 1'b0,
        RV_AXI4_LITE_PRIVILEDGED_ACCESS = 1'b1
    } rv_axi4_lite_privilege;

    typedef enum logic {
        RV_AXI4_LITE_SECURE_ACCESS = 1'b0,
        RV_AXI4_LITE_NONSECURE_ACCESS = 1'b1
    } rv_axi4_lite_security;

    typedef enum logic {
        RV_AXI4_LITE_DATA_ACCESS = 1'b0,
        RV_AXI4_LITE_INSTRUCTION_ACCESS = 1'b1
    } rv_axi4_lite_access;

    typedef struct packed {
        rv_axi4_lite_access access;
        rv_axi4_lite_security security;
        rv_axi4_lite_privilege privilege;
    } rv_axi4_lite_prot;

endpackage

`endif
