`timescale 1ns/1ps

module flow_tb();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    rv_interrupt_intf in0(.*);
    rv_interrupt_intf in1(.*);
    rv_interrupt_intf out0(.*);
    rv_interrupt_intf out1(.*);

    // task automatic send(ref logic valid, ref logic ready);
    //     valid = 'b1;
    //     @ (posedge clk);
    //     while (!ready) @ (posedge clk);
    //     valid = 'b0;
    // endtask

    // task automatic recv(ref logic valid, ref logic ready);
    //     ready = 'b1;
    //     @ (posedge clk);
    //     while (!valid) @ (posedge clk);
    //     ready = 'b0;
    // endtask

    logic enable;
    logic [1:0] enable_output, consume, produce;
    logic [1:0] valid_input, ready_input, valid_output, ready_output;

    assign valid_input = {in1.valid, in0.valid};
    assign {in1.ready, in0.ready} = ready_input;

    assign {out1.valid, out0.valid} = valid_output;
    assign ready_output = {out1.ready, out0.ready};

    flow #(2, 2) flow_inst (.*);

    initial begin
        in0.valid = 'b0;
        in1.valid = 'b0;
        out0.ready = 'b0;
        out1.ready = 'b0;
        while (rst) @ (posedge clk);
        fork
            in0.interrupt();
            in1.interrupt();
            out0.pause();
            out1.pause();
            // send(valid_input[0], ready_input[0]);
            // send(valid_input[1], ready_input[1]);
            // recv(valid_output[0], ready_output[0]);
            // recv(valid_output[1], ready_output[1]);
        join
    end

    initial begin
        consume = 'b00;
        produce = 'b00;
        while (rst) @ (posedge clk);
        do @ (posedge clk); while (!enable);
        consume <= 'b00;
        produce <= 'b00;
        do @ (posedge clk); while (!enable);
        consume <= 'b01;
        produce <= 'b01;
        do @ (posedge clk); while (!enable);
        consume <= 'b10;
        produce <= 'b10;
        do @ (posedge clk); while (!enable);
        consume <= 'b11;
        produce <= 'b11;
    end

endmodule
