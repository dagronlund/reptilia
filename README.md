# risc-v
SystemVerilog RISC-V implementation and libraries

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
	Systemverilog (\*.sv) files containing modules that are going to be synthesized into logic 

intf/
	Systemverilog (\*.sv) files containing interfaces that will be used to connect different modules together

lib/
	Systemverilog header (\*.svh) files containing packages with enumerations, structs, and functions that will contain shared behavior between modules.

## Stream Libraries
Managing and pipelining streams is a critical part of digital logic design, and a consistent naming convention and library support is crucial part of maintainable design.

The following standard stream components are provided
1. rv_stream_stage
	Provides a combinational break for the datapath but leaves the backflow path (ready flag) propagating combinationally through it.
2. rv_stream_break
	Provides a complete combinational break for twice the register resources.
3. rv_stream_reset
	Provides a purely combinational reset domain converter for two synchronous resets.

The following standard state machine controller are provided for working with streams
1. rv_seq_flow_controller
	...
2. rv_comb_flow_controler
	...


## Pre-Preprocessor Notes
To run this on windows requires Cygwin installed with the following packages:
- bison
- flex
- gcc-g++
- libcrypt-devel
- make
- perl

[Installation Instructions](https://www.veripool.org/projects/verilog-perl/wiki/Installing)

```
git clone http://git.veripool.org/git/Verilog-Perl
perl Makefile.PL
make
```

To run the preprocessor for wrappers in this repository use the following command as an example (in Cygwin)

```
perl vppreproc --noline --noblank --nocomment +define+__PRE_PREPROCESSOR__ wrapper.sv --o wrapper_processed.sv
```

## Random Notes
1. ABSOLUTELY NEVER put an interface or module definition in a header file, Vivado loses it brainz
2. Use $bit(interface.bus) instead of interface.BUS_WIDTH to parameterize bit widths when possible
3. When referencing a parameter or type passed through an interface port (i.e my_intf.BUS_WIDTH or $bits(my_intf.bus)), make sure that it is assigned to a localparam, not a parameter
4. Always put interfaces in a seperate \*.sv file and only put packages in \*.svh files.
5. Never include a header file from another header file, the simulator can handle this but the synthesis engine cannot properly handle the relative includes. Instead the file using those the primary header needs to include the secondary header itself. Vivado has the ```-include_dirs /somepath/somewhere``` option for synthesis but all of directories with header files would need to be included here, and usually with absolute paths since these paths are otherwise relative to the directory that Vivado was started in.
