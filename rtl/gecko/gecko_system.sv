//!import std/std_pkg.sv
//!import stream/stream_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import riscv/riscv32i_pkg.sv
//!import gecko/gecko_pkg.sv
//!import stream/stream_intf.sv
//!import std/std_register.sv
//!import std/std_counter_pipelined.sv
//!import stream/stream_stage.sv
//!import stream/stream_controller.sv
//!wrapper gecko/gecko_system_wrapper.sv

`include "std/std_util.svh"
`include "mem/mem_util.svh"

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
    parameter bit ENABLE_TTY_IO = 0,
    parameter bit ENABLE_PERFORMANCE_COUNTERS = 0
)(
    input wire clk, 
    input wire rst,
    input gecko_performance_stats_t performance_stats,
    stream_intf.in system_command, // gecko_system_operation_t
    stream_intf.out system_result, // gecko_operation_t

    input logic instruction_decoded,
    input logic instruction_executed,

    stream_intf.in     tty_in, // logic [7:0]
    stream_intf.out    tty_out, // logic [7:0]
    output logic [7:0] exit_code
);

    typedef logic [7:0]  byte_t;
    typedef logic [31:0] word_t;

    function automatic riscv32_reg_value_t update_csr(
            input riscv32_reg_value_t current_value,
            input gecko_system_operation_t op
    );
        case (op.sys_op)
        RISCV32I_FUNCT3_SYS_CSRRW:  return op.rs1_value;
        RISCV32I_FUNCT3_SYS_CSRRS:  return current_value | op.rs1_value;
        RISCV32I_FUNCT3_SYS_CSRRC:  return current_value & ~op.rs1_value;
        RISCV32I_FUNCT3_SYS_CSRRWI: return op.imm_value;
        RISCV32I_FUNCT3_SYS_CSRRSI: return current_value | op.imm_value;
        RISCV32I_FUNCT3_SYS_CSRRCI: return current_value & ~op.imm_value;
        default:                    return '0;
        endcase
    endfunction

    logic consume_command, produce_result, enable;
    logic consume_tty, produce_tty;

    stream_intf #(.T(gecko_operation_t)) system_result_next (.clk, .rst);
    stream_intf #(.T(logic [7:0]))       tty_in_buffered    (.clk, .rst);
    stream_intf #(.T(logic [7:0]))       tty_out_next       (.clk, .rst);

    stream_controller #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(2)
    ) stream_controller_inst (
        .clk, .rst,

        .valid_input({system_command.valid, tty_in_buffered.valid}),
        .ready_input({system_command.ready, tty_in_buffered.ready}),
        
        .valid_output({system_result_next.valid, tty_out_next.valid}),
        .ready_output({system_result_next.ready, tty_out_next.ready}),

        .consume({consume_command, consume_tty}),
        .produce({produce_result,  produce_tty}),

        .enable
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(gecko_operation_t)
    ) system_result_stage_inst (
        .clk, .rst,
        .stream_in(system_result_next), .stream_out(system_result)
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_BUFFERED),
        .T(logic [7:0])
    ) tty_in_stage_inst (
        .clk, .rst,
        .stream_in(tty_in), .stream_out(tty_in_buffered)
    );

    stream_stage #(
        .CLOCK_INFO(CLOCK_INFO),
        .PIPELINE_MODE(STREAM_PIPELINE_MODE_BUFFERED),
        .T(logic [7:0])
    ) tty_out_stage_inst (
        .clk, .rst,
        .stream_in(tty_out_next), .stream_out(tty_out)
    );

    // TODO: Use different counters for RDCYCLE and RDTIME to support processor pausing
    logic [31:0] perf_counter_increments [7];
    always_comb perf_counter_increments = '{
        32'b1, // clock cycles
        {30'b0, {1'b0, instruction_decoded} + {1'b0, instruction_executed}},
        {31'b0, performance_stats.instruction_mispredicted},
        {31'b0, performance_stats.instruction_data_stalled},
        {31'b0, performance_stats.instruction_control_stalled},
        {31'b0, performance_stats.frontend_stalled},
        {31'b0, performance_stats.backend_stalled}
    };

    logic [63:0] perf_counters [7];

    genvar k;
    generate
    for (k = 0; k < 7; k++) begin
        std_counter_pipelined #(
            .CLOCK_INFO(CLOCK_INFO),
            .PIPELINE_WIDTH(32),
            .PIPELINE_COUNT(2),
            .RESET_VECTOR('b0)
        ) counter_inst (
            .clk, .rst,
            .increment(perf_counter_increments[k]),
            .value(perf_counters[k]),
            .overflowed()
        );
    end
    endgenerate

    logic [7:0] exit_code_next;

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic [7:0]),
        .RESET_VECTOR('b0)
    ) exit_code_register_inst (
        .clk, .rst,
        .enable,
        .next(exit_code_next),
        .value(exit_code)
    );

    always_comb begin
        automatic gecko_system_operation_t command_in;

        command_in = gecko_system_operation_t'(system_command.payload);

        consume_command = 'b1;
        consume_tty = 'b0;
        produce_tty = 'b0;

        exit_code_next = exit_code;
        tty_out_next.payload = 'b0;

        system_result_next.payload = '{default: 'b0};
        system_result_next.payload.addr = command_in.reg_addr;
        system_result_next.payload.reg_status = command_in.reg_status;
        system_result_next.payload.jump_flag = command_in.jump_flag;
        system_result_next.payload.value = 'b0;

        if (ENABLE_PERFORMANCE_COUNTERS) begin
            case (command_in.csr)
            RISCV32I_CSR_CYCLE: system_result_next.payload.value = perf_counters[0][31:0];
            RISCV32I_CSR_TIME: system_result_next.payload.value = perf_counters[0][31:0];
            RISCV32I_CSR_INSTRET: system_result_next.payload.value = perf_counters[1][31:0];

            12'hC03: system_result_next.payload.value = perf_counters[2][31:0];
            12'hC04: system_result_next.payload.value = perf_counters[3][31:0];
            12'hC05: system_result_next.payload.value = perf_counters[4][31:0];
            12'hC06: system_result_next.payload.value = perf_counters[5][31:0];
            12'hC07: system_result_next.payload.value = perf_counters[6][31:0];

            RISCV32I_CSR_CYCLEH: system_result_next.payload.value = perf_counters[0][63:32];
            RISCV32I_CSR_TIMEH: system_result_next.payload.value = perf_counters[0][63:32];
            RISCV32I_CSR_INSTRETH: system_result_next.payload.value = perf_counters[1][63:32];
            default: begin end
            endcase
        end

        tty_out_next.payload = byte_t'(update_csr('b0, command_in));

        if (ENABLE_TTY_IO) begin
            case (command_in.csr)
            12'h800: system_result_next.payload.value = word_t'(exit_code);
            12'h801: system_result_next.payload.value = 'b0;
            12'h802: system_result_next.payload.value = word_t'(tty_in_buffered.payload);
            default: begin end
            endcase
        end

        produce_result = (command_in.reg_addr != 'b0); // Don't produce writeback to x0

        case (command_in.sys_op)
        RISCV32I_FUNCT3_SYS_ENV: begin // System Op
            produce_result = 'b0;
        end
        RISCV32I_FUNCT3_SYS_CSRRW, 
        RISCV32I_FUNCT3_SYS_CSRRS, 
        RISCV32I_FUNCT3_SYS_CSRRC,
        RISCV32I_FUNCT3_SYS_CSRRWI, 
        RISCV32I_FUNCT3_SYS_CSRRSI, 
        RISCV32I_FUNCT3_SYS_CSRRCI: begin // CSR Op
            if (ENABLE_TTY_IO) begin
                case (command_in.csr)
                12'h800: exit_code_next = byte_t'(update_csr(word_t'(exit_code), command_in));
                12'h801: produce_tty = 'b1;
                12'h802: consume_tty = 'b1;
                default: begin end
                endcase
            end
        end
        default: begin
            produce_result = 'b0;
        end
        endcase
    end

endmodule
