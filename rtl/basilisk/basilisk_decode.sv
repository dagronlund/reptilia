`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/gecko/gecko.svh"
`include "../../lib/basilisk/basilisk.svh"

`else

`include "std_util.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32i.svh"
`include "rv32f.svh"
`include "gecko.svh"
`include "basilisk.svh"

`endif

module basilisk_decode
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import rv32f::*;
    import gecko::*;
    import basilisk::*;
#(
    // parameter int INST_LATENCY = 1,
    // parameter int DATA_LATENCY = 1,
    // parameter int INST_PIPELINE_BREAK = 1,
    // parameter gecko_pc_t START_ADDR = 'b0,
    // parameter int ENABLE_PERFORMANCE_COUNTERS = 1,
    // parameter int ENABLE_PRINT = 1
)(
    input logic clk, rst
);



endmodule
