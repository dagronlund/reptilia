//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import riscv/riscv32i_pkg.sv
//!import gecko/gecko_pkg.sv
//!import stream/stream_intf.sv
//!import mem/mem_intf.sv
//!import std/std_register.sv
//!import stream/stream_stage.sv
//!import mem/mem_stage.sv
//!import mem/mem_combinational.sv
//!import gecko/gecko_fetch_predictor.sv
//!wrapper gecko/gecko_fetch_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

// The fetch stage is responsible for generating a sequence of program counters
// and updating the sequence when requested. This sequence can either use a
// simple incrementing counter, and use the result of an embedded branch
// predictor.
module gecko_fetch
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import gecko_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    
    parameter stream_pipeline_mode_t   PIPELINE_MODE = STREAM_PIPELINE_MODE_TRANSPARENT,
    parameter gecko_pc_t               START_ADDR = 'b0,
    parameter gecko_predictor_config_t PREDICTOR_CONFIG = gecko_get_basic_predictor_config()
)(
    input wire clk, 
    input wire rst,

    stream_intf.view jump_command, // gecko_jump_operation_t

    stream_intf.out instruction_command, // gecko_instruction_operation_t
    mem_intf.out instruction_request
);

    // Stream Logic ------------------------------------------------------------

    stream_controller8_output_t stream_controller_result;
    logic enable;
    logic produce;

    stream_intf #(.T(gecko_instruction_operation_t)) next_instruction_command (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) next_instruction_request (.clk, .rst);

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(gecko_instruction_operation_t)
    ) instruction_command_stage_inst (
        .clk, .rst,
        .stream_in(next_instruction_command), 
        .stream_out(instruction_command)
    );

    mem_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE)
    ) instruction_request_stage_inst (
        .clk, .rst,
        .mem_in(next_instruction_request), 
        .mem_in_meta('b0),
        .mem_out(instruction_request),
        .mem_out_meta()
    );

    // State Logic -------------------------------------------------------------

    logic branch_table_reset_done;

    gecko_pc_t pc, pc_next;
    logic pc_updated, pc_updated_next;
    logic halt_flag;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(gecko_pc_t),
        .RESET_VECTOR(START_ADDR)
    ) pc_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(pc_next),
        .value(pc)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic),
        .RESET_VECTOR('b0)
    ) pc_updated_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(pc_updated_next),
        .value(pc_updated)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic),
        .RESET_VECTOR('b0)
    ) halt_flag_register_inst (
        .clk, .rst,
        .enable(jump_command.valid && !jump_command.payload.mispredicted),
        .next(jump_command.payload.halt || halt_flag),
        .value(halt_flag)
    );

    logic predictor_valid;
    logic predictor_taken;
    gecko_pc_t predictor_prediction;
    gecko_predictor_history_t predictor_history;

    gecko_fetch_predictor #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .PREDICTOR_CONFIG(PREDICTOR_CONFIG)
    ) predictor (
        .clk, 
        .rst,
        .pc,
        .jump_command,
        .predictor_valid, 
        .predictor_taken,
        .predictor_prediction,
        .predictor_history,
        .reset_done(branch_table_reset_done)
    );

    always_comb begin
        produce = !halt_flag && branch_table_reset_done;

        stream_controller_result = stream_controller8(stream_controller8_input_t'{
            valid_input:  {7'b0, 1'b1},
            ready_output: {6'b0, next_instruction_command.ready, next_instruction_request.ready},
            consume: {7'b0, 1'b1},
            produce: {6'b0, produce, produce}
        });
        {next_instruction_command.valid, next_instruction_request.valid} = stream_controller_result.valid_output[1:0];
        enable = stream_controller_result.enable;

        pc_next = pc;
        pc_updated_next = pc_updated;

        // Update pc and pc_updated if the fetch state is enabled
        if (produce && enable) begin
            // Take branch if a prediction target exists and we are predicted to take it
            if (PREDICTOR_CONFIG.mode != GECKO_PREDICTOR_MODE_NONE && 
                    predictor_valid && predictor_taken) begin
                pc_next = predictor_prediction;
            end else begin
                pc_next = pc + 'd4;
            end
            pc_updated_next = 'b0;
        end

        // Override pc_next decision if a jump command comes in
        if (jump_command.valid && jump_command.payload.update_pc && 
                                 !jump_command.payload.mispredicted) begin
            pc_next = jump_command.payload.actual_next_pc;
            pc_updated_next = 'b1;
        end

        // Pass outputs to memory and command streams
        next_instruction_command.payload = '{
            pc: pc,
            next_pc: pc_next,
            pc_updated: pc_updated,
            prediction: '{
                miss: !predictor_valid, // TODO: Consider removing this flag, it is not used
                history: predictor_history
            }
        };

        next_instruction_request.read_enable = 'b1;
        next_instruction_request.write_enable = 'b0;
        next_instruction_request.addr = pc;
        next_instruction_request.data = 'b0;
    end

endmodule
