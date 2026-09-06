#!/usr/bin/env python3
"""Build and verify the Reptilia RTL."""

from __future__ import annotations

import argparse
from pathlib import Path

from scripts.build import build
from scripts.format import format_systemverilog
from scripts.rustdv import discover_targets, select_targets

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=("build", "test", "format"),
        help="build selected targets, build and run their tests, or format all SystemVerilog files",
    )
    parser.add_argument(
        "--targets",
        nargs="+",
        metavar="TARGET",
        help="select RustDV names or quoted wildcard patterns (space-separated; default: all)",
    )
    parser.add_argument(
        "--output",
        action="store_true",
        help="show output from every completed test (failed output is always shown at the end)",
    )
    parser.add_argument(
        "--wave",
        choices=("vcd", "fst"),
        help="enable waveform support (test also exports waveforms)",
    )
    parser.add_argument(
        "--wave-dir",
        type=Path,
        default=Path("build/waves"),
        help="waveform output directory (default: build/waves)",
    )
    args = parser.parse_args()
    if args.command == "format" and (args.targets is not None or args.wave is not None):
        parser.error("--targets and --wave require build or test")
    if args.targets is not None:
        try:
            select_targets(discover_targets(), tuple(args.targets))
        except ValueError as error:
            parser.error(str(error))

    if args.command == "format":
        format_systemverilog()
    else:
        build(
            run_tests=args.command == "test",
            rustdv_targets=tuple(args.targets) if args.targets is not None else None,
            output=args.output,
            wave=args.wave,
            wave_dir=args.wave_dir,
        )
