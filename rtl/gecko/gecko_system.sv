//!import std/std_pkg
//!import stream/stream_pkg
//!import riscv/riscv_pkg
//!import riscv/riscv32_pkg
//!import riscv/riscv32i_pkg
//!import gecko/gecko_pkg

`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "../mem/mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

module gecko_system
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import gecko_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter int ENABLE_PERFORMANCE_COUNTERS = 1
)(
    input wire clk, 
    input wire rst,
    input gecko_retired_count_t retired_instructions,
    stream_intf.in system_command, // gecko_system_operation_t
    stream_intf.out system_result // gecko_operation_t
);

    // Clock counter works for RDCYCLE and RDTIME
    logic [32:0] next_clock_counter_partial, next_instruction_counter_partial;
    logic [32:0] clock_counter_partial, instruction_counter_partial;
    logic [63:0] next_clock_counter, next_instruction_counter;
    logic [63:0] clock_counter, instruction_counter;

    logic consume, produce, enable;

    stream_intf #(.T(gecko_operation_t)) next_system_result (.clk, .rst);

    stream_controller #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) stream_controller_inst (
        .clk, .rst,

        .valid_input({system_command.valid}),
        .ready_input({system_command.ready}),
        
        .valid_output({next_system_result.valid}),
        .ready_output({next_system_result.ready}),

        .consume({consume}),
        .produce({produce}),

        .enable
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(gecko_operation_t)
    ) system_result_stage_inst (
        .clk, .rst,
        .stream_in(next_system_result), .stream_out(system_result)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic [32:0]),
        .RESET_VECTOR('b0)
    ) clock_counter_partial_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(next_clock_counter_partial),
        .value(clock_counter_partial)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic [32:0]),
        .RESET_VECTOR('b0)
    ) instruction_counter_partial_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(next_instruction_counter_partial),
        .value(instruction_counter_partial)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic [63:0]),
        .RESET_VECTOR('b0)
    ) clock_counter_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(next_clock_counter),
        .value(clock_counter)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic [63:0]),
        .RESET_VECTOR('b0)
    ) instruction_counter_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(next_instruction_counter),
        .value(instruction_counter)
    );

    always_comb begin
        automatic gecko_system_operation_t command_in;

        next_clock_counter_partial = {1'b0, clock_counter_partial[31:0]} + 'b1;
        next_instruction_counter_partial = {1'b0, instruction_counter_partial[31:0]} + retired_instructions;

        next_clock_counter[31:0] = clock_counter_partial[31:0];
        next_clock_counter[63:32] = clock_counter[63:32] + clock_counter_partial[32];

        next_instruction_counter[31:0] = instruction_counter_partial[31:0];
        next_instruction_counter[63:32] = instruction_counter[63:32] + instruction_counter_partial[32];

        command_in = gecko_system_operation_t'(system_command.payload);

        consume = 'b1;

        next_system_result.payload.addr = command_in.reg_addr;
        next_system_result.payload.speculative = 'b0;
        next_system_result.payload.reg_status = command_in.reg_status;
        next_system_result.payload.jump_flag = command_in.jump_flag;
        next_system_result.payload.value = 'b0;

        if (ENABLE_PERFORMANCE_COUNTERS) begin
            case (command_in.csr)
            RISCV32I_CSR_CYCLE: next_system_result.payload.value = clock_counter[31:0];
            RISCV32I_CSR_TIME: next_system_result.payload.value = clock_counter[31:0];
            RISCV32I_CSR_INSTRET: next_system_result.payload.value = instruction_counter[31:0];
            RISCV32I_CSR_CYCLEH: next_system_result.payload.value = clock_counter[63:32];
            RISCV32I_CSR_TIMEH: next_system_result.payload.value = clock_counter[63:32];
            RISCV32I_CSR_INSTRETH: next_system_result.payload.value = instruction_counter[63:32];
            endcase
        end

        case (command_in.sys_op)
        RISCV32I_FUNCT3_SYS_ENV: begin // System Op
            produce = 'b0;
        end
        RISCV32I_FUNCT3_SYS_CSRRW: begin // Read Write
            produce = (command_in.reg_addr != 'b0); // Don't produce writeback to x0
        end
        RISCV32I_FUNCT3_SYS_CSRRS: begin // Read Set
            produce = (command_in.reg_addr != 'b0); // Don't produce writeback to x0
        end
        RISCV32I_FUNCT3_SYS_CSRRC: begin // Read Clear
            produce = (command_in.reg_addr != 'b0); // Don't produce writeback to x0
        end
        RISCV32I_FUNCT3_SYS_CSRRWI: begin // Read Write Imm
            produce = (command_in.reg_addr != 'b0); // Don't produce writeback to x0
        end
        RISCV32I_FUNCT3_SYS_CSRRSI: begin // Read Set Imm
            produce = (command_in.reg_addr != 'b0); // Don't produce writeback to x0
        end
        RISCV32I_FUNCT3_SYS_CSRRCI: begin // Read Clear Imm
            produce = (command_in.reg_addr != 'b0); // Don't produce writeback to x0
        end
        default: begin
            produce = 'b0;
        end
        endcase
    end

endmodule
