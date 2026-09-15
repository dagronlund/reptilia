"""Run CIRCT using the same source lists as Verilator when available."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


def run(
    dotfile_path: Path,
    *,
    top: str,
    lint: bool = False,
) -> subprocess.CompletedProcess[str] | None:
    """Write Moore, LLHD, and HW IR beside the source list when available.

    With lint=True, only import the design, preserving the existing check mode.
    """
    circt_verilog = shutil.which("circt-verilog")
    if circt_verilog is None:
        return None

    modes = (
        [["--import-only"]]
        if lint
        else [
            [f"--ir-{stage}", "-o", str(dotfile_path.with_name(f"circt.{stage}.mlir"))]
            for stage in ("moore", "llhd", "hw")
        ]
    )
    for mode in modes:
        result = subprocess.run(
            [
                circt_verilog,
                "--format=sv",
                "-Wno-multiple-always-assigns",
                *mode,
                f"--top={top}",
                "--Xslang=--relax-enum-conversions",
                "--Xslang=-f",
                f"--Xslang={dotfile_path}",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        if result.returncode:
            print(f"\n{result.stdout}", file=sys.stderr, end="", flush=True)
            result.check_returncode()
    return result
