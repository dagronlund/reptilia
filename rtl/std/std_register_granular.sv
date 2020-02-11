//!import std/std_pkg
//!import std/std_register

`timescale 1ns/1ps

module std_register_granular
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter type T = logic,
    parameter T RESET_VECTOR = 'b0
)(
    input wire clk, 
    input wire rst,

    input T enable = 'b0,
    input T next = 'b0,
    output T value
);

    genvar k;
    generate
    for (k = 0; k < $bits(T); k++) begin

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR(RESET_VECTOR[k])
        ) std_register_inst (
            .clk, .rst,

            .enable(enable[k]),
            .next(next[k]),
            .value(value[k])
        );

    end
    endgenerate

endmodule
