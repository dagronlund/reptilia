`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

module gecko_tb
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#()();

    initial begin
        automatic gecko_math_result_t result;
        result = gecko_get_full_math_result(32'h80000000, 'b1, 'b1);
        $display("Selected Result %h", result.rshift_result);
        $display("Result: %p", result);
    end

endmodule
