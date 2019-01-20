`ifndef __RV_UTIL__
`define __RV_UTIL__

/*
Utilities for RISC-V development

Original STATIC_ASSERT from Reid Long
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
    interface ``DATA_TYPE``_stream_intf(input logic clk = 'b0, rst = 'b0); \
        DATA_TYPE data; logic valid, ready, block; \
        modport out(output valid, data, block, input ready); \
        modport in(input valid, data, output ready, block); \
        modport view(input valid, data, ready, block); \
        task send(input DATA_TYPE data_in); \
            data <= data_in; valid <= 1'b1; @ (posedge clk); while (!ready) @ (posedge clk); valid <= 1'b0; \
        endtask \
        task recv(output DATA_TYPE data_out); \
            ready <= 1'b1; @ (posedge clk); while (!valid) @ (posedge clk); ready <= 1'b0; data_out = data; \
        endtask \
    endinterface \
    `define __``DATA_TYPE``_STREAM_INTF__ \
    `endif

`endif