`ifndef __RV_IO__
`define __RV_IO__

interface rv_io_intf #()();

    logic i, o, t;
    modport out(output o, t, input i);
    modport in(input o, t, output i);
    modport view(input i, o, t);

endinterface

`endif
