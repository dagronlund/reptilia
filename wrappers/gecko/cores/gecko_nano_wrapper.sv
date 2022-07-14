module gecko_nano_wrapper 
    import gecko_pkg::*;
#(
    parameter int MEMORY_ADDR_WIDTH = 14,
    parameter STARTUP_PROGRAM = ""
)(
    input wire clk, 
    input wire rst,

    output logic        debug_info_jump_valid,
    output logic        debug_info_register_write,
    output logic [4:0]  debug_info_register_addr,
    output logic [31:0] debug_info_jump_address,
    output logic [31:0] debug_info_register_data,

    // stream_intf.in  tty_in, // logic [7:0]
    // stream_intf.out tty_out, // logic [7:0]



    // output logic faulted_flag,
    // output logic finished_flag,

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

    gecko_debug_info_t debug_info;
    always_comb debug_info_jump_valid     = debug_info.jump_valid;
    always_comb debug_info_register_write = debug_info.register_write;
    always_comb debug_info_register_addr  = debug_info.register_addr;
    always_comb debug_info_jump_address   = debug_info.jump_address;
    always_comb debug_info_register_data  = debug_info.register_data;

    gecko_nano #(
        .MEMORY_ADDR_WIDTH(MEMORY_ADDR_WIDTH),
        .STARTUP_PROGRAM(STARTUP_PROGRAM)
    ) inst (
        .clk, 
        .rst,

        .debug_info,

        .tty_in,
        .tty_out,

        .exit_flag,
        .error_flag,
        .exit_code
    );

endmodule