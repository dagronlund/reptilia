#!/usr/bin/env python3
"""Build and verify the Reptilia RTL."""

from __future__ import annotations

import argparse

from scripts.build import main

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
    args = parser.parse_args()
    main(
        run_riscv_tests=args.riscv_tests,
        run_dhrystone=args.dhrystone,
    )
