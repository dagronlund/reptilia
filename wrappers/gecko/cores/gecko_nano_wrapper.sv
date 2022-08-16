module gecko_nano_wrapper 
    import gecko_pkg::*;
#(
    parameter int MEMORY_ADDR_WIDTH = 14,
    parameter STARTUP_PROGRAM = ""
)(
    input wire clk, 
    input wire rst,

    input  wire        tty_in_valid,
    output logic       tty_in_ready,
    input  wire [7:0]  tty_in_data,

    output logic       tty_out_valid,
    input  wire        tty_out_ready,
    output logic [7:0] tty_out_data,

    output logic       exit_flag,
    output logic       error_flag,
    output logic [7:0] exit_code
);

    stream_intf #(.T(logic [7:0])) tty_in (.clk, .rst);
    always_comb tty_in.valid = tty_in_valid;
    always_comb tty_in_ready = tty_in.ready;
    always_comb tty_in.payload = tty_in_data;

    stream_intf #(.T(logic [7:0])) tty_out (.clk, .rst);
    always_comb tty_out_valid = tty_out.valid;
    always_comb tty_out.ready = tty_out_ready;
    always_comb tty_out_data = tty_out.payload;

    gecko_nano #(
        .MEMORY_ADDR_WIDTH(MEMORY_ADDR_WIDTH),
        .STARTUP_PROGRAM(STARTUP_PROGRAM)
    ) inst (
        .clk, 
        .rst,

        .tty_in,
        .tty_out,

        .exit_flag,
        .error_flag,
        .exit_code
    );

endmodule