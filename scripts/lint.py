"""Print slang diagnostics for the project's Verilog sources."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def lint_verilog() -> int:
    """Lint RTL, wrappers, and testbenches, preserving slang's output and status."""
    slang = shutil.which("slang")
    if slang is None:
        print("slang was not found on PATH; install slang to run lint", file=sys.stderr)
        return 1

    source_files = sorted(
        path.relative_to(REPO_ROOT)
        for folder in ("rtl", "wrappers", "tb")
        for path in (REPO_ROOT / folder).rglob("*")
        if path.is_file() and path.suffix in (".sv", ".v")
    )
    if not source_files:
        return 0

    return subprocess.run(
        [slang, "--lint-only", "--error-limit=0", "-I", "rtl", *source_files],
        cwd=REPO_ROOT,
        check=False,
    ).returncode
