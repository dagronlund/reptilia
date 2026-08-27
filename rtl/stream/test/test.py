"""rustdv targets for the stream RTL family."""

from scripts.rustdv import RustdvTest

STAGE_MODES = (
    ("transparent", "2'h0"),
    ("registered", "2'h1"),
    ("buffered", "2'h2"),
    ("elastic", "2'h3"),
)

FIFO_MODES = (
    ("combinational", "2'h0"),
    ("combinational-registered", "2'h1"),
    ("sequential", "2'h2"),
    ("sequential-registered", "2'h3"),
)

for name, value in STAGE_MODES:
    RustdvTest(
        name=f"stream-stage-{name}",
        family="stream",
        crate="stream_tb",
        testcase="stream_stage",
        top="stream_stage_tb",
        files=("rtl/stream/stream_stage.sv",),
        wrapper="rtl/stream/test/rtl/stream_stage_tb.sv",
        parameters=(("PIPELINE_MODE", value),),
    )

for name, value in FIFO_MODES:
    RustdvTest(
        name=f"stream-fifo-{name}",
        family="stream",
        crate="stream_tb",
        testcase="stream_fifo",
        top="stream_fifo_tb",
        files=("rtl/stream/stream_fifo.sv",),
        wrapper="rtl/stream/test/rtl/stream_fifo_tb.sv",
        parameters=(("FIFO_MODE", value),),
    )

RustdvTest(
    name="stream-split-merge",
    family="stream",
    crate="stream_tb",
    testcase="stream_split_merge",
    top="stream_split_merge_tb",
    files=("rtl/stream/stream_merge.sv", "rtl/stream/stream_split.sv"),
    wrapper="rtl/stream/test/rtl/stream_split_merge_tb.sv",
)

RustdvTest(
    name="stream-ordered-merge",
    family="stream",
    crate="stream_tb",
    testcase="stream_ordered_merge",
    top="stream_merge_tb",
    files=("rtl/stream/stream_merge.sv",),
    wrapper="rtl/stream/test/rtl/stream_merge_tb.sv",
)
