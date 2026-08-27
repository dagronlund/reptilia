"""rustdv targets for the Gecko pipeline stages."""

from scripts.rustdv import RustdvTest

for stage, files in (
    ("fetch", ("rtl/gecko/gecko_fetch.sv",)),
    ("decode", ("rtl/gecko/gecko_decode.sv",)),
    ("execute", ("rtl/gecko/gecko_execute.sv",)),
    ("writeback", ("rtl/gecko/gecko_writeback.sv",)),
):
    RustdvTest(
        name=f"gecko-{stage}",
        family="gecko",
        crate="gecko_tb",
        testcase=f"gecko_{stage}",
        top=f"gecko_{stage}_tb",
        files=files,
        wrapper=f"rtl/gecko/test/rtl/gecko_{stage}_tb.sv",
    )
