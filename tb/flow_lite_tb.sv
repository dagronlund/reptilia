`timescale 1ns/1ps

module flow_lite_tb();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    std_stream_intf #(.T(int)) stream_in0 (.clk, .rst);
    std_stream_intf #(.T(int)) stream_in1 (.clk, .rst);

    std_stream_intf #(.T(int)) stream_mid0 (.clk, .rst);
    std_stream_intf #(.T(int)) stream_mid1 (.clk, .rst);

    std_stream_intf #(.T(int)) stream_out0 (.clk, .rst);
    std_stream_intf #(.T(int)) stream_out1 (.clk, .rst);

    logic enable;
    logic [1:0] consume, produce;

    std_flow_lite #(
        .NUM_INPUTS(2),
        .NUM_OUTPUTS(2)
    ) std_flow_lite_inst (
        .clk, .rst,

        .valid_input({stream_in0.valid, stream_in1.valid}),
        .ready_input({stream_in0.ready, stream_in1.ready}),

        .valid_output({stream_mid0.valid, stream_mid1.valid}),
        .ready_output({stream_mid0.ready, stream_mid1.ready}),

        .consume({consume[0], consume[1]}),
        .produce({produce[0], produce[1]}),
        .enable(enable)
    );

    std_flow_stage #(
        .T(int),
        .MODE(2)
    ) std_flow_output_inst0 (
        .clk, .rst,

        .stream_in(stream_mid0),
        .stream_out(stream_out0)
    );

    std_flow_stage #(
        .T(int),
        .MODE(2)
    ) std_flow_output_inst1 (
        .clk, .rst,

        .stream_in(stream_mid1),
        .stream_out(stream_out1)
    );

    int temp;

    initial begin
        stream_in0.valid = 'b0;
        stream_in1.valid = 'b0;
        stream_out0.ready = 'b0;
        stream_out1.ready = 'b0;
        while (rst) @ (posedge clk);

        fork
            begin
                stream_in0.send('h42);
                stream_in0.send('h69);
                stream_in0.send('h99);
            end
            begin
                stream_in1.send('h1);
                stream_in1.send('h1);
                stream_in1.send('h99);
            end
            begin
                stream_out0.recv(temp);
                stream_out0.recv(temp);
            end
        join
    end

    logic [3:0] state;

    always_ff @(posedge clk) begin
        if(rst) begin
            state <= 'b0;
        end else if (enable) begin
            state <= state + 1;
        end
    end

    always_comb begin
        stream_mid0.payload = stream_in0.payload;
        produce[0] = 'b1;
        produce[1] = 'b0;
        consume = 'b11;
        // produce = state[3:2];
        // consume = state[1:0];
    end

endmodule
