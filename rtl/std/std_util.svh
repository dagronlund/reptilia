`ifndef __STD_UTIL__
`define __STD_UTIL__

/*
Preprocessor utilities for SV development, original STATIC_ASSERT from Reid
Long. Honestly though, you should hate using these as much as I do, the
preprocessor is evil and will burn you eventually.
*/

function MAX(int a, int b);
    return (a > b) ? a : b;
endfunction

function MIN(int a, int b);
    return (a < b) ? a : b;
endfunction

// let MAX(a,b) = (a > b) ? a : b;
// let MIN(a,b) = (a < b) ? a : b;

`define STRINGIFY(str) `"str`"

`define STATIC_ASSERT(condition) \
    `ifndef __SYNTH_ONLY__ \
    generate \
    if (!(condition)) begin \
        initial begin \
            $error("FAILED ASSERTION: %s:%d, %s", `__FILE__, `__LINE__, `STRINGIFY(condition)); \
        end \
    end \
    endgenerate \
    `endif

`define PROCEDURAL_ASSERT(condition) \
    `ifndef __SYNTH_ONLY__ \
    initial begin \
        assert (condition) else $error("FAILED ASSERTION: %s:%d, %s", `__FILE__, `__LINE__, `STRINGIFY(condition)); \
    end \
    `endif

`define INLINE_ASSERT(condition) \
    assert (condition) else $error("FAILED ASSERTION: %s:%d, %s", `__FILE__, `__LINE__, `STRINGIFY(condition));

`define BUILD_STREAM_INTF_EXPLICIT(FULL_NAME, PREFIX, DATA_TYPE) \
    `ifndef __``FULL_NAME``_STREAM_INTF__ \
    interface ``FULL_NAME``_stream_intf(input logic clk = 'b0, rst = 'b0); \
        PREFIX``DATA_TYPE data; logic valid, ready; \
        modport out(output valid, data, input ready); \
        modport in(input valid, data, output ready); \
        modport view(input valid, data, ready); \
        task send(input PREFIX``DATA_TYPE data_in); \
            data <= data_in; valid <= 1'b1; @ (posedge clk); while (!ready) @ (posedge clk); valid <= 1'b0; \
        endtask \
        task recv(output PREFIX``DATA_TYPE data_out); \
            ready <= 1'b1; @ (posedge clk); while (!valid) @ (posedge clk); ready <= 1'b0; data_out = data; \
        endtask \
    endinterface \
    `define __``FULL_NAME``_STREAM_INTF__ \
    `endif

`define BUILD_STREAM_INTF_PACKAGED(PACKAGE, DATA_TYPE) \
    `BUILD_STREAM_INTF_EXPLICIT(DATA_TYPE, PACKAGE::, DATA_TYPE)

`define BUILD_STREAM_INTF(DATA_TYPE) \
    `BUILD_STREAM_INTF_EXPLICIT(DATA_TYPE, , DATA_TYPE)

`endif
