`ifndef __RV_MEM__
`define __RV_MEM__

package rv_mem;

    typedef enum bit {
        RV_MEM_READ = 1'b1, 
        RV_MEM_WRITE = 1'b0
    } rv_memory_op;

    interface rv_mem #(
        parameter DATA_WIDTH = 32,
        parameter ADDR_WIDTH = 10
    )();

        logic valid, ready, block;
        rv_memory_op op;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] data;

        modport out(
            output valid, block,
            input ready,
            output op, addr, data
        );

        modport in(
            input valid, block,
            output ready,
            input op, addr, data
        );
        
        modport view(
            input valid, block, ready,
            input op, addr, data
        );
    
    endinterface

endpackage

`endif