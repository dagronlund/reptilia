//!import std/std_pkg.sv
//!import std/std_register.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import gecko/gecko_pkg.sv

// Speculation is handled with a small table and front/rear counters used for
// indexing into that table. The front counter is incremented when a branch/jump
// instruction is encountered, and the rear counter when that branch is 
// resolved, either having been predicted correctly or incorrectly. While the 
// counters are not equal no branch/jump instructions execute, and all other 
// instructions are marked as speculative. When a branch is resolved the rear 
// counter increments and the mispredicted flag is set for that entry. When a 
// writeback happens, the front counter with that writeback is used to lookup if
// that writeback was mispredicted.

// The instruction count table is only ever written to by the front counter and
// the mispredicted flag table is only ever written to by the rear counter.
module gecko_decode_speculative
    import std_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import gecko_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter int              COUNTER_WIDTH = 2
)(
    input wire clk, 
    input wire rst,

    // From decode
    input  wire  instruction_enable,
    input  wire  instruction_branch_jump,
    input  wire  instruction_updated,

    // From execute
    input  wire  speculation_resolved,
    input  wire  speculation_mispredicted,

    output logic mispredicted,
    output logic speculating,
    output logic speculation_full,
    output logic instruction_increment,

    output gecko_jump_flag_t execute_flag,

    output logic reset_done
);

    localparam int HISTORY_DEPTH = 1 << $bits(gecko_jump_flag_t);
    typedef logic [COUNTER_WIDTH-1:0] counter_t;
    typedef counter_t [HISTORY_DEPTH-1:0] counter_table_t;

    // Track speculation status
    gecko_jump_flag_t front_flag, rear_flag;
    gecko_jump_flag_t front_flag_next, rear_flag_next;
    logic mispredicted_next;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(gecko_jump_flag_t),
        .RESET_VECTOR('b0)
    ) front_flag_register_inst (
        .clk, .rst,
        .enable(instruction_enable),
        .next(front_flag_next),
        .value(front_flag)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(gecko_jump_flag_t),
        .RESET_VECTOR('b0)
    ) rear_flag_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(rear_flag_next),
        .value(rear_flag)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic),
        .RESET_VECTOR('b0)
    ) mispredicted_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(mispredicted_next),
        .value(mispredicted)
    );

    // Track instruction counts
    counter_table_t counter_table, counter_table_next;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(counter_table_t),
        .RESET_VECTOR('b0)
    ) counter_table_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(counter_table_next),
        .value(counter_table)
    );

    logic [COUNTER_WIDTH:0] counter, counter_next;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic [COUNTER_WIDTH:0]),
        .RESET_VECTOR('b0)
    ) counter_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(counter_next),
        .value(counter)
    );

    logic instruction_increment_next;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic),
        .RESET_VECTOR('b0)
    ) instruction_increment_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(instruction_increment_next),
        .value(instruction_increment)
    );

    always_comb begin
        // Temporarily increment execute flag if the instruction stream updated
        // to reduce a cycle of waiting
        execute_flag = front_flag + (instruction_updated ? 'b1 : 'b0);

        // Indicate if the current instructions are mispredicted
        if (speculation_resolved && speculation_mispredicted) begin
            mispredicted_next = 'b1;
        end else if (instruction_enable && instruction_updated) begin
            mispredicted_next = 'b0;
        end else begin
            mispredicted_next = mispredicted;
        end

        // Increment front flag once each for a branch/jump instruction or when
        // given an updated instruction stream from an earlier branch/jump
        front_flag_next = front_flag;
        front_flag_next += instruction_branch_jump ? 'b1 : 'b0;
        front_flag_next += instruction_updated ? 'b1 : 'b0;

        // Increment rear flag once each for a speculation that was resolved or
        // when the instruction stream updates
        rear_flag_next = rear_flag;
        rear_flag_next += speculation_resolved ? 'b1 : 'b0;
        rear_flag_next += (instruction_enable && instruction_updated) ? 'b1 : 'b0;

        speculating      = front_flag != rear_flag;
        speculation_full = ((front_flag + 'b1) == rear_flag);

        // Determine how many instructions have actually been executed
        counter_table_next = counter_table;
        counter_next = counter;
        counter_table_next[front_flag] += (speculating && instruction_enable) ? 'b1 : 'b0;
        counter_next += (!speculating && instruction_enable) ? 'b1 : 'b0;
        counter_next -= (counter != 0) ? 'b1 : 'b0;
        if (speculation_resolved) begin
            counter_table_next[rear_flag] = 'b0;
            if (!speculation_mispredicted) begin
                counter_next += counter_table[rear_flag];
            end
        end
        if (instruction_enable && instruction_updated) begin
            counter_table_next[rear_flag + 'b1] = 'b0;
        end
        instruction_increment_next = counter != 0;
    end

endmodule
