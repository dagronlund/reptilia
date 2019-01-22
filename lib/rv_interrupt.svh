`ifndef __RV_INTERRUPT__
`define __RV_INTERRUPT__

`include "../lib/rv_util.svh"

interface rv_interrupt_intf #()(
    input logic clk = 'b0, rst = 'b0
);

    logic valid, ready;

    modport out(
        output valid,
        input ready
    );

    modport in(
        input valid,
        output ready
    );
    
    modport view(
        input valid, ready
    );

    task interrupt();
        valid <= 1'b1;
        @ (posedge clk);
        while (!ready) @ (posedge clk);
        valid <= 1'b0;
    endtask

    task pause();
        ready <= 1'b1;
        @ (posedge clk);
        while (!valid) @ (posedge clk);
        ready <= 1'b0;
    endtask

endinterface

`endif
