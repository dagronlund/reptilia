//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import riscv/riscv32i_pkg.sv
//!import riscv/riscv32m_pkg.sv
//!import riscv/riscv32f_pkg.sv
//!import gecko/gecko_pkg.sv
//!import gecko/gecko_decode_regfile.sv
//!import gecko/gecko_decode_speculative.sv
//!import gecko/gecko_decode_pkg.sv
//!import stream/stream_intf.sv
//!import mem/mem_intf.sv
//!import stream/stream_stage.sv
//!import mem/mem_combinational.sv
//!wrapper gecko/gecko_decode_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

/*
Decode State:
    RESET - Clearing all necessary register values coming out of reset
    NORMAL - Normal decode stage operations
    DEBUG - Inspect the internal state of the core through an external interface
    EXIT - An instruction has caused the core to stop running

Execute Saved Result:
    Flag for which register is currently is stored in the execute stage,
    should be x0 if no valid result exists.
*/
module gecko_decode
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import riscv32m_pkg::*;
    import riscv32f_pkg::*;
    import gecko_pkg::*;
    import gecko_decode_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter int NUM_FORWARDED = 0,
    parameter bit ENABLE_FLOAT = 0,
    parameter bit ENABLE_INTEGER_MATH = 0,
    parameter bit ENABLE_EXECUTE_SAVED = 1,
    parameter int NUM_FORWARDED_SAFE = NUM_FORWARDED == 0 ? 1 : NUM_FORWARDED
)(
    input wire clk, 
    input wire rst,

    mem_intf.in instruction_result,
    stream_intf.in instruction_command, // gecko_instruction_operation_t

    stream_intf.out system_command, // gecko_system_operation_t
    stream_intf.out execute_command, // gecko_execute_operation_t
    stream_intf.out float_command, // gecko_float_operation_t

    // Non-flow Controlled
    stream_intf.view jump_command, // gecko_jump_operation_t
    stream_intf.in writeback_result, // gecko_operation_t

    input gecko_forwarded_t [NUM_FORWARDED_SAFE-1:0] forwarded_results,

    output gecko_performance_stats_t performance_stats,

    output logic exit_flag,
    output logic error_flag
);

    typedef enum logic [1:0] {
        GECKO_DECODE_RESET,
        GECKO_DECODE_NORMAL,
        GECKO_DECODE_DEBUG,
        GECKO_DECODE_EXIT
    } state_t;

    typedef struct packed {
        logic               rs1_valid, rs2_valid;
        riscv32_reg_addr_t  rs1_addr,  rs2_addr;
        riscv32_reg_value_t rs1_value, rs2_value;
    } rs1_rs2_status_t;

    function automatic rs1_rs2_status_t get_forwarded_values(
        input rs1_rs2_status_t status,
        input gecko_forwarded_t [NUM_FORWARDED_SAFE-1:0] forwarded_results,
        input gecko_reg_status_t rs1_status_front_last, 
        input gecko_reg_status_t rs2_status_front_last
    );
        rs1_rs2_status_t status_next = status;

        // Find forwarded results
        for (int i = 0; i < NUM_FORWARDED; i++) begin
            // Use the forwarded result if it is valid and not mispredicted
            if (forwarded_results[i].valid && !forwarded_results[i].mispredicted) begin
                // Check forwarding for result of rs1
                if (forwarded_results[i].addr == status.rs1_addr &&
                        forwarded_results[i].reg_status == rs1_status_front_last) begin
                    status_next.rs1_value = forwarded_results[i].value;
                    status_next.rs1_valid = 'b1;
                end

                // Check forwarding for result of rs2
                if (forwarded_results[i].addr == status.rs2_addr &&
                        forwarded_results[i].reg_status == rs2_status_front_last) begin
                    status_next.rs2_value = forwarded_results[i].value;
                    status_next.rs2_valid = 'b1;
                end
            end
        end

        return status_next;
    endfunction

    typedef struct packed {
        logic flush_instruction;
        logic stall_control;
        logic stall_data;
    } instruction_status_t;

    function automatic instruction_status_t get_instruction_status(
        input state_t state,
        input riscv32_fields_t instruction_fields,
        input gecko_decode_operands_status_t operands_status,
        input rs1_rs2_status_t rs1_rs2_status,
        input logic mispredicted,
        input logic pc_updated,
        input logic speculating,
        input logic speculation_full
    );
        instruction_status_t status = '{default: 'b0};
        case (state)
        GECKO_DECODE_NORMAL: begin
            // Throw away instructions that were misfetched
            if (mispredicted && !pc_updated) begin
                status.flush_instruction = 'b1;
            // Wait if instruction registers are not ready yet
            end else if (!rs1_rs2_status.rs1_valid || !rs1_rs2_status.rs2_valid || !operands_status.rd_valid) begin
                status.stall_data = 'b1;
            // Only execute non-side-effect instructions while speculating
            end else if (speculating && is_instruction_system(instruction_fields)) begin
                status.stall_control = 'b1;
            // Only execute non-control flow while speculation queue is full
            end else if (speculation_full && is_opcode_control_flow(instruction_fields)) begin
                status.stall_control = 'b1;
            end
        end
        GECKO_DECODE_EXIT: begin
            status.flush_instruction = 'b1;
        end
        default: begin end
        endcase
        return status;
    endfunction

    stream_controller8_output_t stream_controller_result;
    logic consume_instruction /* verilator isolate_assignments*/;
    logic produce_system /* verilator isolate_assignments*/;
    logic produce_execute /* verilator isolate_assignments*/;
    logic produce_float /* verilator isolate_assignments*/;
    logic enable /* verilator isolate_assignments*/;

    stream_intf #(.T(gecko_system_operation_t)) next_system_command (.clk, .rst);
    stream_intf #(.T(gecko_execute_operation_t)) next_execute_command (.clk, .rst);
    stream_intf #(.T(gecko_float_operation_t)) next_float_command (.clk, .rst);

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(gecko_system_operation_t)
    ) system_operation_stream_stage_inst (
        .clk, .rst,
        .stream_in(next_system_command), .stream_out(system_command)
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(gecko_execute_operation_t)
    ) execute_operation_stream_stage_inst (
        .clk, .rst,
        .stream_in(next_execute_command), .stream_out(execute_command)
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(gecko_float_operation_t)
    ) float_operation_stream_stage_inst (
        .clk, .rst,
        .stream_in(next_float_command), .stream_out(float_command)
    );

    state_t state, next_state;
    logic next_error_flag /* verilator isolate_assignments*/;
    riscv32_reg_addr_t execute_saved, next_execute_saved;

    gecko_performance_stats_t performance_stats_next;

    logic [1:0] state_temp;
    always_comb state = state_t'(state_temp);

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic [1:0]),
        .RESET_VECTOR(GECKO_DECODE_RESET)
    ) decode_state_register_inst (
        .clk, .rst,
        .enable,
        .next(next_state),
        .value(state_temp)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(gecko_performance_stats_t),
        .RESET_VECTOR('b0)
    ) performance_stats_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(performance_stats_next),
        .value(performance_stats)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic),
        .RESET_VECTOR('b0)
    ) error_flag_register_inst (
        .clk, .rst,
        .enable,
        .next(next_error_flag),
        .value(error_flag)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(riscv32_reg_addr_t),
        .RESET_VECTOR('b0)
    ) execute_saved_register_inst (
        .clk, .rst,
        .enable,
        .next(next_execute_saved),
        .value(execute_saved)
    );

    gecko_instruction_operation_t instruction_op;
    gecko_jump_operation_t jump_cmd_in;
    gecko_operation_t writeback_in;
    always_comb instruction_op = gecko_instruction_operation_t'(instruction_command.payload);
    always_comb jump_cmd_in = gecko_jump_operation_t'(jump_command.payload);
    always_comb writeback_in = gecko_operation_t'(writeback_result.payload);

    riscv32_fields_t instruction_fields;
    always_comb instruction_fields = riscv32_get_fields(instruction_result.data);

    gecko_decode_opcode_status_t opcode_status;
    always_comb opcode_status = decode_opcode(instruction_fields, ENABLE_INTEGER_MATH, ENABLE_FLOAT);

    riscv32_reg_value_t rs1_value,      rs2_value;
    gecko_reg_status_t  rs1_status;
    gecko_reg_status_t                  rs2_status;

    logic               rd_read_enable, rd_write_enable, rd_write_value_enable;
    riscv32_reg_addr_t  rd_read_addr,   rd_write_addr;
    riscv32_reg_value_t                 rd_write_value;
    gecko_reg_status_t  rd_read_status /* verilator isolate_assignments*/;

    gecko_reg_status_t  rs1_status_front_last, rs2_status_front_last, rd_read_status_front;

    logic reset_done;

    gecko_decode_regfile #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY)
    ) regfile (
        .clk, 
        .rst,

        .rs1_addr(instruction_fields.rs1),
        .rs1_value,
        .rs1_status,
        .rs1_status_front_last,
        .rs2_addr(instruction_fields.rs2),
        .rs2_value,
        .rs2_status,
        .rs2_status_front_last,
        .rd_read_enable(rd_read_enable && enable),
        .rd_read_addr(instruction_fields.rd),
        .rd_read_status,
        .rd_read_status_front,
        .rd_write_enable,
        .rd_write_value_enable,
        .rd_write_addr,
        .rd_write_value,

        .reset_done
    );

    logic instruction_enable /* verilator isolate_assignments*/;
    logic instruction_branch_jump;

    gecko_jump_flag_t execute_flag;

    logic mispredicted /* verilator isolate_assignments*/;
    logic speculating /* verilator isolate_assignments*/;
    logic speculation_full /* verilator isolate_assignments*/;
    logic instruction_increment;

    gecko_decode_speculative #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY)
    ) speculator (
        .clk, 
        .rst,

        .instruction_enable(enable && instruction_enable),
        .instruction_branch_jump,
        .instruction_updated(instruction_op.pc_updated),

        .speculation_resolved(jump_command.valid),
        .speculation_mispredicted(jump_cmd_in.update_pc && !jump_cmd_in.mispredicted),

        .execute_flag,
        .mispredicted,
        .speculating,
        .speculation_full,
        .instruction_increment,

        .reset_done()
    );

    gecko_decode_operands_status_t operands_status;
    rs1_rs2_status_t rs1_rs2_status;
    instruction_status_t instruction_status;

    always_comb begin
        // Get the status of the current register file
        operands_status = gecko_decode_find_operand_status(
            instruction_fields,
            instruction_op.pc_updated,
            ENABLE_EXECUTE_SAVED ? execute_saved : 'b0,
            rd_read_status,
            rs1_status,
            rs2_status
        );
    end

    always_comb begin
        // Find any forwarded values if they exist
        rs1_rs2_status = get_forwarded_values(
            '{
                rs1_valid: operands_status.rs1_valid, rs2_valid: operands_status.rs2_valid,
                rs1_addr:  instruction_fields.rs1,    rs2_addr:  instruction_fields.rs2,
                rs1_value: rs1_value,                 rs2_value: rs2_value 
            },
            forwarded_results,
            rs1_status_front_last, 
            rs2_status_front_last
        );
    end

    always_comb begin
        instruction_status = get_instruction_status(
            state,
            instruction_fields,
            operands_status,
            rs1_rs2_status,
            mispredicted,
            instruction_op.pc_updated,
            speculating,
            speculation_full
        );
    end

    always_comb begin
        // Assign next values to defaults
        next_error_flag = opcode_status.error_flag;
        if (opcode_status.execute_flag) begin
            next_execute_saved = get_execute_writeback(riscv32_get_fields(instruction_result.data));
        end else begin
            next_execute_saved = 'b0;
        end

        // Determine various external flags
        exit_flag = (state == GECKO_DECODE_EXIT);

        // Build commands
        next_execute_command.payload = create_execute_op(
                riscv32_get_fields(instruction_result.data), 
                instruction_op,
                ENABLE_EXECUTE_SAVED ? execute_saved : 'b0,
                rs1_rs2_status.rs1_value, 
                rs1_rs2_status.rs2_value,
                rd_read_status_front,
                execute_flag
        );
        if (opcode_status.exit_flag) begin
            // Exit by jumping and halting the fetch stage
            next_execute_command.payload.halt = 'b1;
            next_execute_command.payload.op_type = GECKO_EXECUTE_TYPE_JUMP;
        end

        next_system_command.payload = create_system_op(
                riscv32_get_fields(instruction_result.data), 
                rs1_rs2_status.rs1_value, 
                rs1_rs2_status.rs2_value,
                rd_read_status_front,
                execute_flag
        );

        next_float_command.payload = create_float_op(
                riscv32_get_fields(instruction_result.data),  
                rs1_rs2_status.rs1_value, 
                rs1_rs2_status.rs2_value,
                rd_read_status_front,
                execute_flag
        );

        instruction_enable = !instruction_status.stall_data && 
                             !instruction_status.stall_control && 
                             !instruction_status.flush_instruction;
        instruction_branch_jump = is_opcode_control_flow(riscv32_get_fields(instruction_result.data));

        consume_instruction = !instruction_status.stall_data && 
                              !instruction_status.stall_control;
        produce_execute = 'b0;
        produce_system = 'b0;
        produce_float = 'b0;
        if (instruction_enable) begin
            if (opcode_status.exit_flag) begin
                produce_execute = 'b1;
            end else begin
                produce_execute = opcode_status.execute_flag;
                produce_system = opcode_status.system_flag;
                produce_float = opcode_status.float_flag;
            end
        end

        // Update state (RESET -> NORMAL -> EXIT)
        case (state)
        GECKO_DECODE_RESET:  next_state = (reset_done) ? GECKO_DECODE_NORMAL : state;
        GECKO_DECODE_NORMAL: next_state = (opcode_status.exit_flag) ? GECKO_DECODE_EXIT : state;
        GECKO_DECODE_EXIT:   next_state = state;
        default:             next_state = GECKO_DECODE_RESET;
        endcase

        stream_controller_result = stream_controller8(stream_controller8_input_t'{
            valid_input:  {6'b0, instruction_result.valid, instruction_command.valid},
            ready_output: {5'b0, next_system_command.ready, next_execute_command.ready, next_float_command.ready},
            consume: {6'b0, consume_instruction, consume_instruction},
            produce: {5'b0, produce_system, produce_execute, produce_float}
        });
        {instruction_result.ready, instruction_command.ready} = stream_controller_result.ready_input[1:0];
        {next_system_command.valid, next_execute_command.valid, next_float_command.valid} = stream_controller_result.valid_output[2:0];
        enable = stream_controller_result.enable && instruction_enable;

        // Update front register status
        rd_read_enable = get_instruction_writeback(riscv32_get_fields(instruction_result.data)) != 'b0;
        // Update register status regardless of throwing away speculation
        rd_write_enable = writeback_result.valid && writeback_result.ready;
        // Throw away writes to x0 and mispredicted results
        rd_write_value_enable = rd_write_enable && 
                                writeback_in.addr != 'b0 &&
                                !writeback_in.mispredicted;
        rd_write_addr         = writeback_in.addr;
        rd_write_value        = writeback_in.value;
        writeback_result.ready = 'b1;

        // Construct performance stats
        performance_stats_next = '{
            instruction_completed: instruction_increment,
            default: 'b0
        };
        if (stream_controller_result.enable) begin
            performance_stats_next.instruction_mispredicted = instruction_status.flush_instruction;
            performance_stats_next.instruction_data_stalled = instruction_status.stall_data;
            performance_stats_next.instruction_control_stalled = instruction_status.stall_control;
        end else if (!instruction_result.valid || !instruction_command.valid) begin
            performance_stats_next.frontend_stalled = 'b1;
        end else begin
            performance_stats_next.backend_stalled = 'b1;
        end

    end

    logic        debug_jump_valid /*verilator public*/;
    logic        debug_register_write /*verilator public*/;
    logic [4:0]  debug_register_addr /*verilator public*/;
    logic [31:0] debug_jump_address /*verilator public*/;
    logic [31:0] debug_register_data /*verilator public*/;

    always_comb debug_jump_valid = jump_command.valid && 
                                  !jump_cmd_in.mispredicted && 
                                  (jump_cmd_in.branched || jump_cmd_in.jumped);
    always_comb debug_jump_address = jump_cmd_in.actual_next_pc;
    always_comb debug_register_write = rd_write_value_enable;
    always_comb debug_register_addr = writeback_in.addr;
    always_comb debug_register_data = writeback_in.value;

endmodule
