//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import riscv/riscv32i_pkg.sv
//!import riscv/riscv32m_pkg.sv
//!import riscv/riscv32f_pkg.sv
//!import gecko/gecko_pkg.sv
//!import gecko/gecko_decode_pkg.sv
//!import stream/stream_intf.sv
//!import mem/mem_intf.sv
//!import std/std_counter_split.sv
//!import stream/stream_stage.sv
//!import mem/mem_combinational.sv
//!wrapper gecko/gecko_decode_wrapper.sv


/////!import stream/stream_controller.sv

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

Jump Flag: (Configurable Width)
    A counter describing which branch epoch the decode stage thinks it is on, 
    this is incremented when branches are resolved. Incoming instructions that 
    do not match the current jump flag are thrown out.

Speculative Flag (Front/Rear): (Configurable Width)
    Two counters that keep track of which speculative counter is currently
    correct. The rear counter is incremented whenever a branch is resolved,
    and the front counter whenever a branch instruction is decoded.

Speculative Status Table:
    A table of counters and mispredicted flags that indicate how many
    instructions have been decoded speculatively and if those instructions
    where executed incorrectly and their writeback results should be thrown
    out. Only instructions with register-file only side-effects (no system or
    memory instructions) are allowed to be decoded while speculating.
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
    parameter bit ENABLE_PRINT = 1,
    parameter bit ENABLE_FLOAT = 0,
    parameter bit ENABLE_INTEGER_MATH = 0
)(
    input wire clk, 
    input wire rst,

    mem_intf.in instruction_result,
    stream_intf.in instruction_command, // gecko_instruction_operation_t

    stream_intf.out system_command, // gecko_system_operation_t
    stream_intf.out execute_command, // gecko_execute_operation_t
    stream_intf.out float_command, // gecko_float_operation_t
    stream_intf.out ecall_command, // gecko_ecall_operation_t

    // Non-flow Controlled
    stream_intf.view jump_command, // gecko_jump_operation_t
    stream_intf.in writeback_result, // gecko_operation_t

    // Vivado does not like zero-width arrays
    input gecko_forwarded_t [(NUM_FORWARDED == 0 ? 0 : (NUM_FORWARDED - 1)):0] forwarded_results,

    output gecko_retired_count_t retired_instructions,

    output logic exit_flag,
    output logic [7:0] exit_code
);

    localparam GECKO_REG_STATUS_WIDTH = $size(gecko_reg_status_t);
    localparam NUM_SPECULATIVE_COUNTERS = 1 << $bits(gecko_jump_flag_t);

    typedef enum logic [1:0] {
        GECKO_DECODE_RESET,
        GECKO_DECODE_NORMAL,
        GECKO_DECODE_DEBUG,
        GECKO_DECODE_EXIT
    } gecko_decode_state_t;

    typedef struct packed {
        logic mispredicted;
        gecko_speculative_count_t count;
    } gecko_speculative_entry_t;

    typedef gecko_speculative_entry_t [NUM_SPECULATIVE_COUNTERS-1:0] gecko_speculative_status_t;

    typedef struct packed {
        logic rs1_valid, rs2_valid;
        riscv32_reg_value_t rs1_value, rs2_value;
    } gecko_decode_forwarded_search_t;

    function automatic gecko_decode_forwarded_search_t get_forwarded_values(
            input riscv32_fields_t instruction_fields,
            input gecko_forwarded_t [(NUM_FORWARDED == 0 ? 0 : (NUM_FORWARDED - 1)):0] forwarded_results,
            gecko_reg_status_t front_status_rs1, front_status_rs2,
            input gecko_speculative_status_t speculative_status,
            input logic during_speculation
    );
        gecko_decode_forwarded_search_t search = '{default: 'b0};
        gecko_reg_status_t forwarded_status_plus;

        // Find forwarded results
        for (int i = 0; i < NUM_FORWARDED; i++) begin
            forwarded_status_plus = forwarded_results[i].reg_status + 'b1;

            if (forwarded_results[i].valid) begin
                // Take the forward if it is not speculative itself, or if we are not currently
                // speculating and the last speculation this forward belongs to was not mispredicted
                if (!forwarded_results[i].speculative || (!during_speculation && 
                        !speculative_status[forwarded_results[i].jump_flag].mispredicted)) begin

                    // Check forwarding for result of rs1
                    if (forwarded_results[i].addr == instruction_fields.rs1 &&
                            forwarded_status_plus == front_status_rs1) begin
                        search.rs1_value = forwarded_results[i].value;
                        search.rs1_valid = 'b1;
                    end

                    // Check forwarding for result of rs2
                    if (forwarded_results[i].addr == instruction_fields.rs2 &&
                            forwarded_status_plus == front_status_rs2) begin
                        search.rs2_value = forwarded_results[i].value;
                        search.rs2_valid = 'b1;
                    end
                end
            end
        end

        return search;
    endfunction

    stream_controller8_output_t stream_controller_result;
    logic consume_instruction;
    logic produce_system;
    logic produce_execute;
    logic produce_print;
    logic produce_float;
    logic enable;

    stream_intf #(.T(gecko_system_operation_t)) next_system_command (.clk, .rst);
    stream_intf #(.T(gecko_execute_operation_t)) next_execute_command (.clk, .rst);
    stream_intf #(.T(gecko_float_operation_t)) next_float_command (.clk, .rst);
    stream_intf #(.T(gecko_ecall_operation_t)) next_ecall_command (.clk, .rst);

    // stream_controller #(
    //     .NUM_INPUTS(2),
    //     .NUM_OUTPUTS(4)
    // ) stream_controller_inst (
    //     .clk, .rst,

    //     .valid_input({instruction_result.valid, instruction_command.valid}),
    //     .ready_input({instruction_result.ready, instruction_command.ready}),

    //     .valid_output({next_system_command.valid, next_execute_command.valid, next_ecall_command.valid, next_float_command.valid}),
    //     .ready_output({next_system_command.ready, next_execute_command.ready, next_ecall_command.ready, next_float_command.ready}),

    //     .consume({consume_instruction, consume_instruction}), 
    //     .produce({produce_system, produce_execute, produce_print, produce_float}),
    //     .enable
    // );

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
        .T(gecko_ecall_operation_t)
    ) ecall_command_stream_stage_inst (
        .clk, .rst,
        .stream_in(next_ecall_command), .stream_out(ecall_command)
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(gecko_float_operation_t)
    ) float_operation_stream_stage_inst (
        .clk, .rst,
        .stream_in(next_float_command), .stream_out(float_command)
    );

    logic [7:0] next_exit_code;
    gecko_decode_state_t state, next_state;
    riscv32_reg_addr_t reset_counter;
    logic enable_jump_flag;
    gecko_jump_flag_t jump_flag;
    logic clear_speculative_retired_counter;
    gecko_speculative_count_t retired_instructions_speculative, next_retired_instructions_speculative;
    logic clear_execute_saved;
    riscv32_reg_addr_t execute_saved, next_execute_saved;

    logic speculative_status_decrement_enable;
    logic speculative_status_mispredicted_enable;
    gecko_speculative_status_t speculative_status, next_speculative_status;
    gecko_retired_count_t next_retired_instructions;

    logic [1:0] state_temp; // Vivado sux
    always_comb state = gecko_decode_state_t'(state_temp);

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

    logic enable_speculative_flag_front /* verilator isolate_assignments*/;
    logic enable_speculative_flag_rear /* verilator isolate_assignments*/;
    gecko_jump_flag_t current_speculative_flag_front, current_speculative_flag_rear;

    std_counter_split #(
        .CLOCK_INFO(CLOCK_INFO),
        .WIDTH($bits(gecko_jump_flag_t)),
        .RESET_VECTOR('b0)
    ) speculative_flag_counter_register_inst (
        .clk, .rst,
        .increment_enable(enable && enable_speculative_flag_front),
        .decrement_enable(enable_speculative_flag_rear),
        .front_value(current_speculative_flag_front),
        .rear_value(current_speculative_flag_rear),
        .value()
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(gecko_speculative_status_t),
        .RESET_VECTOR('b0)
    ) speculative_status_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(next_speculative_status),
        .value(speculative_status)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(gecko_retired_count_t),
        .RESET_VECTOR('b0)
    ) retired_instructions_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(next_retired_instructions),
        .value(retired_instructions)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(riscv32_reg_addr_t),
        .RESET_VECTOR('b0)
    ) reset_counter_register_inst (
        .clk, .rst,
        .enable(state == GECKO_DECODE_RESET),
        .next(reset_counter + 'b1),
        .value(reset_counter)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic [7:0]),
        .RESET_VECTOR('b0)
    ) exit_code_register_inst (
        .clk, .rst,
        .enable,
        .next(next_exit_code),
        .value(exit_code)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(gecko_jump_flag_t),
        .RESET_VECTOR('b0)
    ) jump_flag_register_inst (
        .clk, .rst,
        .enable(enable_jump_flag),
        .next(jump_flag + 'b1),
        .value(jump_flag)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(gecko_speculative_count_t),
        .RESET_VECTOR('b0)
    ) speculative_retired_counter_register_inst (
        .clk, .rst,
        .enable(enable || clear_speculative_retired_counter),
        .next(clear_speculative_retired_counter ? 'b0 : next_retired_instructions_speculative),
        .value(retired_instructions_speculative)
    );

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(riscv32_reg_addr_t),
        .RESET_VECTOR('b0)
    ) execute_saved_register_inst (
        .clk, .rst,
        .enable(enable || clear_execute_saved),
        .next(clear_execute_saved ? 'b0 : next_execute_saved),
        .value(execute_saved)
    );

    logic               register_write_enable;
    riscv32_reg_addr_t  register_write_addr;
    riscv32_reg_value_t register_write_value;
    riscv32_reg_addr_t  register_read_addr0 /* verilator isolate_assignments*/;
    riscv32_reg_addr_t  register_read_addr1 /* verilator isolate_assignments*/;
    riscv32_reg_value_t register_read_value0;
    riscv32_reg_value_t register_read_value1;

    // Register File
    mem_combinational #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .DATA_WIDTH($size(riscv32_reg_value_t)),
        .ADDR_WIDTH($size(riscv32_reg_addr_t)),
        .READ_PORTS(2)
    ) register_file_inst (
        .clk, .rst,

        // Always write to all bits in register
        .write_enable(register_write_enable),
        .write_addr(register_write_addr),
        .write_data_in(register_write_value),
        .write_data_out(),

        .read_addr({register_read_addr0, register_read_addr1}),
        .read_data_out({register_read_value0, register_read_value1}),

        .reset_done()
    );

    logic front_status_rd_write_enable, rear_status_writeback_enable;

    riscv32_reg_addr_t reg_status_rd_addr /* verilator isolate_assignments*/;
    riscv32_reg_addr_t reg_status_rs1_addr /* verilator isolate_assignments*/;
    riscv32_reg_addr_t reg_status_rs2_addr /* verilator isolate_assignments*/;
    gecko_reg_status_t front_status_rd, front_status_rs1, front_status_rs2;
    gecko_reg_status_t rear_status_rd, rear_status_rs1, rear_status_rs2;

    // Register file status from decode alone
    mem_combinational #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .DATA_WIDTH(GECKO_REG_STATUS_WIDTH),
        .ADDR_WIDTH($size(riscv32_reg_addr_t)),
        .READ_PORTS(2)
    ) register_status_front_inst (
        .clk, .rst,

        // Always write to all bits in register, gate with state clock enable
        .write_enable(front_status_rd_write_enable && enable),
        .write_addr(reg_status_rd_addr),
        // Simply increment the status when written to
        .write_data_in((state == GECKO_DECODE_RESET) ? 'b0 : (front_status_rd + 'b1)),
        .write_data_out(front_status_rd),

        .read_addr({reg_status_rs1_addr, reg_status_rs2_addr}),
        .read_data_out({front_status_rs1, front_status_rs2}),

        .reset_done()
    );

    riscv32_reg_addr_t rear_status_writeback_addr /* verilator isolate_assignments*/;
    gecko_reg_status_t rear_status_writeback;

    // Register file status from writebacks
    mem_combinational #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .DATA_WIDTH(GECKO_REG_STATUS_WIDTH),
        .ADDR_WIDTH($size(riscv32_reg_addr_t)),
        .READ_PORTS(3)
    ) register_status_rear_inst (
        .clk, .rst,

        // Always write to all bits in register, gate with state clock enable
        .write_enable(rear_status_writeback_enable),
        .write_addr(rear_status_writeback_addr),
        // Simply increment the status when written to
        .write_data_in((state == GECKO_DECODE_RESET) ? 'b0 : (rear_status_writeback + 'b1)),
        .write_data_out(rear_status_writeback),

        .read_addr({reg_status_rd_addr, reg_status_rs1_addr, reg_status_rs2_addr}),
        .read_data_out({rear_status_rd, rear_status_rs1, rear_status_rs2}),

        .reset_done()
    );

    riscv32_fields_t instruction_fields;
    gecko_decode_opcode_status_t opcode_status;

    always_comb begin
        instruction_fields = riscv32_get_fields(instruction_result.data);
        opcode_status = get_opcode_status(instruction_fields);

        // Read specific registers if calling the operating environment
        if (instruction_fields.opcode == RISCV32I_OPCODE_SYSTEM && 
                instruction_fields.funct3 == RISCV32I_FUNCT3_SYS_ENV) begin
            instruction_fields.rs1 = 'd10; // a0
            instruction_fields.rs2 = 'd11; // a1
        end

        // Set register file addresses
        register_read_addr0 = instruction_fields.rs1;
        register_read_addr1 = instruction_fields.rs2;

        // Set register status file addresses
        reg_status_rd_addr  = instruction_fields.rd;
        reg_status_rs1_addr = instruction_fields.rs1;
        reg_status_rs2_addr = instruction_fields.rs2;
    end

    gecko_instruction_operation_t instruction_op;
    gecko_jump_operation_t jump_cmd_in;
    gecko_operation_t writeback_in /* verilator isolate_assignments*/;

    gecko_jump_flag_t next_jump_flag;
    gecko_jump_flag_t next_speculative_flag_rear /* verilator isolate_assignments*/;

    logic flush_instruction, send_operation, decode_exit, during_speculation /* verilator isolate_assignments*/;

    always_comb begin
        automatic gecko_decode_operands_status_t operands_status;
        automatic gecko_reg_status_t forwarded_status_plus;
        automatic riscv32_reg_value_t rs1_value, rs2_value;
        automatic gecko_reg_status_t rd_status, rd_counter;
        // automatic riscv32_fields_t instruction_fields;

        automatic logic increment_speculative_counter, clear_speculative_mispredict;
        automatic gecko_decode_forwarded_search_t forwarded_search;
        // automatic gecko_decode_opcode_status_t opcode_status;

        // Reassign payloads to typed values
        // instruction_fields = riscv32_get_fields(instruction_result.data);
        instruction_op = gecko_instruction_operation_t'(instruction_command.payload);
        jump_cmd_in = gecko_jump_operation_t'(jump_command.payload);
        writeback_in = gecko_operation_t'(writeback_result.payload);
        // opcode_status = get_opcode_status(instruction_fields);

        // Assign next values to defaults
        next_execute_saved = execute_saved;

        // Assign internal flags to defaults
        decode_exit = 'b0;
        consume_instruction = 'b0;
        produce_execute = 'b0;
        produce_system = 'b0;
        produce_float = 'b0;
        produce_print = 'b0;

        // // Read specific registers if calling the operating environment
        // if (instruction_fields.opcode == RISCV32I_OPCODE_SYSTEM && 
        //         instruction_fields.funct3 == RISCV32I_FUNCT3_SYS_ENV) begin
        //     instruction_fields.rs1 = 'd10; // a0
        //     instruction_fields.rs2 = 'd11; // a1
        // end

        // Handle clearing register file by default
        register_write_enable = (state == GECKO_DECODE_RESET);
        register_write_addr = (state == GECKO_DECODE_RESET) ? reset_counter : writeback_in.addr;
        register_write_value = (state == GECKO_DECODE_RESET) ? 'b0 : writeback_in.value;

        // // Set register file addresses
        // register_read_addr0 = instruction_fields.rs1;
        // register_read_addr1 = instruction_fields.rs2;

        // // Determine register status
        // reg_status_rd_addr = instruction_fields.rd;
        // reg_status_rs1_addr = instruction_fields.rs1;
        // reg_status_rs2_addr = instruction_fields.rs2;

        // Clear register file status by default
        front_status_rd_write_enable = (state == GECKO_DECODE_RESET);
        rear_status_writeback_enable = (state == GECKO_DECODE_RESET);
        rear_status_writeback_addr = (state == GECKO_DECODE_RESET) ? reset_counter : writeback_in.addr;

        // Determine various external flags
        exit_flag = (state == GECKO_DECODE_EXIT);

        // Handle incoming branch signals earlier than other logic
        speculative_status_mispredicted_enable = 'b0;
        clear_execute_saved = 'b0;
        clear_speculative_retired_counter = 'b0;
        next_retired_instructions = 'b0;
        next_retired_instructions_speculative = retired_instructions_speculative;
        enable_jump_flag = 'b0;

        enable_speculative_flag_rear = 'b0;
        if (jump_command.valid) begin
            if (jump_cmd_in.update_pc) begin // Mispredicted
                enable_jump_flag = 'b1;
                clear_execute_saved = 'b1;
                next_execute_saved = 'b0;
                speculative_status_mispredicted_enable = 'b1;
            end else begin // Predicted Correctly
                next_retired_instructions = gecko_retired_count_t'(retired_instructions_speculative);
            end

            clear_speculative_retired_counter = 'b1;
            enable_speculative_flag_rear = 'b1;
        end

        next_jump_flag = jump_flag + enable_jump_flag;
        next_speculative_flag_rear = current_speculative_flag_rear + enable_speculative_flag_rear;
        during_speculation = (next_speculative_flag_rear != current_speculative_flag_front);

        // Halt incoming speculative writes until speculation resolved
        writeback_result.ready = !during_speculation || !writeback_in.speculative || 
                (writeback_in.jump_flag != next_speculative_flag_rear);

        // Handle incoming writeback updates to speculative state
        speculative_status_decrement_enable = writeback_result.valid && writeback_result.ready && 
                writeback_in.speculative;

        // Get the status of the current register file
        operands_status = gecko_decode_find_operand_status(
                instruction_fields,
                next_execute_saved,
                front_status_rd, rear_status_rd,
                front_status_rs1, rear_status_rs1,
                front_status_rs2, rear_status_rs2
        );

        // Find any forwarded values if they exist
        forwarded_search = get_forwarded_values(
                instruction_fields,
                forwarded_results,
                front_status_rs1, front_status_rs2,
                speculative_status,
                during_speculation
        );

        operands_status.rs1_valid |= forwarded_search.rs1_valid;
        operands_status.rs2_valid |= forwarded_search.rs2_valid;
        rs1_value = forwarded_search.rs1_valid ? forwarded_search.rs1_value : register_read_value0;
        rs2_value = forwarded_search.rs2_valid ? forwarded_search.rs2_value : register_read_value1;

        // Build commands
        next_execute_command.payload = create_execute_op(
                instruction_fields, 
                instruction_op,
                next_execute_saved, 
                rs1_value, rs2_value,
                front_status_rd,
                next_speculative_flag_rear,
                during_speculation
        );

        next_system_command.payload = create_system_op(
                instruction_fields, 
                next_execute_saved, 
                rs1_value, rs2_value,
                front_status_rd,
                next_speculative_flag_rear
        );

        next_float_command.payload = create_float_op(
                instruction_fields, 
                next_execute_saved, 
                rs1_value, rs2_value,
                front_status_rd,
                next_speculative_flag_rear
        );

        next_ecall_command.payload = create_ecall_op(
                instruction_fields, 
                next_execute_saved, 
                rs1_value, rs2_value,
                front_status_rd,
                next_speculative_flag_rear
        );

        enable_speculative_flag_front = 'b0;
        consume_instruction = 'b0;
        flush_instruction = 'b0;
        increment_speculative_counter = 'b0;
        clear_speculative_mispredict = 'b0;
        case (state)
        GECKO_DECODE_NORMAL: begin
            // Throw away instructions that were misfetched
            if (instruction_op.jump_flag != next_jump_flag) begin
                consume_instruction = 'b1;
                flush_instruction = 'b1;
            // Wait if instruction registers are not ready yet
            end else if (!operands_status.rs1_valid || !operands_status.rs2_valid || !operands_status.rd_valid) begin
                consume_instruction = 'b0;
                flush_instruction = 'b0;
            // Only execute non-side-effect instructions while speculating
            end else if (during_speculation) begin
                // Make sure speculative counter still has room
                if (!is_opcode_side_effects(instruction_fields) && 
                        speculative_status[next_speculative_flag_rear].count != GECKO_SPECULATIVE_FULL) begin
                    consume_instruction = 'b1;
                    // Indicate another instruction has been run speculatively
                    increment_speculative_counter = does_opcode_writeback(instruction_fields);
                end else begin
                    consume_instruction = 'b0;
                end
            // Only execute control
            end else if (is_opcode_control_flow(instruction_fields)) begin
                if (speculative_status[next_speculative_flag_rear].count == 'b0) begin
                    consume_instruction = 'b1;
                    enable_speculative_flag_front = 'b1;
                    // Set mispredicted to zero by default
                    clear_speculative_mispredict = 'b1;
                end else begin
                    consume_instruction = 'b0;
                end
            end else begin
                consume_instruction = 'b1;
            end
        end
        GECKO_DECODE_EXIT: begin
            consume_instruction = 'b1;
            flush_instruction = 'b1;
        end
        default: begin end
        endcase
        
        next_exit_code = exit_code;

        if (consume_instruction && !flush_instruction) begin
            decode_exit |= opcode_status.error_flag;
            decode_exit |= (ENABLE_FLOAT == 0) && opcode_status.float_flag;
            decode_exit |= (ENABLE_INTEGER_MATH == 0) && opcode_status.execute_flag && 
                    next_execute_command.payload.op_type == GECKO_EXECUTE_TYPE_MUL_DIV;
            decode_exit |= is_instruction_ebreak(instruction_fields);

            produce_print = is_instruction_ecall(instruction_fields) && ENABLE_PRINT;
            next_execute_saved = update_execute_saved(instruction_fields, next_execute_saved);
            front_status_rd_write_enable |= does_opcode_writeback(instruction_fields);

            if (decode_exit) begin
                next_execute_command.payload.halt = 'b1;
                next_execute_command.payload.op_type = GECKO_EXECUTE_TYPE_JUMP;
                next_exit_code = rs1_value[7:0];
                produce_execute = 'b1;
                produce_system = 'b0;
                produce_float = 'b0;
            end else begin
                produce_execute = opcode_status.execute_flag;
                produce_system = opcode_status.system_flag;
                produce_float = opcode_status.float_flag;
            end
        end

        stream_controller_result = stream_controller8(stream_controller8_input_t'{
            valid_input:  {6'b0, instruction_result.valid, instruction_command.valid},
            ready_output: {4'b0, next_system_command.ready, next_execute_command.ready, next_ecall_command.ready, next_float_command.ready},
            consume: {6'b0, consume_instruction, consume_instruction},
            produce: {4'b0, produce_system, produce_execute, produce_print, produce_float}
        });
        {instruction_result.ready, instruction_command.ready} = stream_controller_result.ready_input[1:0];
        {next_system_command.valid, next_execute_command.valid, next_ecall_command.valid, next_float_command.valid} = stream_controller_result.valid_output[3:0];
        enable = stream_controller_result.enable;

        // Increment instruction counters
        if (consume_instruction && !flush_instruction) begin
            if (during_speculation) begin
                next_retired_instructions_speculative += enable ? 'd1 : 'd0;
            end else begin
                next_retired_instructions += enable ? 'd1 : 'd0;
            end
        end

        // Update state (RESET -> NORMAL -> EXIT)
        case (state)
        GECKO_DECODE_RESET: next_state = (reset_counter == 'd31) ? GECKO_DECODE_NORMAL : state;
        GECKO_DECODE_NORMAL: next_state = (decode_exit) ? GECKO_DECODE_EXIT : state;
        GECKO_DECODE_EXIT: next_state = state;
        default: next_state = GECKO_DECODE_RESET;
        endcase

        // Update register status regardless of throwing away speculation
        rear_status_writeback_enable |= writeback_result.valid && writeback_result.ready;
        // Throw away writes to x0 and mispeculated results
        if (writeback_result.valid && writeback_result.ready && writeback_in.addr != 'b0) begin
            register_write_enable |= !writeback_in.speculative ||
                    !speculative_status[writeback_in.jump_flag].mispredicted;
        end

        // Work out sychronous speculative status updates (enable gated)
        next_speculative_status = speculative_status;
        next_speculative_status[next_speculative_flag_rear].count += (enable && increment_speculative_counter) ? 'd1 : 'd0;
        if (enable && clear_speculative_mispredict) begin
            next_speculative_status[next_speculative_flag_rear].mispredicted = 'b0;
        end

        // Work out asynchronous speculative status updates
        next_speculative_status[writeback_in.jump_flag].count -= speculative_status_decrement_enable ? 'd1 : 'd0;
        if (speculative_status_mispredicted_enable) begin
            next_speculative_status[current_speculative_flag_rear].mispredicted = 'b1;
        end
    end

endmodule
