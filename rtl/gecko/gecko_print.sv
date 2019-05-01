`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/gecko/gecko.svh"

`else

`include "std_util.svh"
`include "std_mem.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32i.svh"
`include "gecko.svh"

`endif

module gecko_print
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#()(
    input logic clk, rst,

    std_stream_intf.in ecall_command, // gecko_ecall_operation_t
    std_stream_intf.out print_out // logic [7:0]
);

    logic consume, produce, enable;

    // Flow Controller
    std_flow #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) std_flow_inst (
        .clk, .rst,

        .valid_input({ecall_command.valid}),
        .ready_input({ecall_command.ready}),
        
        .valid_output({print_out.valid}),
        .ready_output({print_out.ready}),

        .consume, .produce, .enable
    );

    logic [7:0] next_print_out;

    always_ff @ (posedge clk) begin
        if (enable) begin
            print_out.payload <= next_print_out;
        end
    end

    always_comb begin
        consume = 'b1;
        produce = (ecall_command.payload.operation == 'b0);
        next_print_out = ecall_command.payload.data;
    end

endmodule
