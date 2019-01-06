`ifndef __RV_MEM__
`define __RV_MEM__

package rv_mem;

    typedef enum bit {
        RV_MEM_READ = 1'b1, 
        RV_MEM_WRITE = 1'b0
    } rv_memory_op;

endpackage

`endif
