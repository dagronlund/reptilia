"""RV32UI binaries executed by the RustDV Gecko core harness."""

from pathlib import Path

from scripts.riscv import RiscvProgram
from scripts.rustdv import RustdvTest

# Gecko does not implement FENCE.I or misaligned data accesses.
for source in sorted(Path("riscv-tests/isa/rv32ui").glob("*.S")):
    if source.stem in {"fence_i", "ma_data"}:
        continue
    RustdvTest(
        name=f"gecko-riscv-{source.stem}",
        family="gecko",
        crate="gecko_tb",
        testcase="gecko_core",
        top="gecko_core_tb",
        files=("rtl/gecko/gecko_core.sv",),
        wrapper="rtl/gecko/test/rtl/gecko_core_tb.sv",
        program=RiscvProgram(
            f"riscv-tests/{source.stem}/{source.stem}",
            (str(source),),
            linker_script="tests/gecko_assembled.ld",
            include_folders=("riscv-tests/isa/macros/scalar/", "tests/"),
        ),
    )
