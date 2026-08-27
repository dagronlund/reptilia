`timescale 1ns/1ps
module stream_stage_tb_wrapper #(
    parameter stream_pkg::stream_pipeline_mode_t PIPELINE_MODE =
        stream_pkg::STREAM_PIPELINE_MODE_REGISTERED
) (
    input logic clk, rst,
    input logic s_valid,
    input logic [31:0] s_payload,
    output logic s_ready,
    output logic o_valid,
    output logic [31:0] o_payload,
    input logic o_ready
);
    stream_intf #(.T(logic[31:0])) stream_in(.clk, .rst);
    stream_intf #(.T(logic[31:0])) stream_out(.clk, .rst);

    always_comb begin
        stream_in.valid = s_valid;
        stream_in.payload = s_payload;
        s_ready = stream_in.ready;
        o_valid = stream_out.valid;
        o_payload = stream_out.payload;
        stream_out.ready = o_ready;
    end

    stream_stage #(
        .PIPELINE_MODE(PIPELINE_MODE),
        .T(logic[31:0])
    ) dut (
        .clk,
        .rst,
        .stream_in,
        .stream_out
    );
endmodule
