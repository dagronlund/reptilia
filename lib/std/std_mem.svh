`ifndef __STD_MEM__
`define __STD_MEM__

`define STATIC_MATCH_MEM(INTF1, INTF2) \
	`STATIC_ASSERT($bits(INTF1.write_enable) == $bits(INTF2.write_enable)) \
    `STATIC_ASSERT($bits(INTF1.data) == $bits(INTF2.data)) \
    `STATIC_ASSERT($bits(INTF1.addr) == $bits(INTF2.addr)) \
    `STATIC_ASSERT(INTF1.ADDR_BYTE_SHIFTED == INTF2.ADDR_BYTE_SHIFTED)

`endif
