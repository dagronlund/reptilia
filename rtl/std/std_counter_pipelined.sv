//!import std/std_pkg.sv
//!import std/std_register.sv

module std_counter_pipelined
    import std_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter int PIPELINE_WIDTH = 32,
    parameter int PIPELINE_COUNT = 2,
    parameter int WIDTH = PIPELINE_WIDTH * PIPELINE_COUNT,
    parameter logic [WIDTH-1:0] RESET_VECTOR = 'b0
)(
    input wire clk, 
    input wire rst,

    input wire [PIPELINE_WIDTH-1:0] increment,
    
    output logic [WIDTH-1:0] value,

    output logic overflowed
);

    typedef logic [WIDTH-1:0]          counter_t;
    typedef logic [PIPELINE_WIDTH-1:0] partial_counter_t;
    typedef logic [PIPELINE_WIDTH:0]   partial_sum_t;

    logic [WIDTH-1:0] stages  [PIPELINE_COUNT];
    logic             carries [PIPELINE_COUNT];

    logic [WIDTH-1:0] stages_next  [PIPELINE_COUNT];
    logic             carries_next [PIPELINE_COUNT];

    logic [PIPELINE_WIDTH-1:0] stages_sum [PIPELINE_COUNT];
    logic                      stages_carry [PIPELINE_COUNT];

    always_comb value = stages[PIPELINE_COUNT-1];

    generate
    genvar k;
    for (k = 0; k < PIPELINE_COUNT; k++) begin

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic [WIDTH-1:0]),
            .RESET_VECTOR('b0)
        ) stage_register_inst (
            .clk, .rst,
            .enable('b1),
            .next(stages_next[k]),
            .value(stages[k])
        );

        std_register #(
            .CLOCK_INFO(CLOCK_INFO),
            .T(logic),
            .RESET_VECTOR('b0)
        ) carry_register_inst (
            .clk, .rst,
            .enable('b1),
            .next(carries_next[k]),
            .value(carries[k])
        );

        partial_sum_t partial_sum;

        always_comb begin
            if (k == 0) begin
                partial_sum = partial_sum_t'(stages[k]) + partial_sum_t'(increment);
                stages_next[k] = '0;
            end else begin
                partial_sum = partial_sum_t'(stages[k]) + partial_sum_t'(increment);
                stages_next[k] = stages[k-1];
            end
            stages_next[k] |= counter_t'(partial_sum[PIPELINE_WIDTH-1:0]) << (PIPELINE_WIDTH * k);
            carries_next[k] = partial_sum[PIPELINE_WIDTH];
        end
    end
    endgenerate

    logic overflowed_next;
    always_comb overflowed_next = overflowed || carries_next[PIPELINE_COUNT-1];

    std_register #(
        .CLOCK_INFO(CLOCK_INFO),
        .T(logic),
        .RESET_VECTOR('b0)
    ) overflowed_register_inst (
        .clk, .rst,
        .enable('b1),
        .next(overflowed_next),
        .value(overflowed)
    );

endmodule
