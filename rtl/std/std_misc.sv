`timescale 1ns/1ps

/*
 * A collection of small, single cycle utility modules, which avoid using
 * interfaces and should generally be integrated as part of the state of a
 * larger state machine.
 */

module std_register #(
    parameter WIDTH = 8,
    parameter logic [WIDTH-1:0] RESET = 'b0
)(
    input logic clk, rst,

    input logic enable = 'b0,
    input logic [WIDTH-1:0] next_value = 'b0,
    output logic [WIDTH-1:0] value
);

    always_ff @(posedge clk) begin
        if(rst) begin
            value <= RESET;
        end else if (enable) begin
            value <= next_value;
        end
    end

endmodule

module std_counter #(
    parameter WIDTH = 8
)(
    input logic clk, rst,

    input logic enable, clear = 1'b0,
    output logic [WIDTH-1:0] value, next_value,

    input logic load_enable = 1'b0,
    input logic [WIDTH-1:0] load_value = 'b0,

    input logic [WIDTH-1:0] max = {WIDTH{1'b1}},
    output logic complete
);

    std_register #(
        .WIDTH(WIDTH)
    ) std_register_inst (
        .clk, .rst,
        .enable(enable || clear), // TODO: Hmm
        .next_value(next_value),
        .value(value)
    );

    always_comb begin
        complete = (value == max) && enable;
        if (load_enable) begin
            next_value = load_value;
        end else if (complete || clear) begin
            next_value = {WIDTH{1'b0}};
        end else begin
            next_value = value + 'b1;
        end 
    end

endmodule

// TODO: Change to use register module
module std_shift_register #(
    parameter WIDTH = 8,
    parameter RESET = 'b0
)(
    input logic clk, rst,

    input logic enable,
    output logic [WIDTH-1:0] value, next_value,

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

module std_block_ram_single #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10,
    parameter MASK_WIDTH = DATA_WIDTH / 8
)(
    input logic clk, rst,

    input logic enable, 
    input logic [MASK_WIDTH-1:0] write_enable,
    input logic [ADDR_WIDTH-1:0] addr_in,
    input logic [DATA_WIDTH-1:0] data_in,
    output logic [DATA_WIDTH-1:0] data_out
);

    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] data [DATA_LENGTH];

    generate
        genvar k;
        for (k = 0; k < MASK_WIDTH; k++) begin
            always_ff @(posedge clk) begin
                if (enable) begin
                    if (write_enable[k]) begin
                        data[addr_in][((k+1)*8)-1:(k*8)] <= data_in[((k+1)*8)-1:(k*8)];
                    end
                    data_out[((k+1)*8)-1:(k*8)] <= data[addr_in][((k+1)*8)-1:(k*8)];
                end
            end
        end
    endgenerate

endmodule

// TODO: Add asymmetric data widths
module std_block_ram_double #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10,
    parameter MASK_WIDTH = DATA_WIDTH / 8
)(
    input logic clk, rst,

    input logic enable0, 
    input logic [MASK_WIDTH-1:0] write_enable0,
    input logic [ADDR_WIDTH-1:0] addr_in0,
    input logic [DATA_WIDTH-1:0] data_in0,
    output logic [DATA_WIDTH-1:0] data_out0,

    input logic enable1, 
    input logic [MASK_WIDTH-1:0] write_enable1,
    input logic [ADDR_WIDTH-1:0] addr_in1,
    input logic [DATA_WIDTH-1:0] data_in1,
    output logic [DATA_WIDTH-1:0] data_out1
);

    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] data [DATA_LENGTH];

    /*
     * Using two seperate always_ff blocks is super important for Vivado to 
     * recognize that this is a true-dual-port block-ram, without a weird output
     * register stage.
     *
     * A single always_ff block will imply some priority when writing to the
     * block-ram at the same time and place, which won't synthesize.
     */
    generate
        genvar k;
        for (k = 0; k < MASK_WIDTH; k++) begin
            always_ff @(posedge clk) begin
                if (enable0) begin
                    if (write_enable0[k]) begin
                        data[addr_in0][((k+1)*8)-1:(k*8)] <= data_in0[((k+1)*8)-1:(k*8)];
                    end            
                    data_out0[((k+1)*8)-1:(k*8)] <= data[addr_in0][((k+1)*8)-1:(k*8)];
                end
            end

            always_ff @(posedge clk) begin
                if (enable1) begin
                    if (write_enable1[k]) begin
                        data[addr_in1][((k+1)*8)-1:(k*8)] <= data_in1[((k+1)*8)-1:(k*8)];
                    end
                    data_out1[((k+1)*8)-1:(k*8)] <= data[addr_in1][((k+1)*8)-1:(k*8)];
                end
            end
        end
    endgenerate

endmodule

module std_distributed_ram #(
    parameter DATA_WIDTH = 1,
    parameter ADDR_WIDTH = 5,
    parameter READ_PORTS = 1
)(
    input logic clk, rst,

    input logic [DATA_WIDTH-1:0] write_enable,
    input logic [ADDR_WIDTH-1:0] write_addr,
    input logic [DATA_WIDTH-1:0] write_data_in,
    output logic [DATA_WIDTH-1:0] write_data_out,

    input logic [ADDR_WIDTH-1:0] read_addr [READ_PORTS],
    output logic [DATA_WIDTH-1:0] read_data_out [READ_PORTS]
);

    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    (* ram_style="distributed" *)
    logic [DATA_WIDTH-1:0] data [DATA_LENGTH];

    generate
        genvar k;
        for (k = 0; k < DATA_WIDTH; k++) begin
            always_ff @(posedge clk) begin
                if (write_enable[k]) begin
                    data[write_addr][k] <= write_data_in[k];
                end
            end
        end
    endgenerate

    always_comb begin
        write_data_out = data[write_addr];
        for (int i = 0; i < READ_PORTS; i++) begin
            read_data_out[i] = data[read_addr[i]];
        end
    end
   
endmodule
