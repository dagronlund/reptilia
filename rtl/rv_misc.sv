`timescale 1ns/1ps

`include "../lib/rv_util.svh"

/*
 * A collection of small, single cycle utility modules, which avoid using
 * interfaces and should generally be integrated as part of the state of a
 * larger state machine.
 */

module clk_rst_gen #(
    parameter ACTIVE_HIGH = 1,
    parameter CYCLES = 5
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

module rv_register #(
    parameter WIDTH = 8
)(
    input logic clk, rst,

    input logic load_enable = 1'b0,
    input logic [WIDTH-1:0] load_value = {WIDTH{1'b0}},

    output logic [WIDTH-1:0] value
);

    always_ff @(posedge clk) begin
        if(rst) begin
            value <= 'b0;
        end else if (load_enable) begin
            value <= load_value;
        end
    end

endmodule

module rv_counter #(
    parameter WIDTH = 8
)(
    input logic clk, rst,

    input logic enable, clear = 1'b0,
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

module rv_memory_single_port #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
)(
    input logic clk, rst,

    input logic enable, write_enable,
    input logic [ADDR_WIDTH-1:0] addr_in,
    input logic [DATA_WIDTH-1:0] data_in,

    output logic [DATA_WIDTH-1:0] data_out
);

    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] data [DATA_LENGTH];

    always_ff @(posedge clk) begin
        if (enable) begin
            if (write_enable) begin
                data[addr_in] <= data_in;
            end
            data_out <= data[addr_in];
        end
    end

endmodule

// TODO: Add asymmetric data widths
module rv_memory_double_port #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
)(
    input logic clk, rst,

    input logic enable0, write_enable0,
    input logic [ADDR_WIDTH-1:0] addr_in0,
    input logic [DATA_WIDTH-1:0] data_in0,
    output logic [DATA_WIDTH-1:0] data_out0,

    input logic enable1, write_enable1,
    input logic [ADDR_WIDTH-1:0] addr_in1,
    input logic [DATA_WIDTH-1:0] data_in1,
    output logic [DATA_WIDTH-1:0] data_out1
);

    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] data [DATA_LENGTH];

    /*
    Using two seperate always_ff blocks is super important for Vivado to 
    recognize that this is a true-dual-port block-ram, without a weird output
    register stage.

    A single always_ff block will imply some priority when writing to the
    block-ram at the same time and place, which won't synthesize.
    */

    always_ff @(posedge clk) begin
        if (enable0) begin
            if (write_enable0) begin
                data[addr_in0] <= data_in0;
            end
            data_out0 <= data[addr_in0];
        end
    end

    always_ff @(posedge clk) begin
        if (enable1) begin
            if (write_enable1) begin
                data[addr_in1] <= data_in1;
            end
            data_out1 <= data[addr_in1];
        end
    end

endmodule

module rv_memory_distributed #(
    parameter DATA_WIDTH = 1,
    parameter ADDR_WIDTH = 5,
    parameter READ_PORTS = 1
)(
    input logic clk, rst,

    input logic write_enable,
    input logic [ADDR_WIDTH-1:0] write_addr,
    input logic [DATA_WIDTH-1:0] write_data_in,
    output logic [DATA_WIDTH-1:0] write_data_out,

    input logic [ADDR_WIDTH-1:0] read_addr [READ_PORTS],
    output logic [DATA_WIDTH-1:0] read_data_out [READ_PORTS]
);

    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    (* ram_style="distributed" *)
    logic [DATA_WIDTH-1:0] data [DATA_LENGTH];

    always_ff @(posedge clk) begin
        if (write_enable) begin
            data[write_addr] <= write_data_in;
        end
    end

    always_comb begin
        write_data_out = data[write_addr];
        for (int i = 0; i < READ_PORTS; i++) begin
            read_data_out[i] = data[read_addr[i]];
        end
    end
   
endmodule
