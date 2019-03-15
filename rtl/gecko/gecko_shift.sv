`timescale 1ns/1ps

`include "../../lib/std/std_util.svh"

`include "../../lib/gecko/gecko.svh"

`BUILD_STREAM_INTF_PACKAGED(gecko_base, gecko_shift_command_t)
`BUILD_STREAM_INTF_PACKAGED(gecko_base, gecko_reg_result_t)

module gecko_shift #(
    parameter SHIFT_COMPLEXITY = 1
)(
    std_stream_intf.in command_in,
    std_stream_intf.out result_out
);

    import gecko_base::*;

    `STATIC_ASSERT($size(command_in.payload) == $size(gecko_shift_command_t))
    `STATIC_ASSERT($size(result_out.payload) == $size(gecko_reg_result_t))

    gecko_shift_command_t command;
    gecko_reg_result_t result;

    always_comb begin
        command = gecko_shift_command_t'(command_in.payload);

        

        result_out.payload = result;
    end

endmodule
