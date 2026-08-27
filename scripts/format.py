"""SystemVerilog formatting utilities."""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VERIBLE_FORMAT_CONFIG = REPO_ROOT / ".rules.verible_format"


def format_systemverilog() -> None:
    """Format every SystemVerilog source file in the repository."""
    source_files = sorted(REPO_ROOT.rglob("*.sv"))
    if not source_files:
        return

    subprocess.run(
        [
            "verible-verilog-format",
            f"--flagfile={VERIBLE_FORMAT_CONFIG}",
            "--inplace",
            *(path.relative_to(REPO_ROOT) for path in source_files),
        ],
        cwd=REPO_ROOT,
        check=True,
    )
