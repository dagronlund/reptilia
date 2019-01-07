# risc-v
SystemVerilog RISC-V implementation and libraries

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

## Random Notes
1. ABSOLUTELY NEVER put an interface or module definition in a header file, Vivado loses it brainz
2. Use $bit(interface.bus) instead of interface.BUS_WIDTH to parameterize bit widths when possible
3. When referencing a parameter or type passed through an interface port (i.e my_intf.BUS_WIDTH or $bits(my_intf.bus)), make sure that it is assigned to a localparam, not a parameter
