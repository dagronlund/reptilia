`ifndef __RV_IO_DEF__
`define __RV_IO_DEF__

`define RV_IO_PORTS_OUT(PREFIX) \
    `RV_AXI4_LITE_AW_PORTS(output, input, PREFIX)
`define RV_IO_PORTS_IN(PREFIX) \
    `RV_AXI4_LITE_AW_PORTS(input, output, PREFIX)
`define RV_IO_PORTS(FLOW_DIR, BACKFLOW_DIR, PREFIX) \
    FLOW_DIR wire ``PREFIX``_o, BACKFLOW_DIR wire ``PREFIX``_i, \
    FLOW_DIR wire ``PREFIX``_t

`define RV_IO_CONNECT(PREFIX_IN, PREFIX_OUT) \
    assign ``PREFIX_OUT``o = ``PREFIX_IN``o; \
    assign ``PREFIX_IN``i  = ``PREFIX_OUT``i; \
    assign ``PREFIX_OUT``t  = ``PREFIX_IN``t;

`define RV_IO_CONNECT_PORTS(PREFIX_IN, PREFIX_OUT) \
    .``PREFIX_OUT``i(``PREFIX_IN``i), \
    .``PREFIX_OUT``o(``PREFIX_IN``o), \
    .``PREFIX_OUT``t(``PREFIX_IN``t)

`endif
