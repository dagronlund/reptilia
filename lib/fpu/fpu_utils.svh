`ifndef __FPU_UTILS__
`define __FPU_UTILS__

package fpu_utils;

    function automatic logic get_sticky_bit_27(
        input logic [26:0] num,
        input logic [4:0] shift_amount
    );
        logic sticky_shift = 'b0;
        for (int i = 0; i <= shift_amount; i++) begin
            sticky_shift |= num[i];
        end
        return sticky_shift;
    endfunction

    function automatic logic [5:0] get_leading_zeros_47(
        input logic [46:0] num
    );
        for (int i = 6'd46; i >= 0; i--) begin
            if (num[i] == 'b1) begin
                return 6'd46 - i;
            end
        end
        return 6'd47;
    endfunction

    function automatic logic [4:0] get_leading_zeros_27(
        input logic [26:0] num
    );
        for (int i = 5'd26; i >= 0; i--) begin
            if (num[i] == 'b1) begin
                return 5'd26 - i;
            end
        end
        return 5'd27;
    endfunction

endpackage

`endif
