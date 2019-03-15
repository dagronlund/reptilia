`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

module gecko_system
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
(
    input logic clk, rst,

    input logic instruction_retired,

    std_stream_intf.in system_command, // gecko_system_operation_t
    std_stream_intf.out system_result // gecko_operation_t
);

    logic [63:0] clock_counter; // Works for RDCYCLE and RDTIME
    logic [63:0] instruction_counter;

    // Flow Controller
    std_flow #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) std_flow_inst (
        .clk, .rst,

        .valid_input({system_command.valid}),
        .ready_input({system_command.ready}),
        
        .valid_output({system_result.valid}),
        .ready_output({system_result.ready}),

        .consume({1'b1}),
        .produce({1'b1}),

        .enable
    );

    always_ff @ (posedge clk) begin
        if (rst) begin
            clock_counter <= 'b0;
            instruction_counter <= 'b0;
        end else begin
            clock_counter <= clock_counter + 'b1;
            instruction_counter <= instruction_counter + instruction_retired;
        end
    end

    always_comb begin
        automatic gecko_sys_operation_t command_in;
        automatic gecko_operation_t result_out;

        command_in = gecko_system_operation_t'(system_command.payload);

        case (command_in.sys_op)
        RV32I_FUNCT3_SYS_ENV: begin

        end
        RV32I_FUNCT3_SYS_CSRRW: begin // Read Write

        end
        RV32I_FUNCT3_SYS_CSRRS: begin // Read Set

        end
        RV32I_FUNCT3_SYS_CSRRC: begin // Read Clear

        end
        RV32I_FUNCT3_SYS_CSRRWI: begin // Read Write Imm

        end
        RV32I_FUNCT3_SYS_CSRRSI: begin // Read Set Imm

        end
        RV32I_FUNCT3_SYS_CSRRCI: begin // Read Clear Imm

        end
        default: begin

        end
        endcase

        system_result.payload = result_out;
    end

endmodule
