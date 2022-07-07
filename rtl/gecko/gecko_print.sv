//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import riscv/riscv32i_pkg.sv
//!import gecko/gecko_pkg.sv
//!import stream/stream_intf.sv
//!import stream/stream_controller.sv
//!import stream/stream_stage.sv
//!wrapper gecko/gecko_print_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

module gecko_print
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import gecko_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED
)(
    input wire clk, 
    input wire rst,
    stream_intf.in ecall_command, // gecko_ecall_operation_t
    stream_intf.out print_out // logic [7:0]
);

    logic consume, produce, enable;

    stream_intf #(.T(logic [7:0])) next_print_out (.clk, .rst);

    stream_controller #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) stream_controller_inst (
        .clk, .rst,

        .valid_input({ecall_command.valid}),
        .ready_input({ecall_command.ready}),
        
        .valid_output({next_print_out.valid}),
        .ready_output({next_print_out.ready}),

        .consume, .produce, .enable
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(logic [7:0])
    ) print_out_stage_inst (
        .clk, .rst,
        .stream_in(next_print_out), .stream_out(print_out)
    );

    always_comb begin
        consume = 'b1;
        produce = (ecall_command.payload.operation == 'b0);
        next_print_out.payload = ecall_command.payload.data;
    end

endmodule
