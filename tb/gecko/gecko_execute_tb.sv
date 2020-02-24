`timescale 1ns/1ps

module gecko_execute_tb
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import riscv32m_pkg::*;
    import gecko_pkg::*;
#()();

    localparam std_clock_info_t CLOCK_INFO = 'b0;

    logic clk, rst;
    clk_rst_gen #() clk_rst_gen_inst(.clk, .rst);

    stream_intf #(.T(gecko_execute_operation_t)) execute_command (.clk, .rst);

    stream_intf #(.T(gecko_mem_operation_t)) mem_command (.clk, .rst);
    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32), .ADDR_BYTE_SHIFTED(1)) mem_request (.clk, .rst);
    stream_intf #(.T(gecko_operation_t)) execute_result (.clk, .rst);
    stream_intf #(.T(gecko_jump_operation_t)) jump_command (.clk, .rst);

    gecko_execute #(
        .CLOCK_INFO(CLOCK_INFO),
    // parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    // parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
        .ENABLE_INTEGER_MATH(1)
    ) gecko_execute_inst (
        .clk, .rst,

        .execute_command, // gecko_execute_operation_t

        .mem_command, // gecko_mem_operation_t
        .mem_request,
        .execute_result, // gecko_operation_t
        .jump_command // gecko_jump_operation_t
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
        
        mem_request.ready = 'b0;
        mem_command.ready = 'b0;
        execute_result.ready = 'b0;
        jump_command.ready = 'b1;
        
        execute_op = '{default: 'b0};

        @ (posedge clk);
        while (std_is_reset_active(CLOCK_INFO, rst)) @ (posedge clk);

        // typedef struct packed {

        //     gecko_execute_type_t op_type;
        //     riscv32i_funct3_t op;
        //     gecko_alternate_t alu_alternate;

        //     riscv32_reg_value_t rs1_value, rs2_value, mem_value, jump_value;
        // } gecko_execute_operation_t;

        // RISCV32M_FUNCT3_MUL = 'h0,
        // RISCV32M_FUNCT3_MULH = 'h1,
        // RISCV32M_FUNCT3_MULHSU = 'h2,
        // RISCV32M_FUNCT3_MULHU = 'h3,
        // RISCV32M_FUNCT3_DIV = 'h4,
        // RISCV32M_FUNCT3_DIVU = 'h5,
        // RISCV32M_FUNCT3_REM = 'h6,
        // RISCV32M_FUNCT3_REMU = 'h7

        fork
        begin
            // 4 * 4 = 16
            execute_op.op_type = GECKO_EXECUTE_TYPE_MUL_DIV;
            execute_op.op = riscv32i_funct3_t'(RISCV32M_FUNCT3_MUL);
            execute_op.rs1_value = 'd4;
            execute_op.rs2_value = 'd4;
            execute_command.send(execute_op);

            // -1 * -1 = 1
            execute_op.op_type = GECKO_EXECUTE_TYPE_MUL_DIV;
            execute_op.op = riscv32i_funct3_t'(RISCV32M_FUNCT3_MUL);
            execute_op.rs1_value = 'hffff_ffff;
            execute_op.rs2_value = 'hffff_ffff;
            execute_command.send(execute_op);

            // -2 * -1 = 2
            execute_op.op_type = GECKO_EXECUTE_TYPE_MUL_DIV;
            execute_op.op = riscv32i_funct3_t'(RISCV32M_FUNCT3_MUL);
            execute_op.rs1_value = 'hffff_ffff;
            execute_op.rs2_value = 'hffff_fffe;
            execute_command.send(execute_op);

            // 24 / 7 = 3
            execute_op.op_type = GECKO_EXECUTE_TYPE_MUL_DIV;
            execute_op.op = riscv32i_funct3_t'(RISCV32M_FUNCT3_DIVU);
            execute_op.rs1_value = 'd24;
            execute_op.rs2_value = 'd7;
            execute_command.send(execute_op);

            // 24 % 7 = 3
            execute_op.op_type = GECKO_EXECUTE_TYPE_MUL_DIV;
            execute_op.op = riscv32i_funct3_t'(RISCV32M_FUNCT3_REMU);
            execute_op.rs1_value = 'd24;
            execute_op.rs2_value = 'd7;
            execute_command.send(execute_op);

            // 16 / 3 = 5
            execute_op.op_type = GECKO_EXECUTE_TYPE_MUL_DIV;
            execute_op.op = riscv32i_funct3_t'(RISCV32M_FUNCT3_DIVU);
            execute_op.rs1_value = 'd16;
            execute_op.rs2_value = 'd3;
            execute_command.send(execute_op);

            // 0xAAAA_AAAB * 0x2fe7d
            execute_op.op_type = GECKO_EXECUTE_TYPE_MUL_DIV;
            execute_op.op = riscv32i_funct3_t'(RISCV32M_FUNCT3_MULH);
            execute_op.rs1_value = 'hAAAA_AAAB;
            execute_op.rs2_value = 'h2fe7d;
            execute_command.send(execute_op);

            // // 0xff000 * 0xff000
            // execute_op.op_type = GECKO_EXECUTE_TYPE_MUL_DIV;
            // execute_op.op = riscv32i_funct3_t'(RISCV32M_FUNCT3_MULH);
            // execute_op.rs1_value = 'hff000;
            // execute_op.rs2_value = 'hff000;
            // execute_command.send(execute_op);
        end
        // begin
        //     fork
        //         mem_request.recv(read_enable_temp, write_enable_temp, addr_temp, data_temp);
        //         mem_command.recv(mem_op_temp);
        //     join
        //     @ (posedge clk);
        //     @ (posedge clk);
        //     fork
        //         mem_request.recv(read_enable_temp, write_enable_temp, addr_temp, data_temp);
        //         mem_command.recv(mem_op_temp);
        //     join
        // end
        begin
            while ('b1) begin
                execute_result.recv(execute_result_temp);
            end
        end
        join

        @ (posedge clk);
        $finish();
    end

endmodule