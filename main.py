#!/usr/bin/env python3
"""Build and verify the Reptilia RTL."""

from __future__ import annotations

import argparse
from pathlib import Path

from scripts.build import build
from scripts.format import format_systemverilog

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--riscv-tests",
        action="store_true",
        help="run the RISC-V ISA tests against the Gecko simulator",
    )
    parser.add_argument(
        "--dhrystone",
        action="store_true",
        help="run Dhrystone against the Gecko simulator",
    )
    parser.add_argument(
        "--rustdv-tests",
        action="store_true",
        help="run the rustdv Gecko, memory, and stream regressions",
    )
    parser.add_argument(
        "--format",
        action="store_true",
        help="format all SystemVerilog files with Verible",
    )
    parser.add_argument(
        "--wave",
        choices=("vcd", "fst"),
        help="export optional rustdv waveforms in the selected format",
    )
    parser.add_argument(
        "--wave-dir",
        type=Path,
        default=Path("build/waves"),
        help="waveform output directory (default: build/waves)",
    )
    args = parser.parse_args()

    if args.format:
        format_systemverilog()

    run_build = (
        not args.format
        or args.riscv_tests
        or args.dhrystone
        or args.rustdv_tests
        or args.wave is not None
    )
    if run_build:
        build(
            run_riscv_tests=args.riscv_tests,
            run_dhrystone=args.dhrystone,
            run_rustdv_tests=args.rustdv_tests,
            wave=args.wave,
            wave_dir=args.wave_dir,
        )
