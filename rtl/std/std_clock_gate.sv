//!import std/std_pkg

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "../mem/mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

`timescale 1ns/1ps

module std_clock_gate 
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX
)(
    input wire clk_in, 
    input wire clk_en,

    output logic clk_out
);

    generate
    if (TECHNOLOGY == STD_TECHNOLOGY_FPGA_XILINX) begin

        BUFGCE_1 BUFGCE_1_inst(.I(clk_in), .CE(clk_en), .O(clk_out));

    end else if (TECHNOLOGY == STD_TECHNOLOGY_ASIC_TSMC) begin

        // Insert magic top-secret TSMC primitive (it gates the clock *gasp*)

    end else begin

        // TODO: Implement clock gating in other technologies
        `PROCEDURAL_ASSERT(0)

    end
    endgenerate

endmodule
