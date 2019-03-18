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

    input gecko_retired_count_t retired_instructions,

    std_stream_intf.in system_command, // gecko_system_operation_t
    std_stream_intf.out system_result // gecko_operation_t
);

    logic [63:0] clock_counter; // Works for RDCYCLE and RDTIME
    logic [63:0] instruction_counter;

    logic consume, produce, enable;

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

        .consume({consume}),
        .produce({produce}),

        .enable
    );

    gecko_operation_t next_system_result;

    always_ff @ (posedge clk) begin
        if (rst) begin
            clock_counter <= 'b0;
            instruction_counter <= 'b0;
        end else begin
            clock_counter <= clock_counter + 'b1;
            instruction_counter <= instruction_counter + retired_instructions;
        end
        if (enable) begin
            system_result.payload <= next_system_result;
        end
    end

    always_comb begin
        automatic gecko_system_operation_t command_in;

        command_in = gecko_system_operation_t'(system_command.payload);

        consume = 'b1;

        next_system_result.addr = command_in.rd_addr;
        next_system_result.speculative = 'b0;
        next_system_result.value = 'b0;

        case (command_in.csr)
        RV32I_CSR_CYCLE: next_system_result.value = clock_counter[31:0];
        RV32I_CSR_TIME: next_system_result.value = clock_counter[31:0];
        RV32I_CSR_INSTRET: next_system_result.value = instruction_counter[31:0];
        RV32I_CSR_CYCLEH: next_system_result.value = clock_counter[63:32];
        RV32I_CSR_TIMEH: next_system_result.value = clock_counter[63:32];
        RV32I_CSR_INSTRETH: next_system_result.value = instruction_counter[63:32];
        endcase

        case (command_in.sys_op)
        RV32I_FUNCT3_SYS_ENV: begin // System Op
            produce = 'b0;
        end
        RV32I_FUNCT3_SYS_CSRRW: begin // Read Write
            produce = (command_in.rd_addr != 'b0); // Don't produce writeback to x0
        end
        RV32I_FUNCT3_SYS_CSRRS: begin // Read Set
            produce = (command_in.rd_addr != 'b0); // Don't produce writeback to x0
        end
        RV32I_FUNCT3_SYS_CSRRC: begin // Read Clear
            produce = (command_in.rd_addr != 'b0); // Don't produce writeback to x0
        end
        RV32I_FUNCT3_SYS_CSRRWI: begin // Read Write Imm
            produce = (command_in.rd_addr != 'b0); // Don't produce writeback to x0
        end
        RV32I_FUNCT3_SYS_CSRRSI: begin // Read Set Imm
            produce = (command_in.rd_addr != 'b0); // Don't produce writeback to x0
        end
        RV32I_FUNCT3_SYS_CSRRCI: begin // Read Clear Imm
            produce = (command_in.rd_addr != 'b0); // Don't produce writeback to x0
        end
        default: begin
            produce = 'b0;
        end
        endcase
    end

endmodule
