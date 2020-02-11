//!import std/std_pkg

`timescale 1ns/1ps

module xilinx_distributed_ram
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter int DATA_WIDTH = 1,
    parameter int ADDR_WIDTH = 5,
    parameter int READ_PORTS = 1
)(
    input wire clk, 
    input wire rst,

    input wire [DATA_WIDTH-1:0]   write_enable,
    input wire [ADDR_WIDTH-1:0]   write_addr,
    input wire [DATA_WIDTH-1:0]   write_data_in,
    output logic [DATA_WIDTH-1:0] write_data_out,

    input wire [ADDR_WIDTH-1:0]   read_addr [READ_PORTS],
    output logic [DATA_WIDTH-1:0] read_data_out [READ_PORTS]
);

    localparam DATA_LENGTH = 2**ADDR_WIDTH;

    (* ram_style="distributed" *)
    logic [DATA_WIDTH-1:0] data [DATA_LENGTH];

    initial begin
        for (int i = 0; i < DATA_LENGTH; i++) begin
            data[i] = 'b0;
        end
    end

    generate
    genvar k;
    for (k = 0; k < DATA_WIDTH; k++) begin
        if (CLOCK_INFO.clock_edge == STD_CLOCK_EDGE_RISING) begin

            always_ff @(posedge clk) begin
                if (write_enable[k]) begin
                    data[write_addr][k] <= write_data_in[k];
                end
            end

        end else begin

            always_ff @(negedge clk) begin
                if (write_enable[k]) begin
                    data[write_addr][k] <= write_data_in[k];
                end
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