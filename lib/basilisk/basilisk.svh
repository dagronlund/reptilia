`ifndef __BASILISK__
`define __BASILISK__

`ifdef __SIMULATION__
`include "../isa/rv32.svh"
`include "../isa/rv32i.svh"
`endif

package basilisk;

    import rv32::*;
    import rv32i::*;
    import rv32f::*;

endpackage
