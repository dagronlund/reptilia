//!import std/std_pkg.sv
//!import std/std_register.sv

module asic_latch_ram
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_ASIC_TSMC,
    parameter int DATA_WIDTH = 1,
    parameter int ADDR_WIDTH = 5,
    parameter int READ_PORTS = 1
)(
    input wire clk, 
    input wire rst,

    input  wire                   write_enable,
    input  wire  [ADDR_WIDTH-1:0] write_addr,
    input  wire  [DATA_WIDTH-1:0] write_data_in,
    output logic [DATA_WIDTH-1:0] write_data_out,

    input  wire  [READ_PORTS-1:0] [ADDR_WIDTH-1:0] read_addr,
    output logic [READ_PORTS-1:0] [DATA_WIDTH-1:0] read_data_out
);

    // TODO: Support falling clock edges with clock gating primitives

    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] data [DATA_LENGTH];
    logic [DATA_WIDTH-1:0] sampled_write_data;
    logic                  write_clocks [DATA_LENGTH];

    // Generate gated write clocks
    genvar k;
    generate
    for (k = 0; k < DATA_LENGTH; k++) begin
        always_comb write_clocks[k] = 
                clk && 
                write_enable && 
                (k[ADDR_WIDTH-1:0] == write_addr);
    end
    endgenerate

    // Register write data
    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic [DATA_WIDTH-1:0]),
        .RESET_VECTOR('b0)
    ) sampled_write_data_register_inst (
        .clk, .rst,
        .enable(write_enable),
        .next(write_data_in),
        .value(sampled_write_data)
    );

    // Perform write operation with latches
    always_latch begin
        for (int i = 0; i < DATA_LENGTH; i++) begin
            if (write_clocks[i]) begin
                data[i] = sampled_write_data;
            end
        end
    end    

    // Read data out
    always_comb begin
        write_data_out = data[write_addr];
        for (int i = 0; i < READ_PORTS; i++) begin
            read_data_out[i] = data[read_addr[i]];
        end
    end

endmodule
