//!no_lint

`include "std/std_util.svh"
`include "mem/mem_util.svh"

interface mem_intf #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 10,
    parameter int MASK_WIDTH = DATA_WIDTH / 8,
    parameter int ID_WIDTH = 1,
    // Indicates that the address steps by bytes regardless of the data width
    parameter bit ADDR_BYTE_SHIFTED = 0,
    // Indicates that the bus only carries data (i.e. a read response)
    parameter bit DATA_ONLY = 0
)(
`ifndef __SYNTH_ONLY__
    input wire clk = 'b0, rst = 'b0
`else
    input wire clk, rst
`endif
);

    logic valid /* verilator isolate_assignments*/;
    logic ready /* verilator isolate_assignments*/;

    logic                  read_enable;
    logic [MASK_WIDTH-1:0] write_enable;
    logic [ADDR_WIDTH-1:0] addr;
    logic [DATA_WIDTH-1:0] data;
    logic [ID_WIDTH-1:0]   id;
    logic                  last;

    modport out(
        output valid,
        input ready,
        output read_enable, write_enable, addr, data, id, last
    );

    modport in(
        input valid,
        output ready,
        input read_enable, write_enable, addr, data, id, last
    );
    
    modport view(
        input valid, ready,
        input read_enable, write_enable, addr, data, id, last
    );

`ifndef __SYNTH_ONLY__

    task send(
        input logic                  read_enable_in,
        input logic [MASK_WIDTH-1:0] write_enable_in,
        input logic [ADDR_WIDTH-1:0] addr_in, 
        input logic [DATA_WIDTH-1:0] data_in,
        input logic [ID_WIDTH-1:0] id_in
    );
        read_enable <= read_enable_in;
        write_enable <= write_enable_in;
        addr <= addr_in;
        data <= data_in;
        id <= id_in;
        last <= 'b0;

        valid <= 1'b1;
        @ (posedge clk);
        while (!ready) @ (posedge clk);
        valid <= 1'b0;
    endtask

    task recv(
        output logic                  read_enable_out,
        output logic [MASK_WIDTH-1:0] write_enable_out,
        output logic [ADDR_WIDTH-1:0] addr_out,
        output logic [DATA_WIDTH-1:0] data_out,
        output logic [ID_WIDTH-1:0] id_out
    );
        ready <= 1'b1;
        @ (posedge clk);
        while (!valid) @ (posedge clk);
        ready <= 1'b0;

        read_enable_out = read_enable;
        write_enable_out = write_enable;
        addr_out = addr;
        data_out = data;
        id_out = id;
    endtask

`endif

endinterface
