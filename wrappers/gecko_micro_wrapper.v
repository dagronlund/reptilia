module gecko_micro_wrapper(
    input wire clk, rst,
    output wire faulted_flag, finished_flag
);

    gecko_micro_wrapper_sv gecko_micro_inst(
        .clk(clk), 
        .rst(rst), 
        .faulted_flag(faulted_flag), 
        .finished_flag(finished_flag)
    );

endmodule