//!import std/std_pkg.sv
//!import std/std_register.sv

module xilinx_block_ram_single 
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 10,
    parameter int MASK_WIDTH = DATA_WIDTH / 8,
    parameter bit ENABLE_OUTPUT_REG = 0,
    parameter HEX_FILE = ""
)(
    input wire clk, 
    input wire rst,

    input wire                    enable,
    input wire                    enable_output,
    input wire [MASK_WIDTH-1:0]   write_enable,
    input wire [ADDR_WIDTH-1:0]   addr_in,
    input wire [DATA_WIDTH-1:0]   data_in,
    output logic [DATA_WIDTH-1:0] data_out
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

    logic [DATA_WIDTH-1:0] data_out_temp;

    generate
    genvar k;
    for (k = 0; k < MASK_WIDTH; k++) begin
        if (CLOCK_INFO.clock_edge == STD_CLOCK_EDGE_RISING) begin

            always_ff @(posedge clk) begin
                if (enable) begin
                    if (write_enable[k]) begin
                        data[addr_in][((k+1)*8)-1:(k*8)] <= data_in[((k+1)*8)-1:(k*8)];
                    end
                    data_out_temp[((k+1)*8)-1:(k*8)] <= data[addr_in][((k+1)*8)-1:(k*8)];
                end
            end

        end else begin
            
            always_ff @(negedge clk) begin
                if (enable) begin
                    if (write_enable[k]) begin
                        data[addr_in][((k+1)*8)-1:(k*8)] <= data_in[((k+1)*8)-1:(k*8)];
                    end
                    data_out_temp[((k+1)*8)-1:(k*8)] <= data[addr_in][((k+1)*8)-1:(k*8)];
                end
            end

        end
    end

    if (ENABLE_OUTPUT_REG) begin

        // Try register in another module?
        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic[DATA_WIDTH-1:0]),
            .RESET_VECTOR('b0)
        ) output_reg_inst (
            .clk, .rst,
            .enable(enable_output),
            .next(data_out_temp),
            .value(data_out)
        );

    end else begin
        always_comb data_out = data_out_temp;
    end
    endgenerate

endmodule
