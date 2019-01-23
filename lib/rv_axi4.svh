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

`endif
