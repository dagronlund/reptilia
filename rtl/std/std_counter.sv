//!import std/std_pkg
//!import std/std_register

`timescale 1ns/1ps

module std_counter 
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter int WIDTH = 8,
    parameter logic [WIDTH-1:0] RESET_VECTOR = 'b0
)(
    input wire clk, 
    input wire rst,

    input wire enable,
    output logic [WIDTH-1:0] value,

    input wire clear = 1'b0,
    input wire load_enable = 1'b0,
    input wire [WIDTH-1:0] load_value = 'b0,

    input wire [WIDTH-1:0] max = {WIDTH{1'b1}},
    output logic complete
);

    logic [WIDTH-1:0] next;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic[WIDTH-1:0]),
        .RESET_VECTOR(RESET_VECTOR)
    ) std_register_inst (
        .clk, .rst,
        .enable(enable),
        .next(next),
        .value(value)
    );

    always_comb begin
        if (load_enable) begin
            next = load_value;
        end else begin
            next = value + 'b1;
        end 

        complete = (value == max);

        if (complete || clear) begin
            next = RESET_VECTOR;
        end
    end

endmodule
