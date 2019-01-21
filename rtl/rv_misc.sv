`timescale 1ns/1ps

module clk_rst_gen #(
    parameter ACTIVE_HIGH = 1,
    parameter CYCLES = 1
)(
    output logic clk, rst
    // input logic trigger_rst = 1'b0
);
    int i;

    initial begin
        clk = 0;
        rst = 1;
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

interface rv_io_intf #()();

    logic i, o, t;
    modport out(output o, t, input i);
    modport in(input o, t, output i);
    modport view(input i, o, t);

endinterface

module rv_counter #(
    parameter WIDTH = 8
)(
    input logic clk, rst,

    input logic enable, clear,
    output logic [WIDTH-1:0] value,

    input logic load_enable = 1'b0,
    input logic [WIDTH-1:0] load_value = {WIDTH{1'b0}},

    input logic [WIDTH-1:0] max = {WIDTH{1'b1}},
    output logic complete
);

    always_ff @(posedge clk) begin
        if(rst || clear) begin
            value <= {WIDTH{1'b0}};
        end else if (load_enable) begin
            value <= load_value;
        end else if (enable) begin
            if (complete) begin
                value <= {WIDTH{1'b0}};
            end else begin
                value <= value + 1'b1;
            end
        end
    end

    always_comb begin
        complete = (value == max) && enable;
    end

endmodule

module rv_shift_register #(
    parameter WIDTH = 8,
    parameter RESET = 'b0
)(
    input logic clk, rst,

    input logic enable,
    output logic [WIDTH-1:0] value,

    input logic shift_in = 1'b0,
    output logic shift_out,

    input logic load_enable = 1'b0,
    input logic [WIDTH-1:0] load_value = {WIDTH{1'b0}}
);

    always_ff @(posedge clk) begin
        if(rst) begin
            value <= RESET;
        end else if (load_enable) begin
            value <= load_value;
        end else if (enable) begin
            value <= {value[WIDTH-2:0], shift_in};
        end
    end

    always_comb begin
        shift_out = value[WIDTH-1];
    end

endmodule
