//!import std/std_pkg.sv
//!import std/std_register.sv

module std_register_masked
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter type T = logic,
    parameter T RESET_VECTOR = 'b0
)(
    input wire clk, 
    input wire rst,

    input T enable,
    input T next,
    output T value
);

    localparam logic [$bits(T)-1:0] RESET_VECTOR_INTERNAL = {RESET_VECTOR};

    logic [$bits(T)-1:0] enable_internal;
    logic [$bits(T)-1:0] next_internal;
    logic [$bits(T)-1:0] value_internal;

    always_comb enable_internal = {enable};
    always_comb next_internal = {next};
    always_comb {value} = value_internal;

    genvar k;
    generate
    for (k = 0; k < $bits(T); k++) begin

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR(RESET_VECTOR_INTERNAL[k])
        ) std_register_inst (
            .clk, .rst,

            .enable(enable_internal[k]),
            .next(next_internal[k]),
            .value(value_internal[k])
        );

    end
    endgenerate

endmodule
