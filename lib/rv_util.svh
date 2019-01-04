`ifndef __RV_UTIL__
`define __RV_UTIL__

/*
Utilities for RISC-V development
*/

`define STRINGIFY(str) `"str`"

`define STATIC_ASSERT(condition) \
    generate \
    if (!condition) begin \
        initial begin \
            $error("FAILED ASSERTION: %s:%d, %s", `__FILE__, `__LINE__, `STRINGIFY(condition)); \
        end \
    end \
    endgenerate

`define BUILD_STREAM_INTF(DATA_TYPE) \
    `ifndef __``DATA_TYPE``_STREAM_INTF__ \
    interface ``DATA_TYPE``_stream_intf(); \
        DATA_TYPE data; logic valid, ready, block; \
        modport out(output valid, data, block, input ready); \
        modport in(input valid, data, output ready, block); \
        modport view(input valid, data, ready, block); \
    endinterface \
    `define __``DATA_TYPE``_STREAM_INTF__ \
    `endif

`define BUILD_MAYBE_STRUCT(DATA_TYPE) \
    `ifndef __``DATA_TYPE``_MAYBE_STRUCT__ \
    typedef struct { \
        DATA_TYPE data; \
        logic valid; \
    } ``DATA_TYPE``_maybe; \
    `define __``DATA_TYPE``_MAYBE_STRUCT__ \
    `endif

`define BUILD_WRAPPER_TYPES(DATA_TYPE) \
    `BUILD_STREAM_INTF(DATA_TYPE) \
    `BUILD_MAYBE_STRUCT(DATA_TYPE)

`endif
