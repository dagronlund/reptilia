interface stream_intf #(
    parameter type T = logic
)(
    input wire clk = 'b0, rst = 'b0
);

    logic valid, ready;

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

endinterface
