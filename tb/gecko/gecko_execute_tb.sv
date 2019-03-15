`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

module gecko_execute_tb
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#()();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    std_stream_intf #(.T(gecko_execute_operation_t)) execute_command (.clk, .rst);
    std_stream_intf #(.T(gecko_mem_operation_t)) mem_command (.clk, .rst);
    std_stream_intf #(.T(gecko_operation_t)) execute_result (.clk, .rst);
    std_stream_intf #(.T(gecko_branch_command_t)) branch_command (.clk, .rst);
    std_stream_intf #(.T(gecko_branch_signal_t)) branch_signal (.clk, .rst);

    std_mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .ADDR_BYTE_SHIFTED(1)
    ) mem_data (.clk, .rst);

    gecko_execute gecko_execute_inst(
        .clk, .rst,

        .execute_command, // in
        .mem_command, // out
        .mem_data, // out
        .execute_result, // out
        .branch_command, // out
        .branch_signal // out
    );

    logic read_enable_temp;
    logic [3:0] write_enable_temp;
    logic [31:0] addr_temp;
    logic [31:0] data_temp;
    gecko_mem_operation_t mem_op_temp;
    gecko_operation_t execute_result_temp;
    gecko_execute_operation_t execute_op;

    initial begin
        execute_command.valid = 'b0;
        mem_data.ready = 'b0;
        mem_command.ready = 'b0;
        execute_result.ready = 'b0;
        branch_command.ready = 'b1;
        branch_signal.ready = 'b1;
        execute_op = '{default: 'b0};
        while (rst) @ (posedge clk);

        fork
        begin
            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.reg_addr = 'h3;
            execute_op.op = RV32I_FUNCT3_IR_ADD_SUB;
            execute_command.send(execute_op);

            execute_op.op_type = GECKO_EXECUTE_TYPE_LOAD;
            execute_op.op = RV32I_FUNCT3_LS_W;
            execute_op.reg_addr = 'h4;
            execute_command.send(execute_op);

            execute_op.op_type = GECKO_EXECUTE_TYPE_STORE;
            execute_op.op = RV32I_FUNCT3_LS_W;
            execute_op.reg_addr = 'h5;
            execute_command.send(execute_op);

            execute_op.op_type = GECKO_EXECUTE_TYPE_EXECUTE;
            execute_op.reg_addr = 'h3;
            execute_op.op = RV32I_FUNCT3_IR_ADD_SUB;
            execute_command.send(execute_op);
        end
        begin
            fork
                mem_data.recv(read_enable_temp, write_enable_temp, addr_temp, data_temp);
                mem_command.recv(mem_op_temp);
            join
            @ (posedge clk);
            @ (posedge clk);
            fork
                mem_data.recv(read_enable_temp, write_enable_temp, addr_temp, data_temp);
                mem_command.recv(mem_op_temp);
            join
        end
        begin
            @ (posedge clk);
            @ (posedge clk);
            @ (posedge clk);
            @ (posedge clk);
            @ (posedge clk);
            @ (posedge clk);
            execute_result.recv(execute_result_temp);
        end
        join
    end

endmodule