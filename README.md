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