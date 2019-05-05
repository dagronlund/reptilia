`timescale 1ns/1ps

`ifdef __LINTER__

`include "../../lib/std/std_util.svh"
`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"
`include "../../lib/isa/rv32f.svh"
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
    import gecko::*;
    import basilisk::*;
    import basilisk_decode_util::*;
    import fpu::*;
#(
    parameter int OUTPUT_REGISTER_MODE = 1
)(
    input logic clk, rst,

    std_stream_intf.in float_command, // gecko_float_operation_t

    std_stream_intf.in writeback_result, // basilisk_writeback_result_t    

    std_stream_intf.out encode_command, // basilisk_encode_command_t

    std_stream_intf.out mult_command, // basilisk_mult_command_t
    std_stream_intf.out add_command, // basilisk_add_command_t
    std_stream_intf.out sqrt_command, // basilisk_sqrt_command_t
    std_stream_intf.out divide_command, // basilisk_divide_command_t
    
    std_stream_intf.out convert_command, // basilisk_convert_command_t
    std_stream_intf.out memory_command // basilisk_memory_command_t
);

    typedef enum logic {
        BASILISK_DECODE_STATE_RESET = 'b0,
        BASILISK_DECODE_STATE_NORMAL = 'b1
    } basilisk_decode_state_t;

    logic consume, enable;
    logic produce_encode, produce_mult, produce_add, produce_sqrt, 
            produce_divide, produce_convert, produce_memory;

    std_stream_intf #(.T(basilisk_encode_command_t)) next_encode_command (.clk, .rst);

    std_stream_intf #(.T(basilisk_mult_command_t)) next_mult_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_add_command_t)) next_add_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_sqrt_command_t)) next_sqrt_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_divide_command_t)) next_divide_command (.clk, .rst);

    std_stream_intf #(.T(basilisk_convert_command_t)) next_convert_command (.clk, .rst);
    std_stream_intf #(.T(basilisk_memory_command_t)) next_memory_command (.clk, .rst);

    std_flow_lite #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(7)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({float_command.valid}),
        .ready_input({float_command.ready}),

        .valid_output({
            next_encode_command.valid,
            next_mult_command.valid,
            next_add_command.valid,
            next_sqrt_command.valid,
            next_divide_command.valid,
            next_convert_command.valid,
            next_memory_command.valid
        }),
        .ready_output({
            next_encode_command.ready,
            next_mult_command.ready,
            next_add_command.ready,
            next_sqrt_command.ready,
            next_divide_command.ready,
            next_convert_command.ready,
            next_memory_command.ready
        }),

        .consume, 
        .produce({produce_encode, produce_mult, produce_add, produce_sqrt, 
            produce_divide, produce_convert, produce_memory}), 
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
        .T(basilisk_mult_command_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) mult_command_output_stage (
        .clk, .rst,
        .stream_in(next_mult_command), .stream_out(mult_command)
    );

    std_flow_stage #(
        .T(basilisk_add_command_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) add_commmand_output_stage (
        .clk, .rst,
        .stream_in(next_add_command), .stream_out(add_command)
    );

    std_flow_stage #(
        .T(basilisk_sqrt_command_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) sqrt_command_output_stage (
        .clk, .rst,
        .stream_in(next_sqrt_command), .stream_out(sqrt_command)
    );

    std_flow_stage #(
        .T(basilisk_divide_command_t),
        .MODE(OUTPUT_REGISTER_MODE)
    ) divide_command_output_stage (
        .clk, .rst,
        .stream_in(next_divide_command), .stream_out(divide_command)
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


    logic rd_write_enable;
    rv32_reg_addr_t rd_write_addr;
    rv32_reg_value_t rd_write_value;
    rv32_reg_addr_t rs1_read_addr, rs2_read_addr, rs3_read_addr;
    rv32_reg_value_t rs1_read_value, rs2_read_value, rs3_read_value;

    // Register File
    std_distributed_ram #(
        .DATA_WIDTH($size(rv32_reg_value_t)),
        .ADDR_WIDTH($size(rv32_reg_addr_t)),
        .READ_PORTS(3)
    ) register_file_inst (
        .clk, .rst,

        // Always write to all bits in register
        .write_enable({32{rd_write_enable}}),
        .write_addr(rd_write_addr),
        .write_data_in(rd_write_value),

        .read_addr('{rs1_read_addr, rs2_read_addr, rs3_read_addr}),
        .read_data_out('{rs1_read_value, rs2_read_value, rs3_read_value})
    );

    basilisk_decode_state_t current_state, next_state;
    basilisk_decode_reg_status_t current_reg_status [32], next_reg_status [32];
    rv32_reg_addr_t current_reset_counter, next_reset_counter;
    fpu_round_mode_t current_round_mode, next_round_mode;

    logic reg_status_writeback_enable;
    rv32_reg_addr_t reg_status_writeback_addr;

    always_ff @(posedge clk) begin
        if(rst) begin
            current_state <= BASILISK_DECODE_STATE_RESET;
            current_reg_status <= '{32{BASILISK_DECODE_REG_STATUS_VALID}};
            current_reset_counter <= 'b0;
            current_round_mode <= FPU_ROUND_MODE_EVEN;
        end else if (enable) begin
            current_state <= next_state;
            current_reg_status <= next_reg_status;
            if (reg_status_writeback_enable) begin
                current_reg_status[reg_status_writeback_addr] <= BASILISK_DECODE_REG_STATUS_VALID;
            end
            current_reset_counter <= next_reset_counter;
            current_round_mode <= next_round_mode;
        end else if (reg_status_writeback_enable) begin
            current_reg_status[reg_status_writeback_addr] <= BASILISK_DECODE_REG_STATUS_VALID;
        end
    end

    always_comb begin
        automatic rv32_fields_t inst_fields = float_command.payload.instruction_fields;
        automatic fpu_float_fields_t rs1_fields, rs2_fields, rs3_fields;
        automatic fpu_float_conditions_t rs1_conditions, rs2_conditions, rs3_conditions;
        automatic rv32_reg_value_t immediate_value, sys_value;
        automatic basilisk_memory_op_t mem_op;
        automatic basilisk_convert_op_t convert_op;
        automatic basilisk_encode_op_t encode_op;
        automatic logic enable_macc, convert_signed_integer;
        automatic logic sys_write, sys_set, sys_clear, sys_use_imm;

        consume = (current_state == BASILISK_DECODE_STATE_NORMAL);
        produce_encode = 'b0;
        produce_mult = 'b0;
        produce_add = 'b0;
        produce_sqrt = 'b0;
        produce_divide = 'b0;
        produce_convert = 'b0;
        produce_memory = 'b0;

        next_state = current_state;
        next_reset_counter = current_reset_counter + 'b1;
        next_round_mode = current_round_mode;
        next_reg_status = current_reg_status;

        rs1_read_addr = inst_fields.rs1;
        rs2_read_addr = inst_fields.rs2;
        rs3_read_addr = inst_fields.rs3;

        rs1_fields = fpu_decode_float(rs1_read_value);
        rs2_fields = fpu_decode_float(rs2_read_value);
        rs3_fields = fpu_decode_float(rs3_read_value);

        rs1_conditions = fpu_get_conditions(rs1_read_value);
        rs2_conditions = fpu_get_conditions(rs2_read_value);
        rs3_conditions = fpu_get_conditions(rs3_read_value);

        sys_write = 'b0;
        sys_set = 'b0;
        sys_clear = 'b0;
        sys_use_imm = 'b0;

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
            rs3_fields.sign = ~rs3_fields.sign;
        end
        RV32F_OPCODE_FNMSUB_S: begin
            produce_mult = 'b1;
            enable_macc = 'b1;
            rs1_fields.sign = ~rs1_fields.sign;
        end
        RV32F_OPCODE_FNMADD_S: begin
            produce_mult = 'b1;
            enable_macc = 'b1;
            rs1_fields.sign = ~rs1_fields.sign;
            rs3_fields.sign = ~rs3_fields.sign;
        end
        RV32F_OPCODE_FP_OP_S: begin
            case (rv32f_funct7_t'(inst_fields.funct7))
            RV32F_FUNCT7_FADD_S: begin
                produce_add = 'b1;
            end
            RV32F_FUNCT7_FSUB_S: begin
                produce_add = 'b1;
                rs2_fields.sign = ~rs2_fields.sign;
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
                RV32F_FUNCT3_FSGNJ_S: rs1_fields.sign = rs2_fields.sign;
                RV32F_FUNCT3_FSGNJN_S: rs1_fields.sign = !rs2_fields.sign;
                RV32F_FUNCT3_FSGNJX_S: rs1_fields.sign ^= rs2_fields.sign;
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
                rs1_fields = fpu_decode_float(float_command.payload.rs1_value); // Use integer file
            end
            RV32F_FUNCT7_FMV_W_X: begin
                produce_convert = 'b1;
                convert_op = BASILISK_CONVERT_OP_RAW;
                rs1_fields = fpu_decode_float(float_command.payload.rs1_value); // Use integer file
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

        case (float_command.payload.sys_op)
        RV32I_FUNCT3_SYS_CSRRWI, RV32I_FUNCT3_SYS_CSRRSI, RV32I_FUNCT3_SYS_CSRRCI: sys_value = float_command.payload.sys_imm;
        default: sys_value = float_command.payload.rs1_value;
        endcase

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
            produce_encode = 'b0;
            produce_mult = 'b0;
            produce_add = 'b0;
            produce_sqrt = 'b0;
            produce_divide = 'b0;
            produce_convert = 'b0;
            produce_memory = 'b0;

            case (float_command.payload.sys_op)
            RV32I_FUNCT3_SYS_CSRRW, RV32I_FUNCT3_SYS_CSRRS,
            RV32I_FUNCT3_SYS_CSRRC, RV32I_FUNCT3_SYS_CSRRWI,
            RV32I_FUNCT3_SYS_CSRRSI, RV32I_FUNCT3_SYS_CSRRCI: begin
                produce_encode = (float_command.payload.dest_reg_addr != 'b0); // Don't produce writeback to x0
            end
            endcase

            // Have CSR operation return proper flags
            case (rv32_funct12_t'(float_command.payload.sys_csr))
            RV32F_CSR_FRM: begin
                rs1_fields = fpu_decode_float({30'b0, current_round_mode});
                if (sys_write) begin
                    next_round_mode = fpu_round_mode_t'(sys_value);
                end else if (sys_set) begin
                    next_round_mode = fpu_round_mode_t'(sys_value | next_round_mode);
                end else if (sys_clear) begin
                    next_round_mode = fpu_round_mode_t'(~sys_value & next_round_mode);
                end
            end
            default: rs1_fields = fpu_decode_float({32'b0});
            endcase
        // Stall for register availability
        end else if (!basilisk_decode_depend_registers(inst_fields, current_reg_status)) begin
            consume = 'b0;
            produce_encode = 'b0;
            produce_mult = 'b0;
            produce_add = 'b0;
            produce_sqrt = 'b0;
            produce_divide = 'b0;
            produce_convert = 'b0;
            produce_memory = 'b0;
        end else if (basilisk_decode_depend_rd(inst_fields)) begin
            next_reg_status[inst_fields.rd] = BASILISK_DECODE_REG_STATUS_INVALID;
        end

        next_encode_command.payload = '{
            dest_reg_addr: float_command.payload.dest_reg_addr,
            dest_reg_status: float_command.payload.dest_reg_status,
            jump_flag: float_command.payload.jump_flag,
            signed_integer: convert_signed_integer,
            op: encode_op,
            a: rs1_fields,
            b: rs2_fields,
            conditions_a: rs1_conditions,
            conditions_b: rs2_conditions
        };

        next_mult_command.payload = '{
            dest_reg_addr: inst_fields.rd,
            dest_offset_addr: 'b0,
            enable_macc: enable_macc,
            a: rs1_fields,
            b: rs2_fields,
            c: rs3_fields,
            conditions_a: rs1_conditions,
            conditions_b: rs2_conditions,
            conditions_c: rs3_conditions,
            mode: current_round_mode
        };

        next_add_command.payload = '{
            dest_reg_addr: inst_fields.rd,
            dest_offset_addr: 'b0,
            a: rs1_fields,
            b: rs2_fields,
            conditions_a: rs1_conditions,
            conditions_b: rs2_conditions,
            mode: current_round_mode
        };

        next_sqrt_command.payload = '{
            dest_reg_addr: inst_fields.rd,
            dest_offset_addr: 'b0,
            a: rs1_fields,
            conditions_a: rs1_conditions,
            mode: current_round_mode
        };

        next_divide_command.payload = '{
            dest_reg_addr: inst_fields.rd,
            dest_offset_addr: 'b0,
            a: rs1_fields,
            b: rs2_fields,
            conditions_a: rs1_conditions,
            conditions_b: rs2_conditions,
            mode: current_round_mode
        };
        
        next_convert_command.payload = '{
            dest_reg_addr: inst_fields.rd,
            dest_offset_addr: 'b0,
            a: rs1_fields,
            b: rs2_fields,
            conditions_a: rs1_conditions,
            conditions_b: rs2_conditions,
            op: convert_op,
            signed_integer: convert_signed_integer
        };

        next_memory_command.payload = '{
            dest_reg_addr: inst_fields.rd,
            dest_offset_addr: 'b0,
            a: {rs1_fields.sign, rs1_fields.exponent, rs1_fields.mantissa},
            op: mem_op,
            mem_base_addr: float_command.payload.rs1_value,
            mem_offset_addr: immediate_value
        };

        // Handle writebacks
        writeback_result.ready = (current_state == BASILISK_DECODE_STATE_NORMAL);

        rd_write_enable = 'b0;
        rd_write_addr = writeback_result.payload.dest_reg_addr;
        rd_write_value = writeback_result.payload.result;

        reg_status_writeback_enable = 'b0;
        reg_status_writeback_addr = writeback_result.payload.dest_reg_addr;

        if (current_state == BASILISK_DECODE_STATE_RESET) begin
            rd_write_enable = 'b1;
            rd_write_addr = current_reset_counter;
            rd_write_value = 'b0;
        end else if (writeback_result.valid) begin
            rd_write_enable = 'b1;
            reg_status_writeback_enable = 'b1;
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