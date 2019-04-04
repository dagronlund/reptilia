`include "../lib/isa/rv.svh"
`include "../lib/isa/rv32.svh"
`include "../lib/isa/rv32i.svh"

`include "../lib/gecko/gecko.svh"

module gecko_micro_wrapper();

    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;

    logic clk, rst, faulted_flag, finished_flag;

    gecko_micro #(
        .ADDR_SPACE_WIDTH(12),
        .START_ADDR('b0),
        .ENABLE_PERFORMANCE_COUNTERS(0)
    )gecko_micro_inst(
        .clk(clk), 
        .rst(rst), 
        .faulted_flag(faulted_flag), 
        .finished_flag(finished_flag)
    );

    gecko_test_wrapper gecko_test_wrapper_inst(
        .clk, .rst,
        .faulted(faulted_flag),
        .finished(finished_flag)
    );

endmodule