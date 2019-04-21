`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/isa/rv32f.svh"

`include "../../lib/gecko/gecko.svh"
`include "../../lib/basilisk/basilisk.svh"

module basilisk_input
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
(
    input logic clk, rst,

    std_stream_intf.in input_command, // ...
    std_stream_intf.in output_command // ...
);

endmodule
