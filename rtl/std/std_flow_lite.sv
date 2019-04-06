`timescale 1ns/1ps

/*
 * ⚛🔋 My abstractions keep getting better! 🔫🏹
 */
module std_flow_lite #(
    parameter int NUM_INPUTS = 1, 
    parameter int NUM_OUTPUTS = 1
)(
    input logic clk, rst,

    input logic [NUM_INPUTS-1:0] valid_input,
    output logic [NUM_INPUTS-1:0] ready_input,

    output logic [NUM_OUTPUTS-1:0] valid_output,
    input logic [NUM_OUTPUTS-1:0] ready_output,

    input logic [NUM_INPUTS-1:0] consume, // If input being read this cycle
    input logic [NUM_OUTPUTS-1:0] produce, // If an output will be present next cycle

    output logic enable // Enable for current state
);

    // Handle asynchronous enable and ready signals
    always_comb begin
        enable = 'b1;

        // Enable if all outputs are either not being produced, not valid, or being consumed
        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            enable &= (!produce[i]) || (ready_output[i]);
        end

        // Enable if all inputs are either consumed and present, or not being consumed
        for (int i = 0; i < NUM_INPUTS; i++) begin
            enable &= (consume[i] && valid_input[i]) || (!consume[i]);
        end

        // Set output valid signals if enabled and being produced
        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            valid_output[i] = produce[i] && enable;
        end

        // Set input ready signals if enabled and being consumed
        for (int i = 0; i < NUM_INPUTS; i++) begin
            ready_input[i] = consume[i] && enable;
        end
    end

endmodule
