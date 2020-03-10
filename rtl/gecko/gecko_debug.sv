//!import std/std_pkg
//!import stream/stream_pkg
//!import riscv/riscv_pkg
//!import riscv/riscv32_pkg
//!import riscv/riscv32i_pkg
//!import gecko/gecko_pkg

`timescale 1ns/1ps

`ifdef __LINTER__
    `include "../std/std_util.svh"
    `include "../mem/mem_util.svh"
`else
    `include "std_util.svh"
    `include "mem_util.svh"
`endif

/*
The debug module supports three different forms of direct access, and only once 
the processor has been put into debug mode. It also support general status
checks and these can be run while the processor runs normally.

1. General Status and Terminal Output
    The debug module can check if the processor has exited and if so what error
    code it reported, as well as restart it if it did exit. It can also read
    bytes from the standard-out FIFO to emulate a very slow debugger terminal
    without needing a separate UART controller. If the debug module does not
    read from this FIFO fast enough it will simply overflow/have undefined
    behavior but not affect or stop the processor operation.

2. Direct Register Access
    The debug module can arbitrarily read or write from any of the 32 RISC-V
    registers. This does not wait for the processor in any form, other than the
    cycle it takes to propagate through the register file.

3. Direct Memory Access
    The debug module can arbitrarily read or write from any memory address
    accessible by the processor. This does have the complication that if the
    memory interconnect is for any reason stalled, then the debug module will
    not be able to get responses. Accesses are performed by sending special
    commands through the execute stage, which in the case of reads will then
    get written-back but are "intercepted" by the debug module instead of
    modifying the register file.

4. Direct CSR Access
    The debug module can arbitrarily read or write control/status registers just
    like the processor would otherwise be able to. Likewise these will propagate
    just like normal instructions but be fed back to the debug module instead of
    writing back anything to the register file.

*/
module gecko_debug
    import std_pkg::*;
    import stream_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import riscv32i_pkg::*;
    import gecko_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX,
    parameter stream_pipeline_mode_t PIPELINE_MODE = STREAM_PIPELINE_MODE_REGISTERED,
    parameter int ENABLE_PRINT = 1
)(
    input wire clk, 
    input wire rst
);

endmodule
