//!import std/std_pkg.sv
//!import std/std_register.sv

module std_shift_register 
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

    input wire shift_in,
    output logic shift_out,

    input wire clear,
    input wire load_enable,
    input wire [WIDTH-1:0] load_value
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
            next = {value[WIDTH-2:0], shift_in};
        end

        if (clear) begin
            next = RESET_VECTOR;
        end

        shift_out = value[WIDTH-1];
    end

endmodule