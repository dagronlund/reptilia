//!import stream/stream_controller.sv

/*
 * A stateless manager of valid/ready pairs that translates consume/produce
 * signals into the correct output signals.
 */
module stream_controller_gated #(
    parameter int NUM_INPUTS = 1, 
    parameter int NUM_OUTPUTS = 1
)(
    input wire clk, 
    input wire rst,

    input wire enable_in,

    input wire [NUM_INPUTS-1:0] valid_input,
    output logic [NUM_INPUTS-1:0] ready_input,

    output logic [NUM_OUTPUTS-1:0] valid_output,
    input wire [NUM_OUTPUTS-1:0] ready_output,

    input wire [NUM_INPUTS-1:0] consume, // If input being read this cycle
    input wire [NUM_OUTPUTS-1:0] produce, // If an output will be present next cycle

    output logic enable // Enable for current state
);

    logic [NUM_INPUTS-1:0] consume_temp;
    logic [NUM_OUTPUTS-1:0] produce_temp;
    logic enable_temp;

    stream_controller #(
        .NUM_INPUTS(NUM_INPUTS),
        .NUM_OUTPUTS(NUM_OUTPUTS)
    ) stream_controller_inst (
        .clk, .rst,

        .valid_input, .ready_input,
        .valid_output, .ready_output,
        .consume(consume_temp), .produce(produce_temp),
        .enable(enable_temp)
    );

    always_comb begin
        for (int i = 0; i < NUM_INPUTS; i++) begin
            consume_temp[i] = consume[i] && enable_in;
        end

        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            produce_temp[i] = produce[i] && enable_in;
        end

        enable = enable_temp && enable_in;
    end

endmodule
