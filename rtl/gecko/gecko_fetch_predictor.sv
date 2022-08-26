//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import riscv/riscv32i_pkg.sv
//!import gecko/gecko_pkg.sv
//!import stream/stream_intf.sv
//!import std/std_register.sv
//!import mem/mem_combinational.sv
//!wrapper gecko/gecko_fetch_predictor_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

// The branch predictor can either be disabled or use in simple, global, or 
// local modes.
module gecko_fetch_predictor
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import gecko_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter gecko_predictor_config_t PREDICTOR_CONFIG = gecko_get_basic_predictor_config()
)(
    input wire clk, 
    input wire rst,

    input gecko_pc_t pc,

    stream_intf.view jump_command, // gecko_jump_operation_t

    output logic predictor_valid, 
    output logic predictor_taken,
    output gecko_pc_t predictor_prediction,
    output gecko_predictor_history_t predictor_history,

    output logic reset_done
);

    // Type Definitions --------------------------------------------------------

    function automatic int get_history_table_addr_width(
            input gecko_predictor_mode_t prediction_type
    );
        unique case (prediction_type)
        GECKO_PREDICTOR_MODE_NONE: return PREDICTOR_CONFIG.target_addr_width;
        GECKO_PREDICTOR_MODE_SIMPLE: return PREDICTOR_CONFIG.target_addr_width;
        GECKO_PREDICTOR_MODE_GLOBAL: return PREDICTOR_CONFIG.history_width;
        GECKO_PREDICTOR_MODE_LOCAL: return PREDICTOR_CONFIG.history_width;
        endcase
    endfunction

    localparam int BRANCH_TAG_WIDTH = $bits(gecko_pc_t) - PREDICTOR_CONFIG.target_addr_width - 2;

    typedef logic [PREDICTOR_CONFIG.target_addr_width-1:0] target_addr_t;
    typedef logic [BRANCH_TAG_WIDTH-1:0] tag_addr_t;

    typedef logic [PREDICTOR_CONFIG.history_width-1:0] history_t;
    typedef logic [get_history_table_addr_width(PREDICTOR_CONFIG.mode)-1:0] history_addr_t;
    typedef logic [PREDICTOR_CONFIG.local_addr_width-1:0] local_history_addr_t;

    typedef struct packed {
        logic valid;
        gecko_pc_t predicted_next;
        tag_addr_t tag;
        logic jump_instruction;
    } gecko_fetch_table_entry_t;

    function automatic target_addr_t get_pc_target(input gecko_pc_t pc);
        return pc[(PREDICTOR_CONFIG.target_addr_width+2-1):2];
    endfunction

    function automatic tag_addr_t get_pc_tag(input gecko_pc_t pc);
        return pc[31:PREDICTOR_CONFIG.target_addr_width+2];
    endfunction

    function automatic local_history_addr_t get_pc_local_addr(input gecko_pc_t pc);
        return pc[(PREDICTOR_CONFIG.local_addr_width+2-1):2];
    endfunction

    logic branch_table_write_enable;
    target_addr_t branch_table_write_addr /* verilator isolate_assignments*/;
    gecko_fetch_table_entry_t branch_table_write_data;

    // target_addr_t branch_table_read_addr /* verilator isolate_assignments*/;
    gecko_fetch_table_entry_t branch_table_read_data /* verilator isolate_assignments*/;

    mem_combinational #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .DATA_WIDTH($bits(gecko_fetch_table_entry_t)),
        .ADDR_WIDTH(PREDICTOR_CONFIG.target_addr_width),
        .READ_PORTS(1),
        .AUTO_RESET(1)
    ) branch_target_table_inst (
        .clk, .rst,

        .write_enable(branch_table_write_enable),
        .write_addr(branch_table_write_addr),
        .write_data_in(branch_table_write_data),
        .write_data_out(),

        .read_addr({get_pc_target(pc)}),
        .read_data_out({branch_table_read_data}),

        .reset_done
    );

    history_t current_global_history, next_global_history;

    // local_history_addr_t local_history_update_addr  /* verilator isolate_assignments*/;
    history_t local_history_update_read_data, local_history_update_write_data;
    history_t local_history_result;

    history_addr_t history_table_update_addr /* verilator isolate_assignments*/;
    history_addr_t history_table_addr /* verilator isolate_assignments*/;
    gecko_predictor_history_t history_table_update_data, history_table_data;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(history_t),
        .RESET_VECTOR('b0)
    ) global_history_register_inst (
        .clk, .rst,
        .enable(branch_table_write_enable),
        .next(next_global_history),
        .value(current_global_history)
    );

    mem_combinational #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .DATA_WIDTH($bits(history_t)),
        .ADDR_WIDTH(PREDICTOR_CONFIG.local_addr_width),
        .READ_PORTS(1)
    ) local_history_table_inst (
        .clk, .rst,

        .write_enable(branch_table_write_enable),
        .write_addr(get_pc_local_addr(jump_command.payload.current_pc)),
        .write_data_in(local_history_update_write_data),
        .write_data_out(local_history_update_read_data),

        .read_addr({get_pc_local_addr(pc)}),
        .read_data_out({local_history_result}),

        .reset_done()
    );

    mem_combinational #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .DATA_WIDTH($bits(gecko_predictor_history_t)),
        .ADDR_WIDTH($bits(history_addr_t)),
        .READ_PORTS(1)
    ) branch_history_table_inst (
        .clk, .rst,

        .write_enable(branch_table_write_enable),
        .write_addr(history_table_update_addr),
        .write_data_in(history_table_update_data),
        .write_data_out(),

        .read_addr({history_table_addr}),
        .read_data_out({history_table_data}),

        .reset_done()
    );

    always_comb begin
        unique case (PREDICTOR_CONFIG.mode)
        GECKO_PREDICTOR_MODE_NONE:   history_table_addr = 'b0;
        GECKO_PREDICTOR_MODE_SIMPLE: history_table_addr = get_pc_target(pc);
        GECKO_PREDICTOR_MODE_GLOBAL: history_table_addr = current_global_history;
        GECKO_PREDICTOR_MODE_LOCAL:  history_table_addr = local_history_result;
        endcase
    end

    always_comb begin
        // Get branch predictions ----------------------------------------------

        // Determine if entry exists in branch table and has matching address
        predictor_valid = branch_table_read_data.valid && 
                                (branch_table_read_data.tag == get_pc_tag(pc));
        predictor_taken = gecko_predictor_is_taken(history_table_data) || 
                                 branch_table_read_data.jump_instruction;
        predictor_prediction = branch_table_read_data.predicted_next;
        predictor_history = history_table_data;

        // Update branch predictions -------------------------------------------

        // Update branch target table from jump commands (always accepts)
        branch_table_write_enable = jump_command.valid && !jump_command.payload.mispredicted;
        branch_table_write_addr = get_pc_target(jump_command.payload.current_pc);
        branch_table_write_data = '{
            valid: 'b1,
            predicted_next: jump_command.payload.actual_next_pc,
            tag: get_pc_tag(jump_command.payload.current_pc),
            jump_instruction: jump_command.payload.jumped
        };

        // Update global history
        next_global_history = {
                current_global_history[$bits(history_t)-2:0], 
                jump_command.payload.branched};

        // Update local history table
        local_history_update_write_data = {
                local_history_update_read_data[$bits(history_t)-2:0],
                jump_command.payload.branched};

        // Update history table
        unique case (PREDICTOR_CONFIG.mode)
        GECKO_PREDICTOR_MODE_NONE, 
        GECKO_PREDICTOR_MODE_SIMPLE: history_table_update_addr = branch_table_write_addr;
        GECKO_PREDICTOR_MODE_GLOBAL: history_table_update_addr = current_global_history;
        GECKO_PREDICTOR_MODE_LOCAL:  history_table_update_addr = local_history_update_read_data;
        endcase
        // I have some questions about two adjacent jumps stepping on each other
        // but this is the simplest version to implement
        history_table_update_data = gecko_predictor_update_history(
                jump_command.payload.prediction.history, 
                jump_command.payload.branched);
    end

endmodule
