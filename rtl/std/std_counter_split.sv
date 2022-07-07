//!import std/std_pkg.sv
//!import std/std_register.sv

module std_counter_split
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter int WIDTH = 8,
    parameter logic [WIDTH-1:0] RESET_VECTOR = 'b0
)(
    input wire clk, 
    input wire rst,

    input wire increment_enable,
    input wire decrement_enable,
    
    output logic [WIDTH-1:0] value, front_value, rear_value
);

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic[WIDTH-1:0]),
        .RESET_VECTOR(RESET_VECTOR)
    ) front_register_inst (
        .clk, .rst,
        .enable(increment_enable),
        .next(front_value + 'b1),
        .value(front_value)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic[WIDTH-1:0]),
        .RESET_VECTOR(RESET_VECTOR)
    ) rear_register_inst (
        .clk, .rst,
        .enable(decrement_enable),
        .next(rear_value + 'b1),
        .value(rear_value)
    );

    always_comb begin
        value = front_value - rear_value;
    end

endmodule
