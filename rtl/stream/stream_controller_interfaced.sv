//!import stream/stream_intf.sv
//!import stream/stream_controller.sv
//!wrapper stream/stream_controller_interfaced_wrapper.sv

module stream_controller_interfaced #(
    parameter int NUM_INPUTS = 1, 
    parameter int NUM_OUTPUTS = 1
)(
    input wire clk, rst,

    stream_intf.in inputs [NUM_INPUTS],
    stream_intf.out outputs [NUM_OUTPUTS],

    input wire [NUM_INPUTS-1:0] consume, // If input being read this cycle
    input wire [NUM_OUTPUTS-1:0] produce, // If an output will be present next cycle

    output logic enable // Enable for current state
);

    logic [NUM_INPUTS-1:0] valid_input;
    logic [NUM_INPUTS-1:0] ready_input;

    logic [NUM_OUTPUTS-1:0] valid_output;
    logic [NUM_OUTPUTS-1:0] ready_output;
    
    generate
    genvar k;
    for (k = 0; k < NUM_INPUTS; k++) begin
        always_comb begin
            valid_input[k] = inputs[k].valid;
            inputs[k].ready = ready_input[k];
        end
    end

    for (k = 0; k < NUM_OUTPUTS; k++) begin
        always_comb begin
            outputs[k].valid = valid_output[k];
            ready_output[k] = outputs[k].ready;
        end
    end
    endgenerate

    stream_controller #(
        .NUM_INPUTS(NUM_INPUTS),
        .NUM_OUTPUTS(NUM_OUTPUTS)
    ) stream_controller_inst (
        .clk, .rst,

        .valid_input, .ready_input,
        .valid_output, .ready_output,
        .consume, .produce,
        .enable
    );

endmodule
