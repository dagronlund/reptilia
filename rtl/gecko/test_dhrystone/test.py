"""Dhrystone executed by the RustDV Gecko core harness."""

from scripts.riscv import RiscvProgram
from scripts.rustdv import RustdvTest

RustdvTest(
    name="gecko-dhrystone",
    family="gecko",
    crate="gecko_tb",
    testcase="gecko_core",
    top="gecko_core_tb",
    files=("rtl/gecko/gecko_core.sv",),
    wrapper="rtl/gecko/test/rtl/gecko_core_tb.sv",
    program=RiscvProgram(
        "dhrystone/dhrystone",
        (
            "tests/lib/crt0.s",
            "tests/lib/libmem.c",
            "tests/lib/libio.c",
            "tests/dhrystone/dhrystone.c",
            "tests/dhrystone/dhrystone_main.c",
            "tests/dhrystone/main.c",
        ),
        linker_script="tests/gecko_compiled.ld",
        opt="-O2",
    ),
)
