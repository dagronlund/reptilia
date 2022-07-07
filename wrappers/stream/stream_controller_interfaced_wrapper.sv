module stream_controller_interfaced_wrapper (
    input wire clk, 
    input wire rst
);

    stream_intf inputs [1] (.clk, .rst),
                outputs [1] (.clk, .rst);

    logic [0:0] consume;
    logic [0:0] produce;
    logic enable;

    stream_controller_interfaced inst(
        .clk,
        .rst,
        .inputs,
        .outputs,
        .consume,
        .produce,
        .enable
    );

endmodule
