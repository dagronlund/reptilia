module gecko_random_tb
    import gecko_pkg::*;
();
    /* verilator public_flat_rw_on */
    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32)
    ) inst_request (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32)
    ) inst_result (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32)
    ) data_request (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32)
    ) data_result (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32)
    ) float_mem_request (
        .clk,
        .rst
    );
    mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32)
    ) float_mem_result (
        .clk,
        .rst
    );

    stream_intf #(
        .T(logic [7:0])
    ) tty_in (
        .clk,
        .rst
    );
    stream_intf #(
        .T(logic [7:0])
    ) tty_out (
        .clk,
        .rst
    );

    logic       exit_flag;
    logic       error_flag;
    logic [7:0] exit_code;

    // Read-only observation aliases. No production RTL behavior is changed.
    logic       trace_reset_done;
    always_comb trace_reset_done = inst.gecko_decode_inst.reset_done;

    logic trace_decode_valid;
    always_comb
        trace_decode_valid = inst.instruction_command_break.valid && inst.instruction_command_break.ready && inst.inst_result_break.valid && inst.inst_result_break.ready && !rst && inst.gecko_decode_inst.reset_done && inst.gecko_decode_inst.state_temp != 3;

    logic trace_decode_flush;
    always_comb trace_decode_flush = inst.gecko_decode_inst.instruction_status.flush_instruction;

    logic [31:0] trace_decode_pc;
    always_comb trace_decode_pc = inst.instruction_command_break.payload.pc;

    logic [31:0] trace_decode_instruction;
    always_comb trace_decode_instruction = inst.inst_result_break.data;

    logic [2:0] trace_decode_tag;
    always_comb trace_decode_tag = inst.gecko_decode_inst.rd_read_status_front;

    logic trace_decode_execute;
    always_comb trace_decode_execute = inst.gecko_decode_inst.produce_execute;

    logic trace_execute_valid;
    always_comb trace_execute_valid = inst.execute_command.valid && inst.execute_command.ready;

    logic [31:0] trace_execute_pc;
    always_comb trace_execute_pc = inst.execute_command.payload.current_pc;

    logic trace_execute_killed;
    always_comb trace_execute_killed = inst.gecko_execute_inst.mispredicted && !inst.execute_command.payload.pc_updated;

    logic trace_execute_halt;
    always_comb trace_execute_halt = inst.execute_command.payload.halt;

    logic trace_wb_valid;
    always_comb trace_wb_valid = inst.writeback_result.valid && inst.writeback_result.ready;

    logic [4:0] trace_wb_rd;
    always_comb trace_wb_rd = inst.writeback_result.payload.addr;

    logic [2:0] trace_wb_tag;
    always_comb trace_wb_tag = inst.writeback_result.payload.reg_status;

    logic [31:0] trace_wb_value;
    always_comb trace_wb_value = inst.writeback_result.payload.value;

    logic trace_wb_killed;
    always_comb trace_wb_killed = inst.writeback_result.payload.mispredicted;

    logic trace_wb_writes;
    always_comb trace_wb_writes = inst.gecko_decode_inst.rd_write_value_enable;

    logic trace_branch_valid;
    always_comb trace_branch_valid = inst.jump_command.valid && inst.jump_command.ready;

    logic [31:0] trace_branch_pc;
    always_comb trace_branch_pc = inst.jump_command.payload.current_pc;

    logic [31:0] trace_branch_next_pc;
    always_comb trace_branch_next_pc = inst.jump_command.payload.actual_next_pc;

    logic trace_branch_taken;
    always_comb trace_branch_taken = inst.jump_command.payload.branched;

    logic trace_branch_jumped;
    always_comb trace_branch_jumped = inst.jump_command.payload.jumped;

    logic trace_branch_killed;
    always_comb trace_branch_killed = inst.jump_command.payload.mispredicted;

    logic trace_branch_halt;
    always_comb trace_branch_halt = inst.jump_command.payload.halt;

    logic [31:0] trace_reg[0:31];
    always_comb trace_reg = inst.gecko_decode_inst.regfile.register_file_inst.xilinx_distributed_ram_inst.data;
    /* verilator public_off */

    gecko_core #(
        .CONFIG(gecko_get_basic_config(1, 1, 0))
    ) inst (
        .clk,
        .rst,
        .inst_request,
        .inst_result,
        .data_request,
        .data_result,
        .float_mem_request,
        .float_mem_result,
        .tty_in,
        .tty_out,
        .exit_flag,
        .error_flag,
        .exit_code
    );

endmodule
