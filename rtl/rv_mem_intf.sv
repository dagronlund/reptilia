`timescale 1ns/1ps

`include "../lib/rv_util.svh"
`include "../lib/rv_mem.svh"

interface rv_mem_intf #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
)(
    input logic clk, rst
);

    import rv_mem::*;

    // logic clk, rst;

    logic valid, ready;
    rv_memory_op op;
    logic [ADDR_WIDTH-1:0] addr;
    logic [DATA_WIDTH-1:0] data;

    // logic block_in, block_out; // Placeholder signals for stream control

    modport out(
        output valid,
        input ready,
        output op, addr, data
        // output block_out
    );

    modport in(
        input valid,
        output ready,
        input op, addr, data
        // output block_in
    );
    
    modport view(
        input valid, ready,
        input op, addr, data
        // input block_in, block_out
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

module rv_mem_intf_in_null(
    rv_mem_intf.in mem
);

    import rv_mem::*;

    (*dont_touch = "true"*) logic valid;
    (*dont_touch = "true"*) logic ready;
    (*dont_touch = "true"*) rv_memory_op op;
    (*dont_touch = "true"*) logic [mem.ADDR_WIDTH-1:0] addr;
    (*dont_touch = "true"*) logic [mem.DATA_WIDTH-1:0] data;

    always_comb begin
        valid = mem.valid;
        mem.ready = ready;
        op = mem.op;
        addr = mem.addr;
        data = mem.data;
    end

endmodule

module rv_mem_intf_out_null(
    rv_mem_intf.out mem
);

    import rv_mem::*;

    (*dont_touch = "true"*) logic valid;
    (*dont_touch = "true"*) logic ready;
    (*dont_touch = "true"*) rv_memory_op op;
    (*dont_touch = "true"*) logic [mem.ADDR_WIDTH-1:0] addr;
    (*dont_touch = "true"*) logic [mem.DATA_WIDTH-1:0] data;

    always_comb begin
        mem.valid = valid;
        ready = mem.ready;
        mem.op = op;
        mem.addr = addr;
        mem.data = data;
    end

endmodule