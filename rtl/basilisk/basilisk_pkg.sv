//!import riscv/riscv_pkg
//!import riscv/riscv32_pkg
//!import riscv/riscv32f_pkg
//!import fpu/fpu_pkg
//!import fpu/fpu_add_pkg
//!import fpu/fpu_mult_pkg
//!import fpu/fpu_divide_pkg
//!import fpu/fpu_sqrt_pkg
//!import gecko/gecko_pkg

package basilisk_pkg;

    import rv32::*;
    import rv32f::*;
    import fpu::*;
    import fpu_add::*;
    import fpu_mult::*;
    import fpu_divide::*;
    import fpu_sqrt::*;
    import gecko::*;

    parameter int BASILISK_VECTOR_WIDTH = 16;
    parameter int BASILISK_VECTOR_ADDR_WIDTH = $clog2(BASILISK_VECTOR_WIDTH) + 1;
    parameter int BASILISK_VECTOR_BITWIDTH = BASILISK_VECTOR_WIDTH * $bits(rv32_reg_value_t);
    parameter int BASILISK_COMPUTE_WIDTH = 8;

    parameter int BASILISK_OFFSET_ADDR_WIDTH_RAW = $clog2(BASILISK_VECTOR_WIDTH/BASILISK_COMPUTE_WIDTH);
    parameter int BASILISK_OFFSET_ADDR_WIDTH = (BASILISK_OFFSET_ADDR_WIDTH_RAW > 0) ?
            BASILISK_OFFSET_ADDR_WIDTH_RAW : 1;
    typedef logic [BASILISK_OFFSET_ADDR_WIDTH-1:0] basilisk_offset_addr_t;

    // typedef logic [BASILISK_VECTOR_BITWIDTH-1:0] basilisk_vector_t;
    typedef logic [($clog2(BASILISK_VECTOR_WIDTH)):0] basilisk_vector_length_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        fpu_result_t result;
    } basilisk_result_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        rv32_reg_value_t result;
    } basilisk_writeback_result_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        fpu_float_fields_t a, b; // a + b
        fpu_float_conditions_t conditions_a, conditions_b;
        fpu_round_mode_t mode;
    } basilisk_add_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        fpu_add_exp_result_t result;
    } basilisk_add_exponent_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        fpu_add_op_result_t result;
    } basilisk_add_operation_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        logic enable_macc;
        fpu_float_fields_t a, b, c; // a * b or (a * b) + c
        fpu_float_conditions_t conditions_a, conditions_b, conditions_c;
        fpu_round_mode_t mode;
    } basilisk_mult_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        logic enable_macc;
        fpu_float_fields_t c;
        fpu_float_conditions_t conditions_c;
        fpu_mult_exp_result_t result;
    } basilisk_mult_exponent_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        logic enable_macc;
        fpu_float_fields_t c;
        fpu_float_conditions_t conditions_c;
        fpu_mult_op_result_t result;
    } basilisk_mult_operation_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        fpu_float_fields_t c;
        fpu_float_conditions_t conditions_c;
        fpu_result_t result;
    } basilisk_mult_add_normalize_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        fpu_float_fields_t a, b; // a / b
        fpu_float_conditions_t conditions_a, conditions_b;
        fpu_round_mode_t mode;
    } basilisk_divide_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        fpu_div_result_t result;
    } basilisk_divide_result_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        fpu_float_fields_t a; // sqrt(a)
        fpu_float_conditions_t conditions_a;
        fpu_round_mode_t mode;
    } basilisk_sqrt_command_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        fpu_sqrt_result_t result;
    } basilisk_sqrt_operation_t;

    typedef enum logic [1:0] {
        BASILISK_CONVERT_OP_MIN = 'b00,
        BASILISK_CONVERT_OP_MAX = 'b01,
        BASILISK_CONVERT_OP_RAW = 'b10,
        BASILISK_CONVERT_OP_CNV = 'b11
    } basilisk_convert_op_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        fpu_float_fields_t a, b;
        fpu_float_conditions_t conditions_a, conditions_b;
        basilisk_convert_op_t op;
        logic signed_integer;
    } basilisk_convert_command_t;

    typedef enum logic {
        BASILISK_MEMORY_OP_LOAD = 'b0,
        BASILISK_MEMORY_OP_STORE = 'b1
    } basilisk_memory_op_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        basilisk_offset_addr_t dest_offset_addr;
        rv32_reg_value_t a;
        basilisk_memory_op_t op;
        rv32_reg_value_t mem_base_addr;
        rv32_reg_value_t mem_offset_addr;
    } basilisk_memory_command_t;

    typedef enum logic [2:0] {
        BASILISK_ENCODE_OP_RAW = 'b000,
        BASILISK_ENCODE_OP_CONVERT = 'b001,
        BASILISK_ENCODE_OP_EQUAL = 'b010,
        BASILISK_ENCODE_OP_LT = 'b011,
        BASILISK_ENCODE_OP_LE = 'b100,
        BASILISK_ENCODE_OP_CLASS = 'b101
    } basilisk_encode_op_t;

    typedef struct packed {
        rv32_reg_addr_t dest_reg_addr;
        gecko_reg_status_t dest_reg_status;
        gecko_jump_flag_t jump_flag;

        basilisk_encode_op_t op;
        logic signed_integer;
        fpu_float_fields_t a, b;
        fpu_float_conditions_t conditions_a, conditions_b;
    } basilisk_encode_command_t;

endpackage
