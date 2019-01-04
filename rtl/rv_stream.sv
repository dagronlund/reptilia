`timescale 1ns/1ps

module rv_stream_stage #(
    parameter DATA_WIDTH = 1
)(
    input logic clk, rst,

    input logic input_valid,
    output logic input_ready,
    input logic [DATA_WIDTH-1:0] input_data,
    
    output logic output_valid,
    input logic output_ready,
    output logic [DATA_WIDTH-1:0] output_data
);

    logic data_valid;
    logic [DATA_WIDTH-1:0] data;

    always_ff @(posedge clk) begin
        if(rst) begin
            data_valid <= 0;
        end else if (input_ready && input_valid) begin
            data_valid <= 1;
            data <= input_data;
        end else if (output_ready) begin
            data_valid <= 0;
        end
    end

    always_comb begin
        input_ready = !data_valid || output_ready;
        output_valid = data_valid;
        output_data = data;
    end

endmodule

module rv_stream_break #(
    parameter DATA_WIDTH = 1
)(
    input logic clk,
    input logic rst,

    input logic input_valid,
    output logic input_ready,
    input logic [DATA_WIDTH-1:0] input_data,
    
    output logic output_valid,
    input logic output_ready,
    output logic [DATA_WIDTH-1:0] output_data
);

    logic input_flag, output_flag;
    
    logic [1:0] data_valid;
    logic [1:0][DATA_WIDTH-1:0] data;

    always_ff @(posedge clk) begin
        if (rst) begin
            input_flag <= 1'b0;
            output_flag <= 1'b0;
            data_valid[1:0] <= 2'b00;
        end else begin
            if (output_ready && data_valid[output_flag]) begin
                data_valid[output_flag] <= 1'b0;
                output_flag <= !output_flag;
            end 

            if (input_valid && !data_valid[input_flag]) begin
                data_valid[input_flag] <= 1'b1;
                data[input_flag] <= input_data;
                input_flag <= !input_flag;
            end
        end
    end

    always_comb begin
        input_ready = !data_valid[input_flag];
        output_valid = data_valid[output_flag];

        output_data = data[output_flag];
    end

endmodule

module rv_stream_reset #(
    parameter DATA_WIDTH = 1
)(
    input logic input_rst, output_rst,

    input logic input_valid,
    output logic input_ready,
    input logic [DATA_WIDTH-1:0] input_data,
    
    output logic output_valid,
    input logic output_ready,
    output logic [DATA_WIDTH-1:0] output_data
);

    always_comb begin
        output_valid = input_valid && !input_rst;
        input_ready = output_ready && !output_rst;

        output_data = input_data;
    end

endmodule
