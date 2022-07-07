//!import std/std_pkg.sv
//!import std/std_register.sv

// TODO: Add asymmetric data widths
module xilinx_block_ram_double 
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 10,
    parameter int MASK_WIDTH = DATA_WIDTH / 8,
    parameter bit ENABLE_OUTPUT_REG0 = 0,
    parameter bit ENABLE_OUTPUT_REG1 = 0,
    parameter HEX_FILE = ""
)(
    input wire clk, 
    input wire rst,

    input wire                    enable0, 
    input wire                    enable_output0,
    input wire [MASK_WIDTH-1:0]   write_enable0,
    input wire [ADDR_WIDTH-1:0]   addr_in0,
    input wire [DATA_WIDTH-1:0]   data_in0,
    output logic [DATA_WIDTH-1:0] data_out0,

    input wire                    enable1, 
    input wire                    enable_output1,
    input wire [MASK_WIDTH-1:0]   write_enable1,
    input wire [ADDR_WIDTH-1:0]   addr_in1,
    input wire [DATA_WIDTH-1:0]   data_in1,
    output logic [DATA_WIDTH-1:0] data_out1
);

    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] data [DATA_LENGTH];

    initial begin
        for (int i = 0; i < DATA_LENGTH; i++) begin
            data[i] = 'b0;
        end
        if (HEX_FILE != "") begin
            $readmemh(HEX_FILE, data);
        end
    end

    logic [DATA_WIDTH-1:0] data_out_temp0, data_out_temp1;

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
            if (CLOCK_INFO.clock_edge == STD_CLOCK_EDGE_RISING) begin

                always_ff @(posedge clk) begin
                    if (enable0) begin
                        if (write_enable0[k]) begin
                            data[addr_in0][((k+1)*8)-1:(k*8)] <= data_in0[((k+1)*8)-1:(k*8)];
                        end            
                        data_out_temp0[((k+1)*8)-1:(k*8)] <= data[addr_in0][((k+1)*8)-1:(k*8)];
                    end
                end

                always_ff @(posedge clk) begin
                    if (enable1) begin
                        if (write_enable1[k]) begin
                            data[addr_in1][((k+1)*8)-1:(k*8)] <= data_in1[((k+1)*8)-1:(k*8)];
                        end
                        data_out_temp1[((k+1)*8)-1:(k*8)] <= data[addr_in1][((k+1)*8)-1:(k*8)];
                    end
                end

            end else begin

                always_ff @(negedge clk) begin
                    if (enable0) begin
                        if (write_enable0[k]) begin
                            data[addr_in0][((k+1)*8)-1:(k*8)] <= data_in0[((k+1)*8)-1:(k*8)];
                        end            
                        data_out_temp0[((k+1)*8)-1:(k*8)] <= data[addr_in0][((k+1)*8)-1:(k*8)];
                    end
                end

                always_ff @(negedge clk) begin
                    if (enable1) begin
                        if (write_enable1[k]) begin
                            data[addr_in1][((k+1)*8)-1:(k*8)] <= data_in1[((k+1)*8)-1:(k*8)];
                        end
                        data_out_temp1[((k+1)*8)-1:(k*8)] <= data[addr_in1][((k+1)*8)-1:(k*8)];
                    end
                end

            end
        end

        if (ENABLE_OUTPUT_REG0) begin

            std_register #(
                .CLOCK_INFO(CLOCK_INFO),
                .T(logic[DATA_WIDTH-1:0]),
                .RESET_VECTOR('b0)
            ) output_reg0_inst (
                .clk, .rst,
                .enable(enable_output0),
                .next(data_out_temp0),
                .value(data_out0)
            );

        end else begin
            always_comb data_out0 = data_out_temp0;
        end

        if (ENABLE_OUTPUT_REG1) begin
            
            std_register #(
                .CLOCK_INFO(CLOCK_INFO),
                .T(logic[DATA_WIDTH-1:0]),
                .RESET_VECTOR('b0)
            ) output_reg1_inst (
                .clk, .rst,
                .enable(enable_output1),
                .next(data_out_temp1),
                .value(data_out1)
            );
        
        end else begin
            always_comb data_out1 = data_out_temp1;
        end
    endgenerate

endmodule