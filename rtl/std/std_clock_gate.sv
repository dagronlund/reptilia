//!include std/std_util.svh
//!import std/std_pkg.sv

`include "std/std_util.svh"

module std_clock_gate 
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_SIMULATION
)(
    input wire clk_in, 
    input wire clk_en,

    output logic clk_out
);

    generate
    if (TECHNOLOGY == STD_TECHNOLOGY_FPGA_XILINX) begin
        BUFGCE_1 BUFGCE_1_inst(.I(clk_in), .CE(clk_en), .O(clk_out));
    end else begin
        always_comb clk_out = clk_in && clk_en;
    end
    endgenerate

endmodule
