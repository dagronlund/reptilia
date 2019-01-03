`timescale 1ns/1ps

module rv_sequential_flow_controller #(
    parameter int NUM_INPUTS = 1,
    parameter int NUM_OUTPUTS = 1
)(
    input logic clk, rst,

    input logic inputs_valid [NUM_INPUTS],
    output logic inputs_ready [NUM_INPUTS],
    input logic inputs_recieved [NUM_INPUTS], // Inputs being accepted
    
    output logic outputs_valid [NUM_OUTPUTS],
    input logic outputs_ready [NUM_OUTPUTS],
    input logic outputs_sent [NUM_OUTPUTS], // Outputs being generated

    output logic enable // Enable state transition
);

    // logic global_output_ready, global_input_valid;

    // Prevents an output from being read more than once
    logic outputs_consumed [NUM_OUTPUTS];
    always_ff @(posedge clk) begin
        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            if (rst || enable) begin
                outputs_consumed[i] <= 0;
            end else if (outputs_ready[i]) begin
                outputs_consumed[i] <= 1;
            end
        end
    end

    /*
    If any output is not ready, then all OTHER outputs are not valid
    If any input is not valid, then all OTHER inputs are not ready
    The OTHER distinction allows easier reasoning when looking at waveforms
    */

    logic outputs_flowing;
    always_comb begin

        // global_output_ready = 1'b1;
        // for (int i = 0; i < NUM_OUTPUTS; i++) begin
        //     global_output_ready &= outputs_ready[i] | ~outputs_sent[i];
        // end

        // global_input_valid = 1'b1;
        // for (int i = 0; i < NUM_INPUTS; i++) begin
        //     global_input_valid &= inputs_valid[i] | ~inputs_recieved[i];
        // end

        // Determines which outputs should be valid
        outputs_flowing = 1'b1;
        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            
            // Outputs are valid if they were sent and haven't been consumed yet
            outputs_valid[i] = outputs_sent[i] & ~outputs_consumed[i];

            for (int j = 0; j < NUM_OUTPUTS; j++) begin
                if (i != j) begin
                    outputs_valid[i] &= outputs_ready[j] | ~outputs_sent[j];
                end
            end

            // Outputs are clear if they are either
            //  a. Being accepted currently 
            //  b. Was already accepted
            //  c. Was never sent originally
            outputs_flowing &= outputs_ready[i] | outputs_consumed[i] | ~outputs_sent[i];   
        end

        enable = outputs_flowing;

        // Determines which inputs should be ready
        for (int i = 0; i < NUM_INPUTS; i++) begin

            // Inputs are ready if they are being awaited and all outputs are flowing
            inputs_ready[i] = inputs_recieved[i] & outputs_flowing;

            for (int j = 0; j < NUM_INPUTS; j++) begin
                if (i != j) begin
                    inputs_ready[i] &= inputs_valid[j] | ~inputs_recieved[j];
                end
            end

            // Inputs are clear if they are either
            //  a. Currently being provided
            //  b. Currently not being accepted
            enable &= inputs_valid[i] | ~inputs_recieved[i];
        end

    end

endmodule

module rv_combinational_flow_controller #(
    parameter int NUM_INPUTS = 1,
    parameter int NUM_OUTPUTS = 1
)(
    input logic inputs_valid [NUM_INPUTS],
    output logic inputs_ready [NUM_INPUTS],
    
    output logic outputs_valid [NUM_OUTPUTS],
    input logic outputs_ready [NUM_OUTPUTS]
);

    logic all_inputs_valid, all_outputs_ready;

    always_comb begin
        all_inputs_valid = 1;
        for (int i = 0; i < NUM_INPUTS; i++) begin
            all_inputs_valid &= inputs_valid[i];
        end

        all_outputs_ready = 1;
        for (int i = 0; i < NUM_OUTPUTS; i++) begin
            all_outputs_ready &= outputs_ready[i];
        end

        outputs_valid = '{NUM_OUTPUTS{all_inputs_valid}};
        inputs_ready = '{NUM_INPUTS{all_outputs_ready}};
    end

endmodule
