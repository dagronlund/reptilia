`timescale 1ns/1ps

module clk_rst_gen #(
    parameter ACTIVE_HIGH = 1,
    parameter CYCLES = 5,
    parameter START_DELAY = 0
)(
    output logic clk, rst
    // input logic trigger_rst = 1'b0
);
    int i;

    initial begin
        clk = 0;
        rst = 1;
        for (i = 0; i < START_DELAY; i++) begin
            #1;
        end
        for (i = 0; i < CYCLES; i++) begin
            #5 clk = 1;
            #5 clk = 0;
        end
        rst = 0;
        forever begin 
            #5 clk = ~clk;
        end
    end

endmodule
