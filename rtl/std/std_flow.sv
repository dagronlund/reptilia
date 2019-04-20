`timescale 1ns/1ps

/*
 * 👾🌌 You have no idea how cool this module is. 🔭🇺🇸
 */
module std_flow #(
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

    output logic enable, // Enable for current state and buses
    output logic [NUM_OUTPUTS-1:0] enable_output // Enable for each output stream
);

    // Handle synchronous output valid signal
    always_ff @(posedge clk) begin
        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            if(rst) begin
                valid_output[i] <= 'b0;
            end else if (enable_output[i]) begin
                valid_output[i] <= produce[i]; 
            end else if (ready_output[i]) begin
                valid_output[i] <= 'b0;
            end
        end
    end

    // Handle asynchronous enable and ready signals
    always_comb begin
        enable = 'b1;

        // Enable if all outputs are either not being produced, not valid, or being consumed
        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            enable &= (!produce[i]) || (!valid_output[i]) || (ready_output[i]);   
        end

        // Enable if all inputs are either consumed and present, or not being consumed
        for (int i = 0; i < NUM_INPUTS; i++) begin
            enable &= (consume[i] && valid_input[i]) || (!consume[i]);
        end

        // Enable individual outputs if being produced and main enable
        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            enable_output[i] = produce[i] && enable;
        end

        // Set input ready signals if enabled and being consumed
        for (int i = 0; i < NUM_INPUTS; i++) begin
            ready_input[i] = consume[i] && enable;
        end
    end

endmodule
