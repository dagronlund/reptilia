module gecko_fetch_predictor_wrapper 
    import gecko_pkg::*;
(
    input wire clk, 
    input wire rst,

    input gecko_pc_t pc,

    input  wire                   jump_command_valid,
    output logic                  jump_command_ready,
    input  gecko_jump_operation_t jump_command_data,

    output logic predictor_valid, 
    output logic predictor_taken,
    output gecko_pc_t predictor_prediction,
    output gecko_predictor_history_t predictor_history,

    output logic reset_done
);

    stream_intf #(.T(gecko_jump_operation_t)) jump_command (.clk, .rst);

    always_comb jump_command.valid = jump_command_valid;
    always_comb jump_command_ready = jump_command.ready;
    always_comb jump_command.payload = jump_command_data;

    gecko_fetch_predictor inst (
        .clk, 
        .rst,

        .pc,

        .jump_command,

        .predictor_valid, 
        .predictor_taken,
        .predictor_prediction,
        .predictor_history,

        .reset_done
    );

endmodule
