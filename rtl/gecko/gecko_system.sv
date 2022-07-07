//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import riscv/riscv32i_pkg.sv
//!import gecko/gecko_pkg.sv
//!import stream/stream_intf.sv
//!import std/std_register.sv
//!import stream/stream_stage.sv
//!import stream/stream_controller.sv
//!wrapper gecko/gecko_system_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

/*
This module contains all the basic RISC-V performance counters, plus support for 
limited (custom) timer interrupts starting at 0xCA0. Right now those timers are 
(two-ish) general purpose counter timers that can be used for a normal timer or 
as a watchdog timer. If two or more timers go off at the same time the lowest 
number timer address will be the one jumped to, so in most situations timer zero
should be used for a watchdog if the system needs one. When interrupts are
encountered they cause the processor to jump to the vector table, which is a
configurable memory base address, and every timer is assigned an entry in the
vector table.

VECTOR_TABLE + (0 to 15 words): Reserved
VECTOR_TABLE + (16 to 31 words): Timers 0 through n

The enable register is set to one in order to start the timer, and can be 
toggled to reset the timer (ideally use the status/reset register). When the 
timer does expire and the vector table is jumped to, the timer will change the 
enable  bit to zero. This is to prevent the user from accidentally creating a 
timer that  triggers every couple cycles or so and prevents any user code from 
ever turning it off.

Reading from the status register will show if the timer has been triggered in 
bit zero. This is only really useful if a lower priority timer was triggered and 
the program wants to see if any other timers went off at the same time. Writing 
to the status register will reset the timer counter to the duration last written
to the duration register. This is most useful in the case of a watchdog timer
where the timer must be reset before the watchdog duration expires. Resetting a
timer that is not currently enabled will have no effect.

The duration register when written to will change the default duration for the 
timer when it is reset, but will not change the current countdown until such a 
reset occurs. Likewise reading from the duration register will report the 
current countdown of the timer and not the duration last written. 

The return address register is read-only and contains the program counter of the
instruction that was going to be executed if the counter interrupt did not
occur. The interrupt handler when it is complete should restore the normal
program registers before then jumping to this address. In order to not pollute
the registers once they have been restored, a special ECALL instruction can be
used to jump directly to this address.

0xCA0: Timer0 Enable (1-bit)
0xCA1: Timer0 Status/Reset (1-bit)
0xCA2: Timer0 Duration (32-bits)
0xCA3: Timer0 Return Address (32-bits)
...

*/
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
    parameter bit ENABLE_PERFORMANCE_COUNTERS = 1
)(
    input wire clk, 
    input wire rst,
    input gecko_retired_count_t retired_instructions,
    stream_intf.in system_command, // gecko_system_operation_t
    stream_intf.out system_result // gecko_operation_t
);

    // TODO: Use different counters for RDCYCLE and RDTIME to support processor pausing
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
        next_instruction_counter_partial = {1'b0, instruction_counter_partial[31:0]} + {28'b0, retired_instructions};

        next_clock_counter[31:0] = clock_counter_partial[31:0];
        next_clock_counter[63:32] = clock_counter[63:32] + {31'b0, clock_counter_partial[32]};

        next_instruction_counter[31:0] = instruction_counter_partial[31:0];
        next_instruction_counter[63:32] = instruction_counter[63:32] + {31'b0, instruction_counter_partial[32]};

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
            default: begin end
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
