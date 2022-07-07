//!no_lint

interface stream_intf #(
    parameter type T = logic,
    parameter logic [$bits(T)-1:0] T_LOGIC = 'b0
)(
`ifndef __SYNTH_ONLY__
    input wire clk = 'b0, rst = 'b0
`else
    input wire clk, rst
`endif
);

    logic valid /* verilator isolate_assignments*/;
    logic ready /* verilator isolate_assignments*/;

    T payload;

    modport out(
        output valid,
        input ready,
        output payload
    );

    modport in(
        input valid,
        output ready,
        input payload
    );
    
    modport view(
        input valid, ready,
        input payload
    );

`ifndef __SYNTH_ONLY__

    task send(
        input T payload_in
    );
        payload <= payload_in;

        valid <= 1'b1;
        @ (posedge clk);
        while (!ready) @ (posedge clk);
        valid <= 1'b0;
    endtask

    task recv(
        output T payload_out
    );
        ready <= 1'b1;
        @ (posedge clk);
        while (!valid) @ (posedge clk);
        ready <= 1'b0;

        payload_out = payload;
    endtask

`endif

endinterface
