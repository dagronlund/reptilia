"""rustdv targets for the memory RTL family."""

from scripts.rustdv import RustdvTest

RustdvTest(
    name="mem-sequential-single",
    family="mem",
    crate="mem_tb",
    testcase="mem_sequential_single",
    top="mem_sequential_single_tb",
    files=(
        "rtl/mem/mem_sequential_single.sv",
        "rtl/mem/mem_stage.sv",
    ),
    wrapper="rtl/mem/test/rtl/mem_sequential_single_tb.sv",
)

RustdvTest(
    name="mem-sequential-double",
    family="mem",
    crate="mem_tb",
    testcase="mem_sequential_double",
    top="mem_sequential_double_tb",
    files=("rtl/mem/mem_sequential_double.sv",),
    wrapper="rtl/mem/test/rtl/mem_sequential_double_tb.sv",
)

RustdvTest(
    name="mem-sequential-read-write",
    family="mem",
    crate="mem_tb",
    testcase="mem_sequential_read_write",
    top="mem_sequential_read_write_tb",
    files=("rtl/mem/mem_sequential_read_write.sv",),
    wrapper="rtl/mem/test/rtl/mem_sequential_read_write_tb.sv",
)

RustdvTest(
    name="mem-split-merge",
    family="mem",
    crate="mem_tb",
    testcase="mem_split_merge",
    top="mem_split_merge_tb",
    files=("rtl/mem/mem_merge.sv", "rtl/mem/mem_split.sv"),
    wrapper="rtl/mem/test/rtl/mem_split_merge_tb.sv",
)
