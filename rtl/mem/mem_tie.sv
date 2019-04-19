`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`else

`include "std_util.svh"
`include "std_mem.svh"

`endif

module mem_tie #()(
    std_mem_intf.in mem_in,
    std_mem_intf.out mem_out
);

    `STATIC_ASSERT($bits(mem_in.addr) == $bits(mem_out.addr))
    `STATIC_ASSERT($bits(mem_in.write_enable) == $bits(mem_out.write_enable))
    `STATIC_ASSERT($bits(mem_in.data) == $bits(mem_out.data))
    `STATIC_ASSERT($bits(mem_in.id) == $bits(mem_out.id))

    always_comb begin
        mem_out.valid = mem_in.valid;
        mem_in.ready = mem_out.ready;
        mem_out.read_enable = mem_in.read_enable;
        mem_out.write_enable = mem_in.write_enable;
        mem_out.addr = mem_in.addr;
        mem_out.data = mem_in.data;
        mem_out.id = mem_in.id;
    end

endmodule
