`ifndef __AXI4__
`define __AXI4__

package axi4;

    typedef logic [7:0] axi4_len_t;
    typedef logic [3:0] axi4_qos_t;
    typedef logic [2:0] axi4_size_t;

    typedef enum logic [1:0] {
        AXI4_RESP_OKAY = 2'b00, 
        AXI4_RESP_EXOKAY = 2'b01, 
        AXI4_RESP_SLVERR = 2'b10, 
        AXI4_RESP_DECERR = 2'b11
    } axi4_resp_t;

    typedef enum logic [1:0] {
        AXI4_BURST_FIXED = 2'b00,
        AXI4_BURST_INCR = 2'b01,
        AXI4_BURST_WRAP = 2'b10,
        AXI4_BURST_UNDEF = 2'b11
    } axi4_burst_t;

    typedef enum logic {
        AXI4_NON_BUFFERABLE = 1'b0,
        AXI4_BUFFERABLE = 1'b1
    } axi4_bufferable_t;

    typedef enum logic {
        AXI4_NON_MODIFIABLE = 1'b0,
        AXI4_MODIFIABLE = 1'b1
    } axi4_modifiable_t;

    typedef enum logic {
        AXI4_UNALLOCATED = 1'b0,
        AXI4_ALLOCATED = 1'b1
    } axi4_allocation_t;

    typedef struct packed {
        axi4_allocation_t allocation;
        axi4_allocation_t other_allocation;
        axi4_modifiable_t cacheable;
        axi4_bufferable_t bufferable;
    } axi4_cache_t;

    typedef enum logic {
        AXI4_LOCK_NORMAL = 1'b0,
        AXI4_LOCK_EXCLUSIVE = 1'b1
    } axi4_lock_t;

    typedef enum logic {
        AXI4_UNPRIVILEDGED_ACCESS = 1'b0,
        AXI4_PRIVILEDGED_ACCESS = 1'b1
    } axi4_privilege_t;

    typedef enum logic {
        AXI4_SECURE_ACCESS = 1'b0,
        AXI4_NONSECURE_ACCESS = 1'b1
    } axi4_security_t;

    typedef enum logic {
        AXI4_DATA_ACCESS = 1'b0,
        AXI4_INSTRUCTION_ACCESS = 1'b1
    } axi4_access_t;

    typedef struct packed {
        axi4_access_t access;
        axi4_security_t security;
        axi4_privilege_t privilege;
    } axi4_prot_t;

endpackage

`endif
