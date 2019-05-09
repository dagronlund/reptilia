`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/isa/rv32f.svh"
`include "../../lib/isa/rv32v.svh"
`include "../../lib/gecko/gecko.svh"
`include "../../lib/basilisk/basilisk.svh"
`include "../../lib/basilisk/basilisk_decode_util.svh"
`include "../../lib/fpu/fpu.svh"

`else

`include "std_util.svh"
`include "rv.svh"
`include "rv32.svh"
`include "rv32i.svh"
`include "rv32f.svh"
`include "rv32v.svh"
`include "gecko.svh"
`include "basilisk.svh"
`include "basilisk_decode_util.svh"
`include "fpu.svh"

`endif

module basilisk_decode
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import rv32f::*;
    import rv32v::*;
    import gecko::*;
    import basilisk::*;
    import basilisk_decode_util::*;
    import fpu::*;
#(
    parameter int OUTPUT_REGISTER_MODE = 1
)(
    input logic clk, rst,

    std_stream_intf.in float_command, // gecko_float_operation_t

    std_stream_intf.in writeback_result [BASILISK_COMPUTE_WIDTH], // basilisk_writeback_result_t    

    std_stream_intf.out encode_command, // basilisk_encode_command_t
    std_stream_intf.out convert_command, // basilisk_convert_command_t
    std_stream_intf.out memory_command, // basilisk_memory_command_t

    std_stream_intf.out mult_command [BASILISK_COMPUTE_WIDTH], // basilisk_mult_command_t
    std_stream_intf.out add_command [BASILISK_COMPUTE_WIDTH], // basilisk_add_command_t
    std_stream_intf.out sqrt_command [BASILISK_COMPUTE_WIDTH], // basilisk_sqrt_command_t
    std_stream_intf.out divide_command [BASILISK_COMPUTE_WIDTH] // basilisk_divide_command_t
);

    function automatic fpu_round_mode_t basilisk_decode_find_rounding_mode(
            rv32f_funct3_round_t inst_round_mode,
            input fpu_round_mode_t current_round_mode
    );
        case (inst_round_mode)
        RV32F_FUNCT3_ROUND_EVEN: return FPU_ROUND_MODE_EVEN;
        RV32F_FUNCT3_ROUND_ZERO: return FPU_ROUND_MODE_ZERO;
        RV32F_FUNCT3_ROUND_DOWN: return FPU_ROUND_MODE_DOWN;
        RV32F_FUNCT3_ROUND_UP: return FPU_ROUND_MODE_UP;
        RV32F_FUNCT3_ROUND_DYNAMIC: return current_round_mode;
        default: return FPU_ROUND_MODE_EVEN;
        endcase
    endfunction

    function automatic rv32f_funct3_round_t basilisk_decode_encode_rounding_mode(
            input fpu_round_mode_t current_round_mode
    );
        case (current_round_mode)
        FPU_ROUND_MODE_EVEN: return RV32F_FUNCT3_ROUND_EVEN;
        FPU_ROUND_MODE_ZERO: return RV32F_FUNCT3_ROUND_ZERO;
        FPU_ROUND_MODE_DOWN: return RV32F_FUNCT3_ROUND_DOWN;
        FPU_ROUND_MODE_UP: return RV32F_FUNCT3_ROUND_UP;
        endcase
    endfunction

    typedef enum logic {
        BASILISK_DECODE_STATE_RESET = 'b0,
        BASILISK_DECODE_STATE_NORMAL = 'b1
    } basilisk_decode_state_t;

    typedef basilisk_vector_length_t basilisk_vector_status_count_t [32];
    typedef basilisk_decode_reg_status_t basilisk_vector_status_reg_t [32];

    function automatic basilisk_vector_status_count_t basilisk_decode_update_reg_status_count(
            input basilisk_vector_status_count_t current_status_count,
            input logic vector_writeback_enables [BASILISK_COMPUTE_WIDTH],
            input rv32_reg_addr_t vector_writeback_addresses [BASILISK_COMPUTE_WIDTH]
    );
        int i;
        for (i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
            if (vector_writeback_enables[i]) begin
                current_status_count[vector_writeback_addresses[i]] -= 'b1;
            end
        end
        return current_status_count;
    endfunction

    function automatic basilisk_vector_status_reg_t basilisk_decode_update_reg_status(
        input basilisk_vector_status_reg_t current_status,
        input basilisk_vector_status_count_t current_status_count,
        input logic vector_writeback_enables [BASILISK_COMPUTE_WIDTH],
        input rv32_reg_addr_t vector_writeback_addresses [BASILISK_COMPUTE_WIDTH]
    );
        int i;
        for (i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
            if (vector_writeback_enables[i]) begin
                current_status_count[vector_writeback_addresses[i]] -= 'b1;
            end
        end
        for (i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
            if (current_status_count[vector_writeback_addresses[i]] == 'b0) begin
                current_status[vector_writeback_addresses[i]] = BASILISK_DECODE_REG_STATUS_VALID;
            end
        end
        return current_status;
    endfunction

    std_stream_intf #(.T(basilisk_encode_command_t)) next_encode_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_convert_command_t)) next_convert_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_memory_command_t)) next_memory_command (.clk, .rst);

    std_stream_intf #(.T(basilisk_mult_command_t)) next_mult_command [BASILISK_COMPUTE_WIDTH] (.clk, .rst);
    std_stream_intf #(.T(basilisk_add_command_t)) next_add_command [BASILISK_COMPUTE_WIDTH] (.clk, .rst);
    std_stream_intf #(.T(basilisk_sqrt_command_t)) next_sqrt_command [BASILISK_COMPUTE_WIDTH] (.clk, .rst);
    std_stream_intf #(.T(basilisk_divide_command_t)) next_divide_command [BASILISK_COMPUTE_WIDTH] (.clk, .rst);

    logic [BASILISK_COMPUTE_WIDTH-1:0] writeback_result_valid, writeback_result_ready;
    basilisk_writeback_result_t writeback_result_payload [BASILISK_COMPUTE_WIDTH];

    logic [BASILISK_COMPUTE_WIDTH-1:0] next_mult_command_valid, next_mult_command_ready;
    basilisk_mult_command_t next_mult_command_payload [BASILISK_COMPUTE_WIDTH];

    logic [BASILISK_COMPUTE_WIDTH-1:0] next_add_command_valid, next_add_command_ready;
    basilisk_add_command_t next_add_command_payload [BASILISK_COMPUTE_WIDTH];

    logic [BASILISK_COMPUTE_WIDTH-1:0] next_sqrt_command_valid, next_sqrt_command_ready;
    basilisk_sqrt_command_t next_sqrt_command_payload [BASILISK_COMPUTE_WIDTH];

    logic [BASILISK_COMPUTE_WIDTH-1:0] next_divide_command_valid, next_divide_command_ready;
    basilisk_divide_command_t next_divide_command_payload [BASILISK_COMPUTE_WIDTH];

    genvar k;
    generate
    for (k = 0; k < BASILISK_COMPUTE_WIDTH; k++) begin
        always_comb begin
            writeback_result_valid[k] = writeback_result[k].valid;
            writeback_result_payload[k] = writeback_result[k].payload;
            writeback_result[k].ready = writeback_result_ready[k];

            next_mult_command[k].valid = next_mult_command_valid[k];
            next_mult_command[k].payload = next_mult_command_payload[k];
            next_mult_command_ready[k] = next_mult_command[k].ready;

            next_add_command[k].valid = next_add_command_valid[k];
            next_add_command[k].payload = next_add_command_payload[k];
            next_add_command_ready[k] = next_add_command[k].ready;

            next_sqrt_command[k].valid = next_sqrt_command_valid[k];
            next_sqrt_command[k].payload = next_sqrt_command_payload[k];
            next_sqrt_command_ready[k] = next_sqrt_command[k].ready;

            next_divide_command[k].valid = next_divide_command_valid[k];
            next_divide_command[k].payload = next_divide_command_payload[k];
            next_divide_command_ready[k] = next_divide_command[k].ready;
        end

        std_flow_stage #(
            .T(basilisk_mult_command_t),
            .MODE(OUTPUT_REGISTER_MODE)
        ) mult_command_output_stage (
            .clk, .rst,
            .stream_in(next_mult_command[k]), .stream_out(mult_command[k])
        );

        std_flow_stage #(
            .T(basilisk_add_command_t),
            .MODE(OUTPUT_REGISTER_MODE)
        ) add_commmand_output_stage (
            .clk, .rst,
            .stream_in(next_add_command[k]), .stream_out(add_command[k])
        );

        std_flow_stage #(
            .T(basilisk_sqrt_command_t),
            .MODE(OUTPUT_REGISTER_MODE)
        ) sqrt_command_output_stage (
            .clk, .rst,
            .stream_in(next_sqrt_command[k]), .stream_out(sqrt_command[k])
        );

        std_flow_stage #(
            .T(basilisk_divide_command_t),
            .MODE(OUTPUT_REGISTER_MODE)
        ) divide_command_output_stage (
            .clk, .rst,
            .stream_in(next_divide_command[k]), .stream_out(divide_command[k])
        );
    end
    endgenerate

    logic consume, enable;
    logic produce_encode, produce_convert, produce_memory;
    logic [BASILISK_COMPUTE_WIDTH-1:0] produce_mult, produce_add, produce_sqrt, produce_divide;

    std_flow_lite #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(3 + (4 * BASILISK_COMPUTE_WIDTH))
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({float_command.valid}),
        .ready_input({float_command.ready}),

        .valid_output({
            next_encode_command.valid,
            next_convert_command.valid,
            next_memory_command.valid,

            next_mult_command_valid,
            next_add_command_valid,
            next_sqrt_command_valid,
            next_divide_command_valid
        }),
        .ready_output({
            next_encode_command.ready,
            next_convert_command.ready,
            next_memory_command.ready,

            next_mult_command_ready,
            next_add_command_ready,
            next_sqrt_command_ready,
            next_divide_command_ready
        }),

        .consume, 
        .produce({produce_encode, produce_convert, produce_memory,
            produce_mult, produce_add, produce_sqrt, produce_divide}), 
        .enable
    );

    std_flow_stage #(
        .T(basilisk_encode_command_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) encode_command_output_stage (
        .clk, .rst,
        .stream_in(next_encode_command), .stream_out(encode_command)
    );

    std_flow_stage #(
        .T(basilisk_convert_command_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) convert_command_output_stage (
        .clk, .rst,
        .stream_in(next_convert_command), .stream_out(convert_command)
    );

    std_flow_stage #(
        .T(basilisk_memory_command_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) memory_command_output_stage (
        .clk, .rst,
        .stream_in(next_memory_command), .stream_out(memory_command)
    );

    basilisk_decode_state_t current_state, next_state;
    logic current_vector_progress, next_vector_progress;
    rv32_reg_addr_t current_reset_counter, next_reset_counter;
    fpu_round_mode_t current_round_mode, next_round_mode;
    basilisk_vector_length_t current_vector_length, next_vector_length;
    basilisk_vector_length_t current_vector_start, next_vector_start;

    logic rd_write_enable [BASILISK_VECTOR_WIDTH];
    rv32_reg_addr_t rd_write_addr [BASILISK_VECTOR_WIDTH];
    rv32_reg_value_t rd_write_value [BASILISK_VECTOR_WIDTH];
    rv32_reg_addr_t rd_read_addr [BASILISK_VECTOR_WIDTH];
    rv32_reg_addr_t rs1_read_addr [BASILISK_VECTOR_WIDTH];
    rv32_reg_addr_t rs2_read_addr [BASILISK_VECTOR_WIDTH];
    rv32_reg_addr_t rs3_read_addr [BASILISK_VECTOR_WIDTH];
    rv32_reg_value_t rs1_read_value [BASILISK_VECTOR_WIDTH];
    rv32_reg_value_t rs2_read_value [BASILISK_VECTOR_WIDTH];
    rv32_reg_value_t rs3_read_value [BASILISK_VECTOR_WIDTH];

    logic rd_front_status_write_enable [BASILISK_VECTOR_WIDTH];
    rv32_reg_addr_t rd_front_status_write_addr [BASILISK_VECTOR_WIDTH];
    logic rs1_front_status [BASILISK_VECTOR_WIDTH];
    logic rs2_front_status [BASILISK_VECTOR_WIDTH];
    logic rs3_front_status [BASILISK_VECTOR_WIDTH];

    logic rs1_rear_status [BASILISK_VECTOR_WIDTH];
    logic rs2_rear_status [BASILISK_VECTOR_WIDTH];
    logic rs3_rear_status [BASILISK_VECTOR_WIDTH];

    logic rd_status [BASILISK_VECTOR_WIDTH];
    logic rs1_status [BASILISK_VECTOR_WIDTH];
    logic rs2_status [BASILISK_VECTOR_WIDTH];
    logic rs3_status [BASILISK_VECTOR_WIDTH];

    generate
    for (k = 0; k < BASILISK_VECTOR_WIDTH; k++) begin
        logic front_status_write_value, rear_status_rd_value;

        assign rd_status[k] = (front_status_write_value == rear_status_rd_value);
        assign rs1_status[k] = (rs1_front_status[k] == rs1_rear_status[k]);
        assign rs2_status[k] = (rs2_front_status[k] == rs2_rear_status[k]);
        assign rs3_status[k] = (rs3_front_status[k] == rs3_rear_status[k]);

        // Front Register Status
        std_distributed_ram #(
            .DATA_WIDTH(1),
            .ADDR_WIDTH($size(rv32_reg_addr_t)),
            .READ_PORTS(3)
        ) front_register_status_inst (
            .clk, .rst,

            .write_enable(rd_front_status_write_enable[k] && enable),
            .write_addr(rd_front_status_write_addr[k]),
            .write_data_in((current_state == BASILISK_DECODE_STATE_RESET) ? 'b0 : (~front_status_write_value)),
            .write_data_out(front_status_write_value),

            .read_addr('{rs1_read_addr[k], rs2_read_addr[k], rs3_read_addr[k]}),
            .read_data_out('{rs1_front_status[k], rs2_front_status[k], rs3_front_status[k]})
        );

        // Rear Register Status
        logic rear_status_write_value;
        std_distributed_ram #(
            .DATA_WIDTH(1),
            .ADDR_WIDTH($size(rv32_reg_addr_t)),
            .READ_PORTS(4)
        ) rear_register_status_inst (
            .clk, .rst,

            .write_enable(rd_write_enable[k]),
            .write_addr(rd_write_addr[k]),
            .write_data_in((current_state == BASILISK_DECODE_STATE_RESET) ? 'b0 : (~rear_status_write_value)),
            .write_data_out(rear_status_write_value),

            .read_addr('{rd_read_addr[k], rs1_read_addr[k], rs2_read_addr[k], rs3_read_addr[k]}),
            .read_data_out('{rear_status_rd_value, rs1_rear_status[k], rs2_rear_status[k], rs3_rear_status[k]})
        );

        // Register File
        std_distributed_ram #(
            .DATA_WIDTH($size(rv32_reg_value_t)),
            .ADDR_WIDTH($size(rv32_reg_addr_t)),
            .READ_PORTS(3)
        ) register_file_inst (
            .clk, .rst,

            // Always write to all bits in register
            .write_enable({32{rd_write_enable[k]}}),
            .write_addr(rd_write_addr[k]),
            .write_data_in(rd_write_value[k]),

            .read_addr('{rs1_read_addr[k], rs2_read_addr[k], rs3_read_addr[k]}),
            .read_data_out('{rs1_read_value[k], rs2_read_value[k], rs3_read_value[k]})
        );
    end
    endgenerate

    logic reg_status_writeback_enable [BASILISK_COMPUTE_WIDTH];
    rv32_reg_addr_t reg_status_writeback_addr [BASILISK_COMPUTE_WIDTH];

    always_ff @(posedge clk) begin
        if(rst) begin
            current_state <= BASILISK_DECODE_STATE_RESET;
            current_vector_progress <= 'b0;
            current_reset_counter <= 'b0;
            current_round_mode <= FPU_ROUND_MODE_EVEN;
            current_vector_length <= 'b1;
            current_vector_start <= 'b0;
        end else if (enable) begin
            current_state <= next_state;
            current_vector_progress <= next_vector_progress;
            current_reset_counter <= next_reset_counter;
            current_round_mode <= next_round_mode;
            current_vector_length <= next_vector_length;
            current_vector_start <= next_vector_start;
        end
    end

    logic reg_file_clear;
    basilisk_vector_length_t calc_vector_addr, read_vector_addr;
    basilisk_offset_addr_t calc_vector_offset;
    logic enable_slideup, enable_slidedown, enable_scalar_rs1, enable_scalar_rs2;
    logic rd_vector_status, rs1_vector_status, rs2_vector_status, rs3_vector_status;
    always_comb begin
        automatic rv32_fields_t inst_fields = float_command.payload.instruction_fields;

        automatic fpu_float_fields_t rs1_fields_scalar, rs2_fields_scalar, rs3_fields_scalar;
        automatic fpu_float_conditions_t rs1_conditions_scalar, rs2_conditions_scalar, rs3_conditions_scalar;

        automatic fpu_float_fields_t rs1_fields_vector [BASILISK_COMPUTE_WIDTH];
        automatic fpu_float_fields_t rs2_fields_vector [BASILISK_COMPUTE_WIDTH];
        automatic fpu_float_fields_t rs3_fields_vector [BASILISK_COMPUTE_WIDTH];
        automatic fpu_float_conditions_t rs1_conditions_vector [BASILISK_COMPUTE_WIDTH];
        automatic fpu_float_conditions_t rs2_conditions_vector [BASILISK_COMPUTE_WIDTH];
        automatic fpu_float_conditions_t rs3_conditions_vector [BASILISK_COMPUTE_WIDTH];

        automatic rv32_reg_value_t immediate_value, sys_value;
        automatic basilisk_memory_op_t mem_op;
        automatic basilisk_convert_op_t convert_op;
        automatic basilisk_encode_op_t encode_op;
        automatic logic enable_macc, convert_signed_integer;
        automatic logic sys_write, sys_set, sys_clear, sys_use_imm;
        automatic fpu_round_mode_t selected_round_mode;
        automatic fpu_round_mode_t incoming_round_mode;
        automatic rv32f_funct3_round_t outgoing_round_mode;
        // automatic basilisk_vector_length_t calc_vector_addr;
        // automatic basilisk_offset_addr_t calc_vector_offset;
        // automatic logic enable_slideup, enable_slidedown, enable_scalar_rs1, enable_scalar_rs2;
        automatic logic enable_vector, enable_vector_macc, enable_vector_sqrt;
        // automatic logic reg_file_clear;

        consume = (current_state == BASILISK_DECODE_STATE_NORMAL);
        produce_encode = 'b0;
        produce_mult = 'b0;
        produce_add = 'b0;
        produce_sqrt = 'b0;
        produce_divide = 'b0;
        produce_convert = 'b0;
        produce_memory = 'b0;

        next_state = current_state;
        next_vector_progress = current_vector_progress;
        next_reset_counter = current_reset_counter + 'b1;
        next_round_mode = current_round_mode;
        next_vector_length = current_vector_length;
        next_vector_start = current_vector_start;

        rd_front_status_write_enable = '{BASILISK_VECTOR_WIDTH{(current_state == BASILISK_DECODE_STATE_RESET)}};
        if (current_state == BASILISK_DECODE_STATE_RESET) begin
            rd_front_status_write_addr = '{BASILISK_VECTOR_WIDTH{current_reset_counter}};
        end else begin
            rd_front_status_write_addr = '{BASILISK_VECTOR_WIDTH{inst_fields.rd}};
        end

        enable_slideup = 'b0;
        enable_slidedown = 'b0;
        enable_scalar_rs1 = 'b0;
        enable_scalar_rs2 = 'b0;
        enable_vector_macc = 'b0;
        enable_vector_sqrt = 'b0;
        case (rv32v_opcode_t'(inst_fields.opcode))
        RV32V_OPCODE_OP: begin
            case (rv32v_funct3_t'(inst_fields.funct3))
            RV32V_FUNCT3_OP_IVI: begin // Integer Vector-Immediate (Slideup/Slidedown)
                case (rv32v_funct6_t'(inst_fields.funct6))
                    RV32V_FUNCT6_VSLIDEUP: enable_slideup = 'b1;
                    RV32V_FUNCT6_VSLIDEDOWN: enable_slidedown = 'b1;
                endcase
            end
            RV32V_FUNCT3_OP_FVF: begin
                case (rv32v_funct6_t'(inst_fields.funct6))
                RV32V_FUNCT6_VFRDIV: enable_scalar_rs1 = 'b1;
                default: enable_scalar_rs2 = 'b1;
                endcase
            end
            RV32V_FUNCT3_OP_FVV: begin // Floating Point Vector-Vector
                case (rv32v_funct6_t'(inst_fields.funct6))
                RV32V_FUNCT6_VFMACC, RV32V_FUNCT6_VFNMACC,
                RV32V_FUNCT6_VFMSAC, RV32V_FUNCT6_VFNMSAC: enable_vector_macc = 'b1;
                RV32V_FUNCT6_VFSQRT: enable_vector_sqrt = 'b1;
                endcase
            end
            endcase
        end
        endcase

        for (int i = 0; i < BASILISK_VECTOR_WIDTH; i++) begin
            rd_read_addr[i] = inst_fields.rd;

            // Vector sqrt works using rs2
            if (enable_vector_sqrt) begin
                rs1_read_addr[i] = inst_fields.rs2;
            end else begin
                rs1_read_addr[i] = inst_fields.rs1;
            end

            rs2_read_addr[i] = inst_fields.rs2;

            // Vector MACC instructions reuse rd as rs3
            if (enable_vector_macc) begin
                rs3_read_addr[i] = inst_fields.rd;
            end else begin
                rs3_read_addr[i] = inst_fields.rs3;
            end
        end

        // Retrieve vector values from register file
        for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
            if (enable_slideup) begin
                read_vector_addr = (BASILISK_VECTOR_WIDTH - BASILISK_COMPUTE_WIDTH - current_vector_start) + i;
                if (read_vector_addr == 0) begin
                    read_vector_addr = BASILISK_VECTOR_WIDTH - 1;
                end else begin
                    read_vector_addr -= 'b1;
                end
            end else if (enable_slidedown) begin
                read_vector_addr = current_vector_start + i;
                if (read_vector_addr == BASILISK_VECTOR_WIDTH - 1) begin
                    read_vector_addr = 'b0;
                end else begin
                    read_vector_addr += 'b1;
                end
            end else begin
                read_vector_addr = current_vector_start + i;
            end

            // Add zero from rs1 if sliding up or down
            if (enable_slideup || enable_slidedown) begin
                rs1_fields_vector[i] = fpu_decode_float('b0);
                rs1_conditions_vector[i] = fpu_get_conditions('b0);
            // Scalar operation on rs1
            end else if (enable_scalar_rs1) begin
                rs1_fields_vector[i] = fpu_decode_float(rs1_read_value['b0]);
                rs1_conditions_vector[i] = fpu_get_conditions(rs1_read_value['b0]); 
            end else begin
                rs1_fields_vector[i] = fpu_decode_float(rs1_read_value[current_vector_start + i]);
                rs1_conditions_vector[i] = fpu_get_conditions(rs1_read_value[current_vector_start + i]);
            end
            
            // Scalar operation on rs2
            if (enable_scalar_rs2) begin
                rs2_fields_vector[i] = fpu_decode_float(rs2_read_value['b0]);
                rs2_conditions_vector[i] = fpu_get_conditions(rs2_read_value['b0]);
            // Use calculated address
            end else begin
                rs2_fields_vector[i] = fpu_decode_float(rs2_read_value[read_vector_addr]);
                rs2_conditions_vector[i] = fpu_get_conditions(rs2_read_value[read_vector_addr]);
            end

            rs3_fields_vector[i] = fpu_decode_float(rs3_read_value[current_vector_start + i]);
            rs3_conditions_vector[i] = fpu_get_conditions(rs3_read_value[current_vector_start + i]);
        end

        // Retrieve scalar values from register file
        rs1_fields_scalar = fpu_decode_float(rs1_read_value[0]);
        rs2_fields_scalar = fpu_decode_float(rs2_read_value[0]);
        rs3_fields_scalar = fpu_decode_float(rs3_read_value[0]);
        rs1_conditions_scalar = fpu_get_conditions(rs1_read_value[0]);
        rs2_conditions_scalar = fpu_get_conditions(rs2_read_value[0]);
        rs3_conditions_scalar = fpu_get_conditions(rs3_read_value[0]);

        rd_vector_status = 'b1;
        rs1_vector_status = 'b1;
        rs2_vector_status = 'b1;
        rs3_vector_status = 'b1;
        for (int i = 0; i < BASILISK_VECTOR_WIDTH; i++) begin
            rd_vector_status &= rd_status[i];
            rs1_vector_status &= rs1_status[i];
            rs2_vector_status &= rs2_status[i];
            rs3_vector_status &= rs3_status[i];
        end

        sys_write = 'b0;
        sys_set = 'b0;
        sys_clear = 'b0;
        sys_use_imm = 'b0;

        // reg_file_clear = 'b1;

        // Handle floating-point load-store immediate
        immediate_value = {{20{inst_fields.inst[31]}}, inst_fields.inst[31:20]};
        mem_op = BASILISK_MEMORY_OP_LOAD;

        // Handle macc operations
        enable_macc = 'b0;

        // Handle conversion operations
        convert_op = BASILISK_CONVERT_OP_CNV;

        // Handle encoding operations
        encode_op = BASILISK_ENCODE_OP_RAW;

        // Handle integer sign
        convert_signed_integer = ((rv32f_funct5_fcvt_t'(inst_fields.rs2)) == RV32F_FUNCT5_FCVT_W);

        // Handle rounding mode selection    
        selected_round_mode =basilisk_decode_find_rounding_mode(
            rv32f_funct3_round_t'(inst_fields.funct3),
            current_round_mode
        );

        case (rv32f_opcode_t'(inst_fields.opcode))
        RV32F_OPCODE_FLW: begin
            produce_memory = 'b1;
        end
        RV32F_OPCODE_FSW: begin
            immediate_value = {{20{inst_fields.inst[31]}}, inst_fields.inst[31:25], inst_fields.inst[11:7]};
            mem_op = BASILISK_MEMORY_OP_STORE;
            produce_memory = 'b1;
        end
        RV32F_OPCODE_FMADD_S: begin
            produce_mult = 'b1;
            enable_macc = 'b1;
        end
        RV32F_OPCODE_FMSUB_S: begin
            produce_mult = 'b1;
            enable_macc = 'b1;
            for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
                rs3_fields_vector[i].sign = ~rs3_fields_vector[i].sign;
            end
            rs3_fields_scalar.sign = ~rs3_fields_scalar.sign;
        end
        RV32F_OPCODE_FNMSUB_S: begin
            produce_mult = 'b1;
            enable_macc = 'b1;
            for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
                rs1_fields_vector[i].sign = ~rs1_fields_vector[i].sign;
            end
            rs1_fields_scalar.sign = ~rs1_fields_scalar.sign;
        end
        RV32F_OPCODE_FNMADD_S: begin
            produce_mult = 'b1;
            enable_macc = 'b1;
            for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
                rs1_fields_vector[i].sign = ~rs1_fields_vector[i].sign;
                rs3_fields_vector[i].sign = ~rs3_fields_vector[i].sign;
            end
            rs1_fields_scalar.sign = ~rs1_fields_scalar.sign;
            rs3_fields_scalar.sign = ~rs3_fields_scalar.sign;
        end
        RV32F_OPCODE_FP_OP_S: begin
            case (rv32f_funct7_t'(inst_fields.funct7))
            RV32F_FUNCT7_FADD_S: begin
                produce_add = 'b1;
            end
            RV32F_FUNCT7_FSUB_S: begin
                produce_add = 'b1;
                for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
                    rs2_fields_vector[i].sign = ~rs2_fields_vector[i].sign;
                end
                rs2_fields_scalar.sign = ~rs2_fields_scalar.sign;
            end
            RV32F_FUNCT7_FMUL_S: begin
                produce_mult = 'b1;
            end
            RV32F_FUNCT7_FDIV_S: begin
                produce_divide = 'b1;
            end
            RV32F_FUNCT7_FSQRT_S: begin
                produce_sqrt = 'b1;
            end
            RV32F_FUNCT7_FSGNJ_S: begin
                produce_convert = 'b1;
                convert_op = BASILISK_CONVERT_OP_RAW;
                case (rv32f_funct3_fsgnj_t'(inst_fields.funct3))
                RV32F_FUNCT3_FSGNJ_S: begin
                    for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
                        rs1_fields_vector[i].sign = rs2_fields_vector[i].sign;
                    end
                    rs1_fields_scalar.sign = rs2_fields_scalar.sign;
                end
                RV32F_FUNCT3_FSGNJN_S: begin
                    for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
                        rs1_fields_vector[i].sign = ~rs2_fields_vector[i].sign;
                    end
                    rs1_fields_scalar.sign = ~rs2_fields_scalar.sign;
                end
                RV32F_FUNCT3_FSGNJX_S: begin
                    for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
                        rs1_fields_vector[i].sign ^= rs2_fields_vector[i].sign;
                    end
                    rs1_fields_scalar.sign ^= rs2_fields_scalar.sign;
                end
                endcase
            end
            RV32F_FUNCT7_FMIN_MAX_S: begin
                produce_convert = 'b1;
                case (rv32f_funct3_min_max_t'(inst_fields.funct3))
                RV32F_FUNCT3_FMIN_S: convert_op = BASILISK_CONVERT_OP_MIN;
                RV32F_FUNCT3_FMAX_S: convert_op = BASILISK_CONVERT_OP_MAX;
                endcase
            end
            RV32F_FUNCT7_FCVT_S_W: begin
                produce_convert = 'b1;
                convert_op = BASILISK_CONVERT_OP_CNV;
                rs1_fields_scalar = fpu_decode_float(float_command.payload.rs1_value); // Use integer file
                rs1_fields_vector[0] = fpu_decode_float(float_command.payload.rs1_value); // Use integer file
            end
            RV32F_FUNCT7_FMV_W_X: begin
                produce_convert = 'b1;
                convert_op = BASILISK_CONVERT_OP_RAW;
                rs1_fields_scalar = fpu_decode_float(float_command.payload.rs1_value); // Use integer file
                rs1_fields_vector[0] = fpu_decode_float(float_command.payload.rs1_value); // Use integer file
            end
            RV32F_FUNCT7_FCVT_W_S: begin
                produce_encode = 'b1;
                encode_op = BASILISK_ENCODE_OP_CONVERT;
            end
            RV32F_FUNCT7_FMV_X_W: begin
                produce_encode = 'b1;
                case (rv32f_funct3_class_t'(inst_fields.funct3))
                RV32F_FUNCT3_FMV_X_W: encode_op = BASILISK_ENCODE_OP_RAW;
                RV32F_FUNCT3_FCLASS_S: encode_op = BASILISK_ENCODE_OP_CLASS;
                endcase
            end
            RV32F_FUNCT7_FCMP_S: begin
                produce_encode = 'b1;
                case (rv32f_funct3_compare_t'(inst_fields.funct3))
                RV32F_FUNCT3_FLE_S: encode_op = BASILISK_ENCODE_OP_LE;
                RV32F_FUNCT3_FLT_S: encode_op = BASILISK_ENCODE_OP_LT;
                RV32F_FUNCT3_FEQ_S: encode_op = BASILISK_ENCODE_OP_EQUAL;
                endcase
            end
            endcase
        end
        endcase
        
        enable_vector = 'b0;
        case (rv32v_opcode_t'(inst_fields.opcode))
        RV32V_OPCODE_OP: begin
            enable_vector = 'b1;
            consume = 'b0;

            case (rv32v_funct3_t'(inst_fields.funct3))
            RV32V_FUNCT3_OP_FVV: begin // Floating Point Vector-Vector
                case (rv32v_funct6_t'(inst_fields.funct6))
                RV32V_FUNCT6_VFADD: begin
                    produce_add = {BASILISK_COMPUTE_WIDTH{1'b1}};
                end
                RV32V_FUNCT6_VFSUB: begin
                    for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
                        rs2_fields_vector[i].sign = ~rs2_fields_vector[i].sign;
                    end
                    produce_add = {BASILISK_COMPUTE_WIDTH{1'b1}};
                end
                RV32V_FUNCT6_VFDIV: begin
                    produce_divide = {BASILISK_COMPUTE_WIDTH{1'b1}};
                end
                RV32V_FUNCT6_VFSQRT: begin
                    produce_sqrt = {BASILISK_COMPUTE_WIDTH{1'b1}};
                end
                RV32V_FUNCT6_VFMUL: begin
                    produce_mult = {BASILISK_COMPUTE_WIDTH{1'b1}};
                end
                RV32V_FUNCT6_VFMACC: begin
                    produce_mult = {BASILISK_COMPUTE_WIDTH{1'b1}};
                end
                RV32V_FUNCT6_VFNMACC: begin
                    produce_mult = {BASILISK_COMPUTE_WIDTH{1'b1}};
                    for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
                        rs1_fields_vector[i].sign = ~rs1_fields_vector[i].sign;
                        rs3_fields_vector[i].sign = ~rs3_fields_vector[i].sign;
                    end
                end
                RV32V_FUNCT6_VFMSAC: begin
                    produce_mult = {BASILISK_COMPUTE_WIDTH{1'b1}};
                    for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
                        rs3_fields_vector[i].sign = ~rs3_fields_vector[i].sign;
                    end
                end
                RV32V_FUNCT6_VFNMSAC: begin
                    produce_mult = {BASILISK_COMPUTE_WIDTH{1'b1}};
                    for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
                        rs1_fields_vector[i].sign = ~rs1_fields_vector[i].sign;
                    end
                end
                endcase
                
                next_vector_start += BASILISK_COMPUTE_WIDTH;
                if (next_vector_start >= BASILISK_VECTOR_WIDTH) begin
                    consume = 'b1;
                    next_vector_start = 'b0;
                end
            end
            RV32V_FUNCT3_OP_FVF: begin // Floating Point Vector-Scalar
                case (rv32v_funct6_t'(inst_fields.funct6))
                RV32V_FUNCT6_VFADD: begin
                    produce_add = {BASILISK_COMPUTE_WIDTH{1'b1}};
                end
                RV32V_FUNCT6_VFSUB: begin
                    for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
                        rs2_fields_vector[i].sign = ~rs2_fields_vector[i].sign;
                    end
                    produce_add = {BASILISK_COMPUTE_WIDTH{1'b1}};
                end
                RV32V_FUNCT6_VFDIV: begin
                    produce_divide = {BASILISK_COMPUTE_WIDTH{1'b1}};
                end
                RV32V_FUNCT6_VFSQRT: begin
                    produce_sqrt = {BASILISK_COMPUTE_WIDTH{1'b1}};
                end
                RV32V_FUNCT6_VFRDIV: begin
                    produce_divide = {BASILISK_COMPUTE_WIDTH{1'b1}};
                end
                RV32V_FUNCT6_VFMUL: begin
                    produce_mult = {BASILISK_COMPUTE_WIDTH{1'b1}};
                end
                endcase
                
                next_vector_start += BASILISK_COMPUTE_WIDTH;
                if (next_vector_start >= BASILISK_VECTOR_WIDTH) begin
                    consume = 'b1;
                    next_vector_start = 'b0;
                end
            end
            RV32V_FUNCT3_OP_IVI: begin // Integer Vector-Immediate (Slideup/Slidedown)
                case (rv32v_funct6_t'(inst_fields.funct6))
                RV32V_FUNCT6_VSLIDEUP, RV32V_FUNCT6_VSLIDEDOWN: begin
                    produce_add = {BASILISK_COMPUTE_WIDTH{1'b1}};
                    next_vector_start += BASILISK_COMPUTE_WIDTH;
                    if (next_vector_start >= BASILISK_VECTOR_WIDTH) begin
                        consume = 'b1;
                        next_vector_start = 'b0;
                    end
                end
                endcase
            end
            endcase
        end
        endcase

        case (float_command.payload.sys_op)
        RV32I_FUNCT3_SYS_CSRRWI, RV32I_FUNCT3_SYS_CSRRSI, RV32I_FUNCT3_SYS_CSRRCI: sys_value = float_command.payload.sys_imm;
        default: sys_value = float_command.payload.rs1_value;
        endcase

        incoming_round_mode = basilisk_decode_find_rounding_mode(rv32f_funct3_round_t'(sys_value[2:0]), FPU_ROUND_MODE_EVEN);
        outgoing_round_mode = basilisk_decode_encode_rounding_mode(current_round_mode);

        case (float_command.payload.sys_op)
        RV32I_FUNCT3_SYS_CSRRW, RV32I_FUNCT3_SYS_CSRRWI: sys_write = 'b1;
        RV32I_FUNCT3_SYS_CSRRS, RV32I_FUNCT3_SYS_CSRRSI: sys_set = 'b1;
        RV32I_FUNCT3_SYS_CSRRC, RV32I_FUNCT3_SYS_CSRRCI: sys_clear = 'b1;
        endcase

        // Is in reset mode
        if (current_state == BASILISK_DECODE_STATE_RESET) begin
            consume = 'b0;
            produce_encode = 'b0;
            produce_mult = 'b0;
            produce_add = 'b0;
            produce_sqrt = 'b0;
            produce_divide = 'b0;
            produce_convert = 'b0;
            produce_memory = 'b0;

            if (next_reset_counter == 'b0) begin
                next_state = BASILISK_DECODE_STATE_NORMAL;
            end
        // Change status registers
        end else if (float_command.payload.enable_status_op) begin
            
            consume = 'b1;
            produce_encode = (float_command.payload.dest_reg_addr != 'b0); // Don't produce writeback to x0
            produce_mult = 'b0;
            produce_add = 'b0;
            produce_sqrt = 'b0;
            produce_divide = 'b0;
            produce_convert = 'b0;
            produce_memory = 'b0;

            // Have CSR operation return proper flags
            case (rv32_funct12_t'(float_command.payload.sys_csr))
            RV32F_CSR_FRM: begin
                rs1_fields_scalar = fpu_decode_float({29'b0, outgoing_round_mode});
                rs1_fields_vector[0] = fpu_decode_float({29'b0, outgoing_round_mode});
                if (sys_write) begin
                    next_round_mode = incoming_round_mode;
                end
            end
            RV32V_CSR_VL: begin
                rs1_fields_scalar = fpu_decode_float(current_vector_length);
                rs1_fields_vector[0] = fpu_decode_float(current_vector_length);
                if (sys_write) begin
                    next_vector_length = sys_value;
                end
            end
            default: begin
                rs1_fields_scalar = fpu_decode_float({32'b0});
                rs1_fields_vector[0] = fpu_decode_float({32'b0});
            end
            endcase
        end else begin
            // Stall for register availability
            if (basilisk_decode_depend_registers(inst_fields, 
                    rd_vector_status, 
                    rs1_vector_status, 
                    rs2_vector_status, 
                    rs3_vector_status) || 
                    current_vector_progress) begin
                if (basilisk_decode_depend_rd(inst_fields)) begin
                    if (enable_vector) begin
                        if (current_vector_start == 0) begin
                            next_vector_progress = 'b1;
                            rd_front_status_write_enable = '{BASILISK_VECTOR_WIDTH{'b1}};
                        end

                        if (current_vector_start >= BASILISK_VECTOR_WIDTH - BASILISK_COMPUTE_WIDTH) begin
                            next_vector_progress = 'b0;
                        end
                    end else begin
                        rd_front_status_write_enable[0] = 'b1;
                    end
                end
            end else begin
                consume = 'b0;
                produce_encode = 'b0;
                produce_mult = 'b0;
                produce_add = 'b0;
                produce_sqrt = 'b0;
                produce_divide = 'b0;
                produce_convert = 'b0;
                produce_memory = 'b0;
                next_vector_start = current_vector_start;
                next_vector_progress = current_vector_progress;
            end
        end

        next_encode_command.payload = '{
            dest_reg_addr: float_command.payload.dest_reg_addr,
            dest_reg_status: float_command.payload.dest_reg_status,
            jump_flag: float_command.payload.jump_flag,
            signed_integer: convert_signed_integer,
            op: encode_op,
            a: rs1_fields_vector[0],
            b: rs2_fields_vector[0],
            conditions_a: rs1_conditions_vector[0],
            conditions_b: rs2_conditions_vector[0]
        };

        next_convert_command.payload = '{
            dest_reg_addr: inst_fields.rd,
            dest_offset_addr: current_vector_start,
            a: rs1_fields_vector[0],
            b: rs2_fields_vector[0],
            conditions_a: rs1_conditions_vector[0],
            conditions_b: rs2_conditions_vector[0],
            op: convert_op,
            signed_integer: convert_signed_integer
        };

        next_memory_command.payload = '{
            dest_reg_addr: inst_fields.rd,
            dest_offset_addr: 'b0,
            a: {rs2_fields_vector[0].sign, rs2_fields_vector[0].exponent, rs2_fields_vector[0].mantissa},
            op: mem_op,
            mem_base_addr: float_command.payload.rs1_value,
            mem_offset_addr: immediate_value
        };

        for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin

            if (enable_slideup) begin
                calc_vector_offset = (BASILISK_VECTOR_WIDTH - BASILISK_COMPUTE_WIDTH - current_vector_start) / BASILISK_COMPUTE_WIDTH;
            end else begin
                calc_vector_offset = current_vector_start / BASILISK_COMPUTE_WIDTH;
            end

            next_mult_command_payload[i] = '{
                dest_reg_addr: inst_fields.rd,
                dest_offset_addr: calc_vector_offset,
                enable_macc: enable_macc || enable_vector_macc,
                a: rs1_fields_vector[i],
                b: rs2_fields_vector[i],
                c: rs3_fields_vector[i],
                conditions_a: rs1_conditions_vector[i],
                conditions_b: rs2_conditions_vector[i],
                conditions_c: rs3_conditions_vector[i],
                mode: selected_round_mode
            };

            // Adding is used for slide up and down
            next_add_command_payload[i] = '{
                dest_reg_addr: inst_fields.rd,
                dest_offset_addr: calc_vector_offset,
                a: rs1_fields_vector[i],
                b: rs2_fields_vector[i],
                conditions_a: rs1_conditions_vector[i],
                conditions_b: rs2_conditions_vector[i],
                mode: selected_round_mode
            };

            next_sqrt_command_payload[i] = '{
                dest_reg_addr: inst_fields.rd,
                dest_offset_addr: calc_vector_offset,
                a: rs1_fields_vector[i],
                conditions_a: rs1_conditions_vector[i],
                mode: selected_round_mode
            };

            next_divide_command_payload[i] = '{
                dest_reg_addr: inst_fields.rd,
                dest_offset_addr: calc_vector_offset,
                a: rs1_fields_vector[i],
                b: rs2_fields_vector[i],
                conditions_a: rs1_conditions_vector[i],
                conditions_b: rs2_conditions_vector[i],
                mode: selected_round_mode
            };

        end

        rd_write_enable = '{BASILISK_VECTOR_WIDTH{'b0}};

        // Handle writebacks
        for (int i = 0; i < BASILISK_COMPUTE_WIDTH; i++) begin
            writeback_result_ready[i] = (current_state == BASILISK_DECODE_STATE_NORMAL);

            calc_vector_addr = (writeback_result_payload[i].dest_offset_addr * BASILISK_COMPUTE_WIDTH) + i;

            // Set all addresses and data for that group
            for (int j = 0; j < (BASILISK_VECTOR_WIDTH/BASILISK_COMPUTE_WIDTH); j++) begin
                if (current_state == BASILISK_DECODE_STATE_RESET) begin
                    rd_write_enable[(j * BASILISK_COMPUTE_WIDTH) + i] = 'b1;
                    rd_write_addr[(j * BASILISK_COMPUTE_WIDTH) + i] = current_reset_counter;
                    rd_write_value[(j * BASILISK_COMPUTE_WIDTH) + i] = 'b0;
                end else begin
                    rd_write_addr[(j * BASILISK_COMPUTE_WIDTH) + i] = writeback_result_payload[i].dest_reg_addr;
                    rd_write_value[(j * BASILISK_COMPUTE_WIDTH) + i] = writeback_result_payload[i].result;
                end
            end

            rd_write_enable[calc_vector_addr] = writeback_result_valid[i];
        end
    end

endmodule

/*
31 27 26 25 24 20 19 15 14 12 11 7 6 0
funct7 rs2 rs1 funct3 rd opcode R-type
rs3 funct2 rs2 rs1 funct3 rd opcode R4-type
imm[11:0] rs1 funct3 rd opcode I-type
imm[11:5] rs2 rs1 funct3 imm[4:0] opcode S-type

RV32F Standard Extension
imm[11:0]     rs1 010 rd       0000111 FLW // rs1 integer value
imm[11:5] rs2 rs1 010 imm[4:0] 0100111 FSW // rs1 integer value

rs3 00    rs2 rs1 rm  rd       1000011 FMADD.S
rs3 00    rs2 rs1 rm  rd       1000111 FMSUB.S
rs3 00    rs2 rs1 rm  rd       1001011 FNMSUB.S
rs3 00    rs2 rs1 rm  rd       1001111 FNMADD.S

0000000   rs2 rs1 rm  rd       1010011 FADD.S
0000100   rs2 rs1 rm  rd       1010011 FSUB.S
0001000   rs2 rs1 rm  rd       1010011 FMUL.S
0001100   rs2 rs1 rm  rd       1010011 FDIV.S
0101100 00000 rs1 rm  rd       1010011 FSQRT.S

0010000   rs2 rs1 000 rd       1010011 FSGNJ.S
0010000   rs2 rs1 001 rd       1010011 FSGNJN.S
0010000   rs2 rs1 010 rd       1010011 FSGNJX.S

0010100   rs2 rs1 000 rd       1010011 FMIN.S
0010100   rs2 rs1 001 rd       1010011 FMAX.S

1100000 00000 rs1  rm rd       1010011 FCVT.W.S // rd integer dest (float to signed int)
1100000 00001 rs1  rm rd       1010011 FCVT.WU.S // rd integer dest (float to unsigned int)
1110000 00000 rs1 000 rd       1010011 FMV.X.W // rd integer dest (move bits)

1010000   rs2 rs1 010 rd       1010011 FEQ.S // rd integer dest
1010000   rs2 rs1 001 rd       1010011 FLT.S // rd integer dest
1010000   rs2 rs1 000 rd       1010011 FLE.S // rd integer dest
1110000 00000 rs1 001 rd       1010011 FCLASS.S // rd integer dest

1101000 00000 rs1  rm rd       1010011 FCVT.S.W // rs1 integer value (signed int to float)
1101000 00001 rs1  rm rd       1010011 FCVT.S.WU // rs1 integer value (unsigned int to float)
1111000 00000 rs1 000 rd       1010011 FMV.W.X // rs1 integer value (move bits)
*/