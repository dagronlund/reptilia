`ifndef __RV_MEM__
`define __RV_MEM__

package rv_mem;

    typedef enum bit {
        RV_MEM_READ = 1'b1, 
        RV_MEM_WRITE = 1'b0
    } rv_memory_op;

endpackage

`define STATIC_MATCH_MEM(INTF1, INTF2) \
    `STATIC_ASSERT($bits(INTF1.data) == $bits(INTF2.data)) \
    `STATIC_ASSERT($bits(INTF1.addr) == $bits(INTF2.addr)) \
    `STATIC_ASSERT(INTF1.ADDR_BYTE_SHIFTED == INTF2.ADDR_BYTE_SHIFTED)

`endif
