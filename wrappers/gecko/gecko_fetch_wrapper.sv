module gecko_fetch_wrapper 
    import gecko_pkg::*;
(
    input wire clk, 
    input wire rst,

    input  wire                   jump_command_valid,
    output logic                  jump_command_ready,
    input  gecko_jump_operation_t jump_command_data,

    output logic                         instruction_command_valid,
    input  wire                          instruction_command_ready,
    output gecko_instruction_operation_t instruction_command_data,

    output logic                         instruction_request_valid,
    input  wire                          instruction_request_ready,
    output logic                         instruction_request_read_enable,
    output logic [3:0]                   instruction_request_write_enable,
    output logic [31:0]                  instruction_request_addr,
    output logic [31:0]                  instruction_request_data,
    output logic [0:0]                   instruction_request_id,
    output logic                         instruction_request_last
);

    stream_intf #(.T(gecko_jump_operation_t))        jump_command        (.clk, .rst);
    stream_intf #(.T(gecko_instruction_operation_t)) instruction_command (.clk, .rst);

    mem_intf #(.DATA_WIDTH(32), .ADDR_WIDTH(32)) instruction_request (.clk, .rst);

    always_comb jump_command.valid = jump_command_valid;
    always_comb jump_command_ready = jump_command.ready;
    always_comb jump_command.payload = jump_command_data;

    always_comb instruction_command_valid = instruction_command.valid;
    always_comb instruction_command.ready = instruction_command_ready;
    always_comb instruction_command_data  = instruction_command.payload;

    always_comb instruction_request_valid        = instruction_request.valid;
    always_comb instruction_request.ready        = instruction_request_ready;
    always_comb instruction_request_read_enable  = instruction_request.read_enable;
    always_comb instruction_request_write_enable = instruction_request.write_enable;
    always_comb instruction_request_addr         = instruction_request.addr;
    always_comb instruction_request_data         = instruction_request.data;
    always_comb instruction_request_id           = instruction_request.id;
    always_comb instruction_request_last         = instruction_request.last;

    gecko_fetch inst (
        .clk, 
        .rst,

        .jump_command,
        .instruction_command,
        .instruction_request
    );

endmodule
