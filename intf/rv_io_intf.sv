`timescale 1ns/1ps

interface rv_io_intf #()();

    logic i, o, t;
    modport out(output o, t, input i);
    modport in(input o, t, output i);
    modport view(input i, o, t);

endinterface
