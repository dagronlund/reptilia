`ifndef __FPU_ULTRASCALE_NATIVE__
`define __FPU_ULTRASCALE_NATIVE__

package fpu_ultrascale_native;

    function automatic logic [47:0] dsp48_mac(
        input logic signed [26:0] a,
        input logic signed [17:0] b,
        input logic signed [47:0] c
    );
        return (a * b) + c;
    endfunction

endpackage

`endif
