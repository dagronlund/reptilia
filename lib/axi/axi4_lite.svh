`ifndef __AXI4_LITE__
`define __AXI4_LITE__

package axi4_lite;

    typedef enum logic [1:0] {
        AXI4_LITE_RESP_OKAY = 2'b00, 
        AXI4_LITE_RESP_EXOKAY = 2'b01, 
        AXI4_LITE_RESP_SLVERR = 2'b10, 
        AXI4_LITE_RESP_DECERR = 2'b11
    } axi4_lite_resp_t;

    typedef enum logic {
        AXI4_LITE_UNPRIVILEDGED_ACCESS = 1'b0,
        AXI4_LITE_PRIVILEDGED_ACCESS = 1'b1
    } axi4_lite_privilege_t;

    typedef enum logic {
        AXI4_LITE_SECURE_ACCESS = 1'b0,
        AXI4_LITE_NONSECURE_ACCESS = 1'b1
    } axi4_lite_security_t;

    typedef enum logic {
        AXI4_LITE_DATA_ACCESS = 1'b0,
        AXI4_LITE_INSTRUCTION_ACCESS = 1'b1
    } axi4_lite_access_t;

    typedef struct packed {
        axi4_lite_access_t access;
        axi4_lite_security_t security;
        axi4_lite_privilege_t privilege;
    } axi4_lite_prot_t;

endpackage

`endif
