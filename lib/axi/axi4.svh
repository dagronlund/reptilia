`ifndef __AXI4__
`define __AXI4__

package axi4;

    typedef enum logic [1:0] {
        AXI4_RESP_OKAY = 2'b00, 
        AXI4_RESP_EXOKAY = 2'b01, 
        AXI4_RESP_SLVERR = 2'b10, 
        AXI4_RESP_DECERR = 2'b11
    } axi4_resp;

    typedef enum logic [1:0] {
        AXI4_BURST_FIXED = 2'b00,
        AXI4_BURST_INCR = 2'b01,
        AXI4_BURST_WRAP = 2'b10,
        AXI4_BURST_UNDEF = 2'b11
    } axi4_burst;

    typedef enum logic {
        AXI4_NON_BUFFERABLE = 1'b0,
        AXI4_BUFFERABLE = 1'b1
    } axi4_bufferable;

    typedef enum logic {
        AXI4_NON_MODIFIABLE = 1'b0,
        AXI4_MODIFIABLE = 1'b1
    } axi4_modifiable;

    typedef enum logic {
        AXI4_UNALLOCATED = 1'b0,
        AXI4_ALLOCATED = 1'b1
    } axi4_allocation;

    typedef struct packed {
        axi4_allocation allocation;
        axi4_allocation other_allocation;
        axi4_modifiable cacheable;
        axi4_bufferable bufferable;
    } axi4_cache;

    typedef enum logic {
        AXI4_LOCK_NORMAL = 1'b0,
        AXI4_LOCK_EXCLUSIVE = 1'b1
    } axi4_lock;

    typedef enum logic {
        AXI4_UNPRIVILEDGED_ACCESS = 1'b0,
        AXI4_PRIVILEDGED_ACCESS = 1'b1
    } axi4_privilege;

    typedef enum logic {
        AXI4_SECURE_ACCESS = 1'b0,
        AXI4_NONSECURE_ACCESS = 1'b1
    } axi4_security;

    typedef enum logic {
        AXI4_DATA_ACCESS = 1'b0,
        AXI4_INSTRUCTION_ACCESS = 1'b1
    } axi4_access;

    typedef struct packed {
        axi4_access access;
        axi4_security security;
        axi4_privilege privilege;
    } axi4_prot;

endpackage

`endif
