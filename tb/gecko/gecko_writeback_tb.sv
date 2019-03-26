`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"
`include "../../lib/std/std_mem.svh"

`include "../../lib/isa/rv.svh"
`include "../../lib/isa/rv32.svh"
`include "../../lib/isa/rv32i.svh"

`include "../../lib/gecko/gecko.svh"

module gecko_writeback_tb
    import rv::*;
    import rv32::*;
    import rv32i::*;
    import gecko::*;
#()();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    std_stream_intf #(.T(gecko_operation_t)) execute_result (.clk, .rst);
    std_stream_intf #(.T(gecko_mem_operation_t)) mem_command (.clk, .rst);
    std_stream_intf #(.T(gecko_operation_t)) system_result (.clk, .rst);
    std_stream_intf #(.T(gecko_operation_t)) writeback_result (.clk, .rst);

    std_mem_intf #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .ADDR_BYTE_SHIFTED(1)
    ) mem_result (.clk, .rst);

    gecko_writeback gecko_writeback_inst(
        .clk, .rst,

        .execute_result,
        .mem_command,
        .mem_result,
        .system_result,
        .writeback_result
    );

    initial begin
        execute_result.valid = 'b0;
        mem_command.valid = 'b0;
        system_result.valid = 'b0;
        mem_result.valid = 'b0;
        writeback_result.ready = 'b1;
        while (rst) @ (posedge clk);

        fork
        begin
            fork
                mem_command.send('{addr: 'h1F, reg_status: 'd0,
                    op: RV32I_FUNCT3_LS_W, offset: 'h2});
                mem_result.send(0, 0, 0, 'hAABBCCDD);
            join
        end
        begin
            execute_result.send('{value: 'h42, addr: 'h1F, reg_status: 'd2, speculative: 'b0});
            execute_result.send('{value: 'h42, addr: 'h1F, reg_status: 'd0, speculative: 'b0});
        end
        begin
            system_result.send('{value: 'h42, addr: 'h1F, reg_status: 'd1, speculative: 'b0});
            system_result.send('{value: 'h42, addr: 'h1F, reg_status: 'd3, speculative: 'b0});
        end
        join
    end

endmodule
