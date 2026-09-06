"""Independent generated-instruction methodology demo; no binary argument."""

from scripts.rustdv import RustdvTest

for name, testcase in [
    ("random", "GeckoRandomTest"),
    ("corners", "GeckoCornerTest"),
    ("stress", "GeckoStressTest"),
    ("instance", "GeckoInstanceTest"),
    ("named", "GeckoNamedTest"),
    ("passive", "GeckoPassiveTest"),
    ("checker-negative", "GeckoCheckerNegativeTest"),
    ("methodology", "GeckoMethodologyTest"),
    ("config-negative", "GeckoConfigNegativeTest"),
    ("wiring-negative", "GeckoWiringNegativeTest"),
    ("timeout-negative", "GeckoTimeoutNegativeTest"),
]:
    RustdvTest(
        name=f"gecko-generated-{name}",
        family="gecko",
        crate="gecko_random_tb",
        testcase=testcase,
        top="gecko_random_tb",
        files=("rtl/gecko/gecko_core.sv",),
        wrapper="rtl/gecko/test_random/rtl/gecko_random_tb.sv",
    )
