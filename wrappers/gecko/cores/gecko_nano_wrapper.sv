module gecko_nano_wrapper 
    import gecko_pkg::*;
#(
    parameter int MEMORY_ADDR_WIDTH = 14,
    parameter STARTUP_PROGRAM = ""
)(
    input wire clk, 
    input wire rst,

    output logic faulted_flag,
    output logic finished_flag,

    output logic       print_out_valid,
    input  wire        print_out_ready,
    output logic [7:0] print_out_data
);

    stream_intf #(.T(logic [7:0])) print_out (.clk, .rst);

    always_comb print_out_valid = print_out.valid;
    always_comb print_out.ready = print_out_ready;
    always_comb print_out_data = print_out.payload;

    gecko_nano #(
        .MEMORY_ADDR_WIDTH(MEMORY_ADDR_WIDTH),
        .STARTUP_PROGRAM(STARTUP_PROGRAM)
    ) inst (
        .clk, 
        .rst,

        .print_out,

        .finished_flag,
        .faulted_flag
    );

endmodule