`timescale 1ns/1ps

`include "../lib/rv_mem.svh"

interface rv_mem_intf #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10,
    // Indicates that the address steps by bytes regardless of the data width
    parameter ADDR_BYTE_SHIFTED = 0
)(
    input logic clk = 'b0, rst = 'b0
);

    import rv_mem::*;

    logic valid, ready;
    rv_memory_op op;
    logic [ADDR_WIDTH-1:0] addr;
    logic [DATA_WIDTH-1:0] data;

    modport out(
        output valid,
        input ready,
        output op, addr, data
    );

    modport in(
        input valid,
        output ready,
        input op, addr, data
    );
    
    modport view(
        input valid, ready,
        input op, addr, data
    );

    task send(input rv_memory_op op_in, 
            input logic [ADDR_WIDTH-1:0] addr_in, 
            input logic [DATA_WIDTH-1:0] data_in);
        op <= op_in;
        addr <= addr_in;
        data <= data_in;

        valid <= 1'b1;
        @ (posedge clk);
        while (!ready) @ (posedge clk);
        valid <= 1'b0;
    endtask

    task recv(output rv_memory_op op_out, 
            output logic [ADDR_WIDTH-1:0] addr_out, 
            output logic [DATA_WIDTH-1:0] data_out);
        ready <= 1'b1;
        @ (posedge clk);
        while (!valid) @ (posedge clk);
        ready <= 1'b0;

        op_out = op;
        addr_out = addr;
        data_out = data;
    endtask

endinterface
