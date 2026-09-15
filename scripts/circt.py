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
    """Write circt.mlir beside the source list, or only lint, when available."""
    circt_verilog = shutil.which("circt-verilog")
    if circt_verilog is None:
        return None

    result = subprocess.run(
        [
            circt_verilog,
            "--format=sv",
            "-Wno-multiple-always-assigns",
            *(
                ["--import-only"]  # Run --import-only instead of --lint-only
                if lint
                else ["-o", str(dotfile_path.with_name("circt.mlir"))]
            ),
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
