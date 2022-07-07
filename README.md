# reptilia
SystemVerilog RISC-V implementation and libraries

## Build/Verify

Before building you need to install three different tools, Verilator, RISCV-GNU, 
and LLVM. Once these are installed you need to set three environment variables
to reflect where these are installed.
- $VERILATOR_ROOT
- $LLVM_ROOT
- $RISCV_GNU_ROOT

The RTL can then be verified by running `./build.py`, which will compile the
test programs, generate the verilator models, and then compile the verilator
models with the test programs loaded into memory.

## Cores

### Gecko
Small RV32I core with flexible memory interfaces and lightweight AXI interfaces

### Basilisk
Gecko core with both integer math, floating point, and vector extensions

### Iguana
Large RV32G core with multiple coherent memory interfaces and full-featured AXI interfaces

### Komodo
Iguana core with supervisor extensions for booting Unix operating systems

## Folder Structure

rtl/
	SystemVerilog (\*.sv) files containing modules that are going to be synthesized into logic 

tb/
	SystemVerilog testbenches for verifying the RTL behavior

tb_cpp/
	C++ testbenches for verifying the RTL behavior with Verilator

tests/
	C/C++/Assembly code for verifying RISC-V core behavior

wrappers/
	SystemVerilog wrappers for verilating/linting RTL files with top-level interfaces

## Random Notes
1. Use $bit(interface.bus) instead of interface.BUS_WIDTH to parameterize bit widths when possible
2. When referencing a parameter or type passed through an interface port (i.e my_intf.BUS_WIDTH or $bits(my_intf.bus)), make sure that it is assigned to a localparam, not a parameter
